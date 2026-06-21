

import { randomUUID } from "node:crypto"
import { execFileSync, execSync } from "node:child_process"
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"
import { ReadTool } from "@moonshot-ai/agent-core/tools/builtin/file/read"
import { GrepTool } from "@moonshot-ai/agent-core/tools/builtin/file/grep"
import { GlobTool } from "@moonshot-ai/agent-core/tools/builtin/file/glob"
import { FetchURLTool } from "@moonshot-ai/agent-core/tools/builtin/web/fetch-url"
import { WebSearchTool } from "@moonshot-ai/agent-core/tools/builtin/web/web-search"
import { LocalFetchURLProvider } from "@moonshot-ai/agent-core/tools/providers/local-fetch-url"
import { MoonshotWebSearchProvider } from "@moonshot-ai/agent-core/tools/providers/moonshot-web-search"
import { KosongLLM } from "@moonshot-ai/agent-core/agent/turn/kosong-llm"
import { ToolCallDeduplicator } from "@moonshot-ai/agent-core/agent/turn/tool-dedup"
import { createLoopEventDispatcher, runTurn } from "@moonshot-ai/agent-core/loop/index"
import { isAbortError, isMaxStepsExceededError } from "@moonshot-ai/agent-core/loop/errors"
import { LocalKaos } from "@moonshot-ai/kaos"
import { createProvider, createToolMessage, createUserMessage } from "@moonshot-ai/kosong"
import OpenAI from "openai"
import { parse as parseToml } from "smol-toml"
// Pure chain/budget decision logic (tested in chain-logic.test.mjs). esbuild
// inlines this into bridge.bundle.mjs at build time, so the bundle stays
// self-contained (the runner only ever executes the bundle).
import { errorText, providerFailure, computeAttemptBudget, hasVerdict, looksNarrated, needsAttentionWithoutFindings, extractVerdictObject, inferLineage, isMinimaxM3Model, isCacheableReviewTool, mergeModelParamsCatalog, modelsListUrl, resolveModelReviewParams, resolveModelsCatalogBaseUrl, stableToolCacheKey } from "./chain-logic.mjs"
// Gate on the SERVING provider, not the declared one: a chain like opencode-go ->
// ollama-cloud runs the review on ollama after opencode-go 429s, so gating must
// happen per-attempt here (inside the bridge, where the actual provider is known)
// rather than once in the outer runner on the model-arg prefix.
import { withProviderSlot } from "./provider-gate.mjs"
// Defensive parser for DeepSeek-V3 inline tool-call tokens that some backends
// (ollama-cloud serving cogito) leak into content instead of structuring.
import { wrapWithDeepSeekToolFallback } from "./deepseek-tool-parser.mjs"
// MCP support: let reviewers reach out to configured MCP servers (e.g. DeepWiki)
// for ground-truth on third-party dependencies instead of guessing.
import { McpConnectionManager } from "@moonshot-ai/agent-core/mcp/connection-manager"
import { mcpResultToExecutableOutput } from "@moonshot-ai/agent-core/mcp/output"

const MODELS_JSON = JSON.parse(readFileSync(new URL("../models.json", import.meta.url), "utf8"))
const SEEDS = MODELS_JSON.lineage_provider_seeds || {}
const PROVIDER_PRIORITY = MODELS_JSON.provider_priority || []
const DIRECT_PROVIDER_BY_LINEAGE = MODELS_JSON.direct_provider_by_lineage || {}
const LINEAGES = Object.keys(SEEDS)
const MODEL_PARAMS_JSON = MODELS_JSON.model_params || {}
const MODEL_PARAMS_DEFAULT = MODEL_PARAMS_JSON._default || {}
const DISABLED_MODELS = new Set(Object.keys(MODELS_JSON.disabled_models || {}))
const KIMI_BIN = process.env.KIMI_BIN || "kimi"

function modelParamsCfg(label) {
  const fromToml = record(config.models?.[label]) || {}
  const fromCatalog = modelCatalogParams(label)
  const fromJson = { ...MODEL_PARAMS_DEFAULT, ...(record(MODEL_PARAMS_JSON[label]) || {}) }
  return mergeModelParamsCatalog(mergeModelParamsCatalog(fromCatalog, fromJson), fromToml)
}

function kimiCatalogModels(providerID) {
  try {
    const out = execFileSync(KIMI_BIN, ["provider", "catalog", "list", providerID, "--json"], {
      encoding: "utf8",
      timeout: 15000,
      maxBuffer: 8 * 1024 * 1024,
    })
    const body = JSON.parse(out)
    return Array.isArray(body?.models) ? body.models : []
  } catch {
    return []
  }
}

const KIMI_CATALOG_CACHE = new Map()

function modelCatalogParams(label) {
  const slash = String(label || "").indexOf("/")
  if (slash < 0) return {}
  const providerID = label.slice(0, slash)
  const modelID = label.slice(slash + 1)
  if (providerID === "managed:kimi-code" || providerID === "kimi-code") return {}
  if (!KIMI_CATALOG_CACHE.has(providerID)) {
    KIMI_CATALOG_CACHE.set(providerID, kimiCatalogModels(providerID))
  }
  const normalized = KIMI_CATALOG_CACHE.get(providerID).find((m) => m?.id === modelID)
  if (!normalized) return {}

  const out = { _modelsDev: true }
  if (normalized.maxOutputSize) out.max_output_size = normalized.maxOutputSize
  if (normalized.reasoningKey) out.reasoning_key = normalized.reasoningKey
  const context = normalized.capability?.max_context_tokens
  if (Number.isFinite(context) && context > 0) out.max_context_size = context
  return out
}

// Structured error taxonomy for provider failures (rate_limit, connection, context_overflow, timeout, auth, other).
// kimi-code's 403 quota/permission_error is mapped to rate_limit so the failover chain continues
// and the error is reported as 429-style for lineage testing.
function classifyProviderError(err, providerID) {
  const msg = String((err && (err.message || err.error || err)) || err || "").toLowerCase()
  if (/429|rate.?limit|too many/i.test(msg)) return "rate_limit"
  if (providerID === "managed:kimi-code" || /kimi-code|kimi-for-coding/.test(providerID)) {
    if (/403|quota|permission_error|billing|usage limit/i.test(msg)) return "rate_limit"
  }
  if (/timeout|etimedout|esockettimedout/i.test(msg)) return "timeout"
  if (/connection|enotfound|econnrefused|network/i.test(msg)) return "connection"
  if (/context|length|token|413|414/i.test(msg)) return "context_overflow"
  if (/401|403|auth|unauthorized|permission/i.test(msg)) return "auth"
  return "other"
}

// Wire-format and baseUrl overrides that cannot be derived from models.dev or
// Kimi config today. Keep these at the narrowest level possible: OpenCode Go has
// per-model format support, so only specific model_refs should override the
// provider default when live evidence proves the default format is rejected.
const WIRE = {
  anthropic: new Set(["zai", "xiaomi-token-plan-ams", "managed:kimi-code", "minimax-coding-plan"]),
  baseUrl: {
    "managed:kimi-code": "https://api.kimi.com/coding",
  },
}

function protocolForEntry(providerID, modelRef) {
  const protocol = record(MODEL_PARAMS_JSON[modelRef])?.protocol
  if (protocol === "anthropic" || protocol === "openai" || protocol === "kimi") return protocol
  return WIRE.anthropic.has(providerID) ? "anthropic" : "openai"
}

function baseUrlForEntry(providerID, modelRef) {
  const base = record(MODEL_PARAMS_JSON[modelRef])?.base_url
  return typeof base === "string" ? base : (WIRE.baseUrl[modelRef] || WIRE.baseUrl[providerID])
}

function versionSort(a, b) {
  const ra = a.match(/M(\d+(?:\.\d+)?)/i) || a.match(/(\d+\.\d+)/)
  const rb = b.match(/M(\d+(?:\.\d+)?)/i) || b.match(/(\d+\.\d+)/)
  const na = ra ? parseFloat(ra[1]) : 0
  const nb = rb ? parseFloat(rb[1]) : 0
  if (na !== nb) return nb - na
  return b.localeCompare(a)
}

function classifyHuntTier(name) {
  const n = String(name || "").toLowerCase()
  const pm = n.match(/[:-](\d+(?:\.\d+)?)(b|t)\b/)
  let size = 0
  if (pm) {
    size = pm[2] === "t" ? parseFloat(pm[1]) * 1000 : parseFloat(pm[1])
  }

  // Gemma 4 and Flash variants are the floor we accept for the scan tier.
  if (/\bgemma.?4\b/.test(n) || /\bflash\b/.test(n)) return "scan"

  // Size wins over loose keywords (nemotron-3-nano:30b → scan, not small).
  if (size > 70) return "solve"
  if (size > 25 && size <= 70) return "scan"
  if (size > 0 && size <= 25) return "small"

  if (/\b(tiny|nano|mini|small|lite|light)\b/.test(n)) return "small"
  if (/\b(medium|light-pro)\b/.test(n)) return "scan"
  if (/\b(large|pro|max|ultra|thinking|coder|reasoner|deepseek-v4-pro)\b/.test(n)) return "solve"

  return "solve"
}

function pickMinimaxM3(models) {
  return models.find((m) => /^MiniMax-M3$/i.test(m)) || models.find((m) => isMinimaxM3Model(m)) || null
}

function hasRunnableModelDefaults(providerID, model) {
  if (providerID === "managed:kimi-code" && model === "kimi-for-coding") {
    return !!record(config.models?.["kimi-code/kimi-for-coding"])
  }
  const modelRef = providerID + "/" + model
  if (record(config.models?.[modelRef])) return true
  return modelCatalogParams(modelRef)._modelsDev === true
}

function lineageForProviderModel(providerID, model) {
  const modelRef = providerID + "/" + model
  return inferLineage(model) || inferLineage(modelRef)
}

function availableModelsForLineage(providerID, lineage) {
  const candidates = new Set()
  if (providerID === "managed:kimi-code" && lineage === "kimi" && record(config.models?.["kimi-code/kimi-for-coding"])) {
    candidates.add("kimi-for-coding")
  }
  for (const model of LIVE_CATALOG.get(providerID) || []) {
    if (lineageForProviderModel(providerID, model) === lineage) candidates.add(model)
  }
  return [...candidates]
}

function isDisabledModelRef(modelRef) {
  return DISABLED_MODELS.has(modelRef)
}

function providerOrderForLineage(lineage) {
  if (Array.isArray(SEEDS[lineage]) && SEEDS[lineage].length) return SEEDS[lineage]
  const out = []
  const direct = DIRECT_PROVIDER_BY_LINEAGE[lineage]
  if (direct) out.push(direct)
  for (const providerID of PROVIDER_PRIORITY) {
    if (providerID && !out.includes(providerID)) out.push(providerID)
  }
  return out
}

function buildDynamicChain(lineage, wantTierSplit = false) {
  const providers = providerOrderForLineage(lineage)
  const scan = []
  const solve = []
  for (const pid of providers) {
    let models = availableModelsForLineage(pid, lineage)
    models = models.sort(versionSort)
    models = models.filter((m) => !isDisabledModelRef(pid + "/" + m))
    const dynamicModels = models.filter((m) => hasRunnableModelDefaults(pid, m))
    models = dynamicModels.length ? dynamicModels : []

    // Three-tier split: small (drop), scan, solve. M3 is in BOTH scan and solve pools.
    const scanModels = models.filter((m) => classifyHuntTier(m) === "scan" || isMinimaxM3Model(m))
    const solveModels = models.filter((m) => classifyHuntTier(m) === "solve" || isMinimaxM3Model(m))

    const makeEntry = (m, huntPhase) => {
      const modelRef = pid + "/" + m
      const entry = { providerID: pid, modelRef, protocolType: protocolForEntry(pid, modelRef) }
      const base = baseUrlForEntry(pid, modelRef)
      if (base) entry.baseUrl = base
      if (pid === "managed:kimi-code") {
        entry.modelRef = "kimi-code/kimi-for-coding"
        entry.model = "kimi-for-coding"
        entry.protocolType = protocolForEntry(pid, entry.modelRef)
        const managedBase = baseUrlForEntry(pid, entry.modelRef)
        if (managedBase) entry.baseUrl = managedBase
      }
      if (isMinimaxM3Model(m) && huntPhase) entry.huntPhase = huntPhase
      return entry
    }

    const m3 = pickMinimaxM3(models)

    if (wantTierSplit) {
      const scanPick = m3 || scanModels[0]
      const solvePick = m3 || solveModels[0]
      if (scanPick) scan.push(makeEntry(scanPick, "scan"))
      if (solvePick) solve.push(makeEntry(solvePick, "solve"))
    } else {
      // flat mode: prefer solve, then scan
      const best = solveModels.length ? solveModels[0] : (scanModels.length ? scanModels[0] : models[0])
      if (best) scan.push(makeEntry(best, isMinimaxM3Model(best) ? "solve" : null))
    }
  }
  return wantTierSplit ? { scan, solve } : scan
}

function directChainEntry(providerID, modelID, huntPhase = null) {
  const modelRef = providerID + "/" + modelID
  const entry = { providerID, modelRef, model: modelID, protocolType: protocolForEntry(providerID, modelRef) }
  const base = baseUrlForEntry(providerID, modelRef)
  if (base) entry.baseUrl = base
  if (huntPhase && isMinimaxM3Model(modelID)) entry.huntPhase = huntPhase
  return entry
}

function dedupeChain(entries) {
  const seen = new Set()
  const out = []
  for (const entry of entries) {
    const key = entry.modelRef
    if (isDisabledModelRef(key)) continue
    if (seen.has(key)) continue
    seen.add(key)
    out.push(entry)
  }
  return out
}

function buildDirectSeededChain(lineage, directRef, wantTierSplit = false) {
  const slash = String(directRef || "").indexOf("/")
  if (slash < 0) return buildDynamicChain(lineage, wantTierSplit)
  const providerID = directRef.slice(0, slash)
  const modelID = directRef.slice(slash + 1)
  const dynamic = buildDynamicChain(lineage, wantTierSplit)
  if (wantTierSplit) {
    return {
      scan: dedupeChain([directChainEntry(providerID, modelID, "scan"), ...(dynamic.scan || [])]),
      solve: dedupeChain([directChainEntry(providerID, modelID, "solve"), ...(dynamic.solve || [])]),
    }
  }
  return dedupeChain([directChainEntry(providerID, modelID), ...dynamic])
}

const input = JSON.parse(process.env.REDTEAM_INPUT_FILE ? readFileSync(process.env.REDTEAM_INPUT_FILE, "utf8") : process.env.REDTEAM_INPUT)
// Orphan guard: the runner launches this bridge with async spawn, so if the runner
// dies by an external signal (timeout(1), Ctrl-C, OOM, a parent pool tearing down)
// it may exit without killing us. Node then reparents us (ppid -> the init/subreaper
// pid, != our launcher) and a heavy review would run on for minutes as an orphan,
// burning CPU and a provider-gate slot. Poll ppid and exit promptly when orphaned.
// unref() so this timer never keeps us alive.
const __launcherPid = process.ppid
setInterval(() => {
  if (process.ppid !== __launcherPid) {
    process.stderr.write("redteam-bridge: launcher gone (orphaned), exiting\n")
    process.exit(2)
  }
}, 1500).unref()
const configPath = process.env.KIMI_CODE_CONFIG || "/home/mhugo/.kimi-code/config.toml"
const config = parseToml(readFileSync(configPath, "utf8"))
const opencodeConfigPath = process.env.OPENCODE_CONFIG || "/home/mhugo/.config/opencode/opencode.json"
let opencodeConfig = {}
try {
  opencodeConfig = JSON.parse(readFileSync(opencodeConfigPath, "utf8"))
} catch {}


const LINEAGE_ALIASES = {
  xiaomi: "mimo",
  zhipu: "glm",
  zai: "glm",
  moonshot: "kimi",
  nvidia: "nemotron",
  openai: "gpt-oss",
}

function canonicalLineage(value) {
  const key = String(value || "").toLowerCase()
  return LINEAGE_ALIASES[key] || key
}

const lineage = canonicalLineage(input.lineage)
// --pin bypasses the lineage chain (runs the exact named model), so a known lineage
// is only required for the normal chain path.
if (!input.pin && !LINEAGES.includes(lineage)) throw new Error("unknown lineage " + input.lineage + " (expected: " + LINEAGES.join(", ") + ")")

function record(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : null
}

// Minimal stderr logger that satisfies agent-core's Logger interface for the
// MCP connection manager. The bridge has no session logger, so we emit MCP
// lifecycle events to stderr (mirroring the rest of the bridge diagnostics).
const mcpLogger = {
  error: (message, payload) => process.stderr.write("redteam-mcp error: " + message + " " + (payload ? JSON.stringify(payload) : "") + "\n"),
  warn: (message, payload) => process.stderr.write("redteam-mcp warn: " + message + " " + (payload ? JSON.stringify(payload) : "") + "\n"),
  info: (message, payload) => process.stderr.write("redteam-mcp info: " + message + " " + (payload ? JSON.stringify(payload) : "") + "\n"),
  debug: () => {},
  createChild: () => mcpLogger,
}

function loadMcpConfig() {
  const envPath = process.env.REDTEAM_MCP_CONFIG
  if (envPath) {
    try {
      return JSON.parse(readFileSync(envPath, "utf8"))
    } catch (err) {
      process.stderr.write("redteam-mcp: failed to read REDTEAM_MCP_CONFIG: " + String(err) + "\n")
      return {}
    }
  }
  const defaultPath = (process.env.HOME || "/home/mhugo") + "/.config/redteam/mcp.json"
  try {
    return JSON.parse(readFileSync(defaultPath, "utf8"))
  } catch {
    // No user config; fall back to the public DeepWiki remote MCP as the
    // default fact base for dependency/third-party behavior.
    if (process.env.REDTEAM_NO_MCP) return {}
    return {
      deepwiki: { transport: "http", url: "https://mcp.deepwiki.com/mcp" },
    }
  }
}

class McpExecutableTool {
  constructor(name, description, parameters, client) {
    this.name = name
    this.description = description
    this.parameters = parameters
    this.client = client
  }

  resolveExecution(input) {
    const toolName = this.name
    const client = this.client
    return {
      approvalRule: "mcp",
      description: this.description,
      execute: async (ctx) => {
        try {
          const args = input && typeof input === "object" && !Array.isArray(input) ? input : {}
          const result = await client.callTool(toolName, args, ctx.signal)
          const { output, isError } = mcpResultToExecutableOutput(result, toolName)
          return { output, isError }
        } catch (err) {
          return {
            output: "<system>ERROR: MCP tool " + toolName + " failed: " + String(err) + "</system>",
            isError: true,
          }
        }
      },
    }
  }
}

async function buildMcpTools() {
  const config = loadMcpConfig()
  const servers = record(config)
  if (!servers || Object.keys(servers).length === 0) return []

  const manager = new McpConnectionManager({ log: mcpLogger })
  const controller = new AbortController()
  const startupTimer = setTimeout(() => controller.abort(new Error("MCP startup timeout")), 15000)
  try {
    await manager.connectAll(servers)
    await manager.waitForInitialLoad(controller.signal)
  } catch (err) {
    process.stderr.write("redteam-mcp: initial load failed: " + String(err) + "\n")
  } finally {
    clearTimeout(startupTimer)
  }

  const tools = []
  for (const entry of manager.list()) {
    if (entry.status !== "connected") {
      process.stderr.write("redteam-mcp: " + entry.name + " " + entry.status + (entry.error ? " — " + entry.error : "") + "\n")
      continue
    }
    const resolved = manager.resolved(entry.name)
    if (!resolved) continue
    for (const tool of resolved.tools) {
      if (resolved.enabledNames && !resolved.enabledNames.has(tool.name)) continue
      tools.push(new McpExecutableTool(tool.name, tool.description, tool.parameters, resolved.client))
    }
  }
  if (tools.length > 0) {
    process.stderr.write("redteam-mcp: registered " + tools.length + " tool(s) from " + manager.list().filter((e) => e.status === "connected").length + " server(s)\n")
  }
  return tools
}

function resolveEnvRef(value) {
  if (typeof value !== "string") return value
  const match = value.match(/^\{env:([^}]+)\}$/)
  return match ? process.env[match[1]] || "" : value
}

// Live /v1/models discovery is availability-only. Kimi stores durable model
// metadata in config aliases generated from models.dev/catalog; do not persist a
// separate redteam model cache that can outlive provider reality.
function discoverLive(config) {
  const out = new Map()
  for (const [pid, p] of Object.entries(config.providers || {})) {
    const base = resolveModelsCatalogBaseUrl(pid, resolveEnvRef(p.base_url) || "")
    const key = p.api_key ? resolveEnvRef(p.api_key) : ""
    if (!base || !key) continue
    const url = modelsListUrl(base)
    try {
      const outStr = execSync("curl -sS -H 'Authorization: Bearer " + key + "' '" + url + "'", { encoding: "utf8", timeout: 8000 })
      const json = JSON.parse(outStr)
      let list = (Array.isArray(json && json.data) ? json.data : Array.isArray(json) ? json : [])
        .map((m) => m && (m.id || m.name))
        .filter((x) => typeof x === "string")
      list = list.sort(versionSort)
      if (list.length) out.set(pid, list)
    } catch {}
  }
  return out
}

const LIVE_CATALOG = discoverLive(config)

function opencodeProvider(entry) {
  const providers = record(opencodeConfig.provider)
  const provider = record(providers?.[entry.providerID])
  if (!provider) return { skip: "missing opencode provider config" }
  const options = record(provider.options) || {}
  const models = record(provider.models)
  const model = entry.model || entry.modelRef.slice(entry.modelRef.indexOf("/") + 1)
  if (!record(models?.[model])) return { skip: "missing opencode model config" }
  const apiKey = resolveEnvRef(options.apiKey)
  if (!apiKey) return { skip: "missing api key" }
  return {
    label: entry.label || entry.modelRef,
    type: entry.protocolType || "anthropic",
    model,
    apiKey,
    baseUrl: typeof options.baseURL === "string" ? options.baseURL : undefined,
    source: "opencode",
  }
}

function zaiProvider(entry) {
  const providers = record(config.providers)
  const kimiProvider = record(providers?.zai) || record(providers?.["z-ai"]) || record(providers?.zhipu)
  if (kimiProvider) {
    const apiKey = resolveEnvRef(kimiProvider.api_key)
    if (!apiKey) return { skip: "missing api key" }
    return {
      label: entry.label || entry.modelRef,
      type: typeof kimiProvider.type === "string" ? kimiProvider.type : entry.protocolType,
      model: entry.model,
      apiKey,
      baseUrl: typeof kimiProvider.base_url === "string" ? kimiProvider.base_url : "https://api.z.ai/api/anthropic",
      source: "kimi",
    }
  }
  const openProviders = record(opencodeConfig.provider)
  const openProvider = record(openProviders?.zai) || record(openProviders?.["z-ai"]) || record(openProviders?.zhipu)
  if (openProvider) {
    const options = record(openProvider.options) || {}
    const apiKey = resolveEnvRef(options.apiKey)
    if (!apiKey) return { skip: "missing api key" }
    return {
      label: entry.label || entry.modelRef,
      type: entry.protocolType,
      model: entry.model,
      apiKey,
      baseUrl: typeof options.baseURL === "string" ? options.baseURL : "https://api.z.ai/api/anthropic",
      source: "opencode",
    }
  }
  const apiKey = process.env.ZAI_API_KEY || process.env.Z_AI_API_KEY || process.env.ZHIPU_API_KEY || ""
  if (!apiKey) return { skip: "missing zai config" }
  return {
    label: entry.label || entry.modelRef,
    type: entry.protocolType,
    model: entry.model,
    apiKey,
    baseUrl: process.env.ZAI_BASE_URL || process.env.Z_AI_BASE_URL || "https://api.z.ai/api/anthropic",
    source: "env",
  }
}

function configuredProvider(entry, lineageName) {
  if (entry.source === "opencode") return opencodeProvider(entry)

  let providerID = entry.providerID
  let modelRef = entry.modelRef

  // Dynamic catalog providers are exactly the provider IDs that appear in the
  // global provider order or direct-provider map. Any provider listed there is
  // driven by Kimi/Kosong catalog metadata + live /v1/models discovery. The
  // exact provider/model label does not need to be a key in config.models.
  const DYNAMIC_PROVIDERS = new Set(
    [
      ...Object.values(SEEDS).flat(),
      ...PROVIDER_PRIORITY,
      ...Object.values(DIRECT_PROVIDER_BY_LINEAGE),
    ].filter(Boolean)
  )

  if (DYNAMIC_PROVIDERS.has(providerID) || DYNAMIC_PROVIDERS.has(entry.providerID)) {
    // keep the original providerID; kosong will handle it
  } else if (providerID === "kimi-for-coding" || providerID === "kimi-code") {
    // legacy kimi lineage head label
    providerID = "managed:kimi-code"
  }

  const providers = record(config.providers)
  const provider = record(providers?.[providerID])
  if (!provider) return { skip: "missing provider config" }

  // For any dynamic provider, the live /v1/models
  // response already decided the model name. We do not require an exact
  // config.models key for that modelRef.
  const hasCatalogDefaults = modelCatalogParams(modelRef)._modelsDev === true
  const isDynamic = DYNAMIC_PROVIDERS.has(providerID) || hasCatalogDefaults
  if (!isDynamic) {
    const models = record(config.models)
    if (!record(models?.[modelRef])) {
      return { skip: 'model "' + modelRef + '" is not configured in config.toml' }
    }
  } else if (!record(config.models?.[modelRef]) && !hasCatalogDefaults) {
    return { skip: 'missing Kosong/models.dev defaults for dynamic model "' + modelRef + '"' }
  }
  const model = entry.model || modelRef.slice(modelRef.indexOf("/") + 1)
  const type = entry.protocolType || (typeof provider.type === "string" ? provider.type : null)
  if (!type) return { skip: "missing provider type" }
  let apiKey = resolveEnvRef(provider.api_key)
  // managed:kimi-code authenticates via OAuth in config (api_key=""), which this
  // harness can't do — so it failed "apiKey is required". The static coding key is
  // in the env; use it whether we drive kimi-code over its native protocol OR the
  // anthropic wire format (api.kimi.com/coding/v1/messages, same key).
  if (!apiKey && (type === "kimi" || providerID === "managed:kimi-code")) {
    apiKey = process.env.KIMI_API_KEY || process.env.MOONSHOT_API_KEY || ""
  }
  if (!apiKey && type !== "kimi") return { skip: "missing api key" }

  return {
    label: entry.label || modelRef,
    type,
    model,
    apiKey: typeof apiKey === "string" ? apiKey : "",
    // entry.baseUrl overrides the config base_url — kimi-code's anthropic endpoint
    // is api.kimi.com/coding (NOT the native .../coding/v1 in config.providers).
    baseUrl: typeof entry.baseUrl === "string" ? entry.baseUrl : (typeof provider.base_url === "string" ? provider.base_url : undefined),
    source: "kimi",
  }
}

function resolveChain(entries, lineageName) {
  return entries.map((entry) => {
    const configured = configuredProvider(entry, lineageName)
    if (configured.skip) return { lineage: lineageName, entry, skipped: true, reason: configured.skip }
    // carry providerID so the chain loop can gate the ACTUAL serving provider
    return { lineage: lineageName, entry, configured: { ...configured, providerID: entry.providerID, huntPhase: entry.huntPhase || null }, skipped: false }
  })
}

function staticRegistryCheck() {
  const readOnlyTools = ["ReadTool", "GrepTool", "GlobTool", "FetchURLTool", "WebSearchTool"]
  const rows = []
  for (const lineageName of LINEAGES) {
    for (const resolved of resolveChain(buildDynamicChain(lineageName), lineageName)) {
      if (!resolved.skipped) {
        buildProvider(resolved.configured)
      }
      rows.push({
        lineage: lineageName,
        entry: resolved.entry.modelRef,
        protocolType: resolved.entry.protocolType,
        status: resolved.skipped ? "skipped" : "configured",
        reason: resolved.reason || "",
        source: resolved.configured?.source || "",
      })
    }
  }
  const toolSetReadOnly = readOnlyTools.every((name) => ["ReadTool", "GrepTool", "GlobTool", "FetchURLTool", "WebSearchTool"].includes(name))
  process.stdout.write(JSON.stringify({ kind: "registry-static", toolSetReadOnly, readOnlyTools, rows }) + "\n")
}

function outputForModel(result) {
  if (typeof result.output === "string") {
    if (result.isError === true) return result.output.trimStart().startsWith("<system>ERROR:") ? result.output : "<system>ERROR: Tool failed</system>\n" + result.output
    return result.output.length === 0 ? "(tool returned empty output)" : result.output
  }
  if (result.output.length === 0) return result.isError === true ? [{ type: "text", text: "(tool returned empty error output)" }] : [{ type: "text", text: "(tool returned empty output)" }]
  return result.isError === true ? [{ type: "text", text: "<system>ERROR: Tool failed</system>" }, ...result.output] : result.output
}

function buildProvider(configured, opts = {}) {
  // maxRetries:0 — a capped/no-balance provider (opencode-go monthly cap, zai no
  // balance) returns 429, but the OpenAI SDK default maxRetries:2 retries it with
  // backoff that HONORS Retry-After (can be many seconds), so the 429 never surfaces
  // fast and the whole per-provider budget is burned before the chain falls through.
  // A clientFactory with maxRetries:0 makes the first 429 throw immediately ->
  // providerFailure() matches '429' -> instant fall-through to the next provider.
  // Only the openai-legacy path takes a clientFactory; kimi/anthropic are the
  // subscription (non-429) providers.
  const clientFactory = configured.type === "openai"
    ? (auth) => new OpenAI({
        apiKey: configured.apiKey,
        baseURL: configured.baseUrl,
        ...(auth?.headers ? { defaultHeaders: auth.headers } : {}),
        maxRetries: 0,
      })
    : undefined
  const modelLabel = String(configured.model || configured.label || "")
  const harnessCfg = modelParamsCfg(configured.label)
  const adaptiveThinking =
    harnessCfg.adaptive_thinking === true || harnessCfg.adaptiveThinking === true
  const p = createProvider({
    type: configured.type,
    model: configured.model,
    apiKey: configured.apiKey,
    baseUrl: configured.baseUrl,
    ...(configured.type === "kimi" ? { defaultHeaders: { "User-Agent": "KimiCLI/1.43.0" } } : {}),
    ...(configured.type === "anthropic" && adaptiveThinking ? { adaptiveThinking: true } : {}),
    ...(clientFactory ? { clientFactory } : {}),
  })
  // temperature=0: agentic tool-use should be deterministic. max_tokens: bound the
  // output budget. createProvider IGNORES a generationKwargs option (OpenAILegacyOptions
  // has no such field — which is why neither temperature nor max_completion_tokens
  // applied), so set them on the provider directly via withGenerationKwargs, which DOES
  // flow into the request (openai-legacy normalizes max_tokens -> max_completion_tokens
  // for o-series/gpt-5 models). Without temperature=0 the provider's default sampling
  // makes reasoning models (cogito) stochastically NARRATE tool calls as text
  // ('<function>Read</function>') instead of issuing native tool_calls -> 0-finding runs.
  // Output budget: an explicit --max-tokens wins (uncapped); otherwise use THIS
  // model's declared max_output_size so verbose reasoners (deepseek, mistral) are
  // never truncated, bounded by a ceiling so a model that declares an absurd max
  // (deepseek: 1048576) can't send a value the endpoint rejects. Falls back to
  // the ceiling when the model isn't in config (e.g. opencode-served).
  //
  // The catalog max_output_size now holds the PROBED enforced cap per
  // (provider, model) — the endpoint's real max_tokens, discovered empirically
  // by scripts/probe-model-output.mjs (the limit is published nowhere;
  // ollama-cloud 400s on values it never advertises, which is why the deepseek
  // lineage died on the old 131072 context-window value). The runner uses that
  // catalog value DIRECTLY: it is guaranteed accepted because it IS the largest
  // max_tokens the endpoint took when probed. FALLBACK applies only to models
  // absent from the catalog. Refresh caps with probe-model-output.mjs --write.
  const FALLBACK = 32768
  // Kimi's reasoning bills as output tokens (thinking is mandatory, can't be disabled).
  // The ollama-cloud kimi-k2.7-code endpoint enforces a 262144 output cap (probed live:
  // 262144 → 200, 524288 → 400 "exceeds maximum output tokens (262144)"). Use that FULL
  // ceiling rather than the old conservative 32768 — the earlier empty-response on big
  // inputs was a 131k attempt under a tighter budget, and 262144 is the endpoint's real
  // max, verified to still conclude. Per-model config max_output_size still wins via min().
  const KIMI_MAX_OUTPUT = 262144
  const explicitCap = Number.isFinite(input.maxCompletionTokens) && input.maxCompletionTokens > 0 ? input.maxCompletionTokens : null
  const modelCfg = record(config.models?.[configured.label]) || {}
  const modelMax = modelCfg.max_output_size
  const isKimiModel = configured.type === "kimi" || /kimi/i.test(modelLabel)
  const cap = explicitCap ?? (isKimiModel
    ? (Number.isFinite(modelMax) && modelMax > 0 ? Math.min(modelMax, KIMI_MAX_OUTPUT) : KIMI_MAX_OUTPUT)
    : (Number.isFinite(modelMax) && modelMax > 0 ? modelMax : FALLBACK))
  const { kwargs: reviewKwargs, thinkingEffort } = resolveModelReviewParams({
    modelCfg: harnessCfg,
    salvage: !!opts.salvage,
    env: process.env,
    modelLabel,
    huntPhase: configured.huntPhase || input.huntPhase || null,
  })
  const kwargs = { ...reviewKwargs, max_tokens: cap }
  let prov = typeof p.withGenerationKwargs === "function" ? p.withGenerationKwargs(kwargs) : p
  // models.json thinking_effort + env (REDTEAM_THINKING_EFFORT / scout off / M3 huntPhase).
  const effort = thinkingEffort ?? (configured.type === "kimi" ? "high" : null)
  if (effort != null && typeof prov.withThinking === "function") {
    prov = prov.withThinking(effort)
  }
  // Defensive fallback: some OpenAI-compatible backends (ollama-cloud serving
  // DeepSeek-base models like cogito) intermittently leak DeepSeek's raw inline
  // tool-call tokens into content instead of structuring them — at temp 0 (our
  // setting) ~every time. Parse them into real tool calls. No-op otherwise.
  return wrapWithDeepSeekToolFallback(prov)
}

if (input.registryStatic) {
  staticRegistryCheck()
  process.exit(0)
}

// --pin builds a single synthetic entry for the EXACT model. Reuse the per-model wire
// format the REGISTRY already declares (e.g. opencode-go/qwen3.7-max -> anthropic, the only
// go model that needs it) if the model appears in any chain; otherwise configuredProvider
// falls back to the provider's declared type. DRY + future-proof: a new per-model exception
// added to the REGISTRY applies to --model automatically (redteam design-panel recommendation).
function pinnedEntry() {
  const ref = input.providerID + "/" + input.modelID
  // Derive protocolType from the known anthropic wire set; everything else defaults to openai.
  // configuredProvider will still validate against config.providers and apply baseUrl overrides.
  return directChainEntry(input.providerID, input.modelID)
}
const wantSplit = input.mode === "hunt"
const chainOrSplit = input.pin
  ? (wantSplit ? { scan: [{ ...pinnedEntry(), huntPhase: isMinimaxM3Model(input.modelID) ? "scan" : undefined }], solve: [{ ...pinnedEntry(), huntPhase: isMinimaxM3Model(input.modelID) ? "solve" : undefined }] } : [pinnedEntry()])
  : (input.directModel ? buildDirectSeededChain(lineage, input.directModel, wantSplit) : buildDynamicChain(lineage, wantSplit))

let scanChain = []
let solveChain = []
if (wantSplit) {
  scanChain = (chainOrSplit.scan || []).filter((e) => !resolveChain([e], lineage)[0].skipped).map((e) => resolveChain([e], lineage)[0].configured)
  solveChain = (chainOrSplit.solve || []).filter((e) => !resolveChain([e], lineage)[0].skipped).map((e) => resolveChain([e], lineage)[0].configured)
} else {
  const flat = resolveChain(chainOrSplit, lineage)
  scanChain = flat.filter((e) => !e.skipped).map((e) => e.configured)
}
const configuredChain = wantSplit ? solveChain : scanChain
const fmtChain = (chain) => chain.length > 0
  ? chain.map((c) => {
      const base = c.baseUrl ? "@" + c.baseUrl.replace(/^https?:\/\//, "").replace(/\/.*$/, "") : ""
      const phase = c.huntPhase ? ("[" + c.huntPhase + "]") : ""
      return phase + c.providerID + "/" + (c.model || c.modelRef || "") + base
    }).join(" → ")
  : "(none configured)"
const chainStr = wantSplit
  ? ("scan: " + fmtChain(scanChain) + " | solve: " + fmtChain(solveChain))
  : fmtChain(configuredChain)

process.stderr.write("redteam-chain: " + lineage + " " + chainStr + "\n")

// Always write the chain file so the user has a record even when the chain is empty
// or when all providers are skipped.
try {
  const home = process.env.HOME || process.env.USERPROFILE || "."
  const chainDir = home + "/.cache/redteam/chains"
  mkdirSync(chainDir, { recursive: true })
  const payload = {
    lineage,
    at: Date.now(),
    chain: configuredChain.map((c) => ({
      providerID: c.providerID,
      model: c.model || c.modelRef || null,
      baseUrl: c.baseUrl || null,
      protocolType: c.protocolType || null,
    })),
  }
  writeFileSync(chainDir + "/" + lineage + ".json", JSON.stringify(payload, null, 2))
} catch (e) {
  process.stderr.write("redteam-chain-file: " + String(e && e.message || e) + "\n")
}

if (configuredChain.length === 0) throw new Error(input.pin ? "--model: provider '" + input.providerID + "' is not usable (not in config.providers, or missing api key)" : "no configured providers for lineage " + lineage)
// Per-provider budget is DEADLINE-based, not an even split of the total. An even
// split (timeoutMs/chainLen) starves the working provider: dead providers (zai,
// opencode-go) 429 in <1.5s and fall through, but the surviving ollama-served
// reasoning model needs 130-260s for a tool-using review and would be cut at
// timeoutMs/N. With a shared deadline, fast-failing providers consume ~1s each and
// the working provider inherits nearly the whole budget. PER_PROVIDER_CAP bounds a
// single attempt so one stuck provider can't eat the entire deadline.
const deadline = Date.now() + input.timeoutMs
const PER_PROVIDER_CAP = Math.min(input.timeoutMs, 280000)
const attemptBudget = () => computeAttemptBudget(deadline, Date.now(), PER_PROVIDER_CAP)

const kaos = (await LocalKaos.create()).withCwd(input.repoRoot)
// WorkspaceConfig per agent-core/tools/support/workspace.ts: {workspaceDir, additionalDirs}.
const workspace = { workspaceDir: input.repoRoot, additionalDirs: [] }
// Web search via the kimi coding plan (api.kimi.com/coding/v1/search, same KIMI_API_KEY
// as chat — verified the bearer authenticates the search endpoint). Lets a reviewer
// resolve a real GitHub repo / docs instead of guessing from an npm import scope.
const __searchSvc = record(config.services && config.services.moonshot_search)
const __searchKey = process.env.KIMI_API_KEY || process.env.MOONSHOT_API_KEY || ""

// submit_verdict: the canonical way for a reviewer to deliver its verdict.
// Two schemas: verify-mode (real|false-positive + reason) and review-mode (approve|needs-attention + findings).
// IMPORTANT: inside String.raw BRIDGE — no backticks, no template interpolation. Use plain object literals.
const VERDICT_TOOL_SCHEMA = input.mode === "verify"
  ? { type: "object", properties: { verdict: { type: "string", enum: ["real", "false-positive"] }, confidence: { type: "number" }, reason: { type: "string" } }, required: ["verdict", "reason"] }
  : { type: "object", properties: { verdict: { type: "string", enum: ["approve", "needs-attention"] }, summary: { type: "string" }, findings: { type: "array", items: { type: "object", properties: { severity: { type: "string", enum: ["critical", "high", "medium", "low"] }, title: { type: "string" }, body: { type: "string" }, file: { type: "string" }, line_start: { type: "number" }, line_end: { type: "number" }, confidence: { type: "number" }, recommendation: { type: "string" } }, required: ["severity", "title", "body", "file", "line_start", "line_end", "confidence", "recommendation"] } }, next_steps: { type: "array", items: { type: "string" } } }, required: ["verdict", "summary", "findings"] }

class SubmitVerdictTool {
  constructor() {
    this.name = "submit_verdict"
    this.description = "Submit your FINAL review verdict. This is the ONLY way to deliver your verdict — call it exactly once at the end. Its parameters are the required fields."
    this.parameters = VERDICT_TOOL_SCHEMA
  }
  resolveExecution() {
    const name = this.name
    const description = this.description
    return {
      approvalRule: name,
      description,
      execute: async () => ({ output: "Verdict recorded; the review is complete.", isError: false, stopTurn: true }),
    }
  }
}

const builtinTools = input.mode === "smoke" || input.mode === "route"
  ? []
  : [
      new ReadTool(kaos, workspace),
      new GrepTool(kaos, workspace),
      new GlobTool(kaos, workspace),
      new FetchURLTool(new LocalFetchURLProvider({ userAgent: "KimiCLI/1.43.0" })),
      new SubmitVerdictTool(),
      ...(__searchSvc && typeof __searchSvc.base_url === "string" && __searchKey
        ? [new WebSearchTool(new MoonshotWebSearchProvider({ baseUrl: __searchSvc.base_url, apiKey: __searchKey, defaultHeaders: { "User-Agent": "KimiCLI/1.43.0" } }))]
        : []),
    ]
const mcpTools = input.mode === "smoke" || input.mode === "route" || process.env.REDTEAM_NO_MCP || input.deepwiki === false ? [] : await buildMcpTools()
const tools = [...builtinTools, ...mcpTools]

// runTurn throws createMaxStepsExceededError when a thorough review exhausts its
// step budget, and an AbortError when the timeout fires. Both are recoverable: the
// assistant text accumulated up to that point is still usable, and the re-ask
// salvage can coax a final JSON object out. Anything else is a real fault — rethrow.
function recoverable(err) {
  return isMaxStepsExceededError(err) || isAbortError(err)
}

async function runWithProvider(configured, attemptTimeoutMs, tools) {
  const messages = [createUserMessage(input.prompt)]
  const assistantTexts = []
  const reasoningTexts = []
  let submittedVerdict = null
  // Manifest of evidence the model actually inspected (Read/Grep/Glob targets). The salvage
  // reask drops the bulky tool-result turns to keep context small, which made a model that
  // spent its whole budget CALLING tools (little prose) reask with no memory of its own
  // investigation and emit a hollow "no files were read" verdict — despite having read them.
  // Feeding back this compact manifest restores that memory without re-bloating the context.
  const readManifest = []
  const openSteps = new Map()
  const pendingToolResultIds = new Set()
  // Tool-call dedup — the SAME component the kimi-cli Agent wires into its loop.
  // Without it, reasoning-heavy models (esp. openai-protocol: deepseek/cogito/
  // gpt-oss) re-issue identical Read/Grep calls every step, ballooning context
  // and blowing the time budget (presents as a "hang"/timeout). The anthropic
  // path was terse enough to slip under the budget, masking the gap.
  const deduper = new ToolCallDeduplicator()
  const toolResultCache = new Map()
  const provider = buildProvider(configured)
  const llm = new KosongLLM({
    provider,
    modelName: configured.model,
    systemPrompt: input.systemPrompt || "You are a read-only adversarial reviewer. Never modify files. Use tools only to inspect evidence, then return the requested JSON object.",
  })

  function pushHistory(message) {
    messages.push(message)
  }

  let stepNum = 0
  let beforeStepCount = 0
  let verdictForced = 0
  const REVIEW_MAX_STEPS = Number(process.env.REDTEAM_REVIEW_MAX_STEPS) || 50
  function appendLoopEvent(event) {
    resetIdle() // any loop event = progress; keep a working model alive, reset the stall clock
    switch (event.type) {
      case "step.begin": {
        stepNum++
        process.stderr.write("  [" + configured.label + "] step " + stepNum + "\n")
        if (input.mode !== "smoke" && input.mode !== "route" && stepNum > REVIEW_MAX_STEPS) {
          throw new Error(configured.label + " review step budget reached")
        }
        const message = { role: "assistant", content: [], toolCalls: [] }
        pushHistory(message)
        openSteps.set(event.uuid, message)
        return
      }
      case "content.part": {
        const openStep = openSteps.get(event.stepUuid)
        if (!openStep) throw new Error("content.part for unknown step " + event.stepUuid)
        openStep.content.push(event.part)
        if (event.part.type === "text") assistantTexts.push(event.part.text)
        else if (event.part.type === "think" && typeof event.part.think === "string") reasoningTexts.push(event.part.think)
        return
      }
      case "tool.call": {
        const openStep = openSteps.get(event.stepUuid)
        if (!openStep) throw new Error("tool.call for unknown step " + event.stepUuid)
        openStep.toolCalls.push({
          type: "function",
          id: event.toolCallId,
          name: event.name,
          arguments: event.args === undefined ? null : JSON.stringify(event.args),
        })
        pendingToolResultIds.add(event.toolCallId)
        if (event.name === "submit_verdict" && event.args && typeof event.args === "object") {
          submittedVerdict = event.args
          // Adoption marker — fires for EVERY path incl. the salvage reask (which has no
          // prepareToolExecution hook), so "did the model CALL submit_verdict?" is observable.
          process.stderr.write("  [" + configured.label + "]   submit_verdict (captured)\n")
        } else if (event.name === "Read" || event.name === "Grep" || event.name === "Glob") {
          // Record what was inspected (path/pattern) for the reask manifest. Capped so a
          // tool-heavy run can't unbounded-grow it.
          const a = event.args && typeof event.args === "object" ? event.args : {}
          const target = a.path || a.pattern || a.file_path || ""
          if (target && readManifest.length < 40) readManifest.push(event.name + " " + String(target))
        }
        return
      }
      case "tool.result": {
        pushHistory(createToolMessage(event.toolCallId, outputForModel(event.result)))
        pendingToolResultIds.delete(event.toolCallId)
        return
      }
      case "step.end": {
        openSteps.delete(event.uuid)
        return
      }
    }
  }

  function providerMessages() {
    return messages.filter((message) => {
      if (message.role !== "assistant") return true
      return message.content.length > 0 || message.toolCalls.length > 0
    })
  }

  const controller = new AbortController()
  // Two bounds: a generous HARD cap (absolute backstop) and an IDLE cap that only
  // fires when the model makes no progress. A model that keeps streaming/tool-calling
  // resets the idle timer on every loop event and runs until the hard cap; a STALLED
  // model is aborted at IDLE_MS instead of hanging the whole panel for the full budget.
  // This is why a slow-but-working 671B review isn't killed, but a wedged one is.
  const IDLE_MS = Math.min(attemptTimeoutMs, 120000)
  let idleTimer
  const resetIdle = () => {
    clearTimeout(idleTimer)
    idleTimer = setTimeout(() => controller.abort(new Error(configured.label + " stalled — no progress for " + Math.round(IDLE_MS / 1000) + "s")), IDLE_MS)
  }
  const attemptStart = Date.now()
  const timer = setTimeout(() => controller.abort(new Error(configured.label + " hard cap " + Math.round(attemptTimeoutMs / 1000) + "s")), attemptTimeoutMs)
  function runTurnWithHardDeadline(args, signalController, timeoutMs, label) {
    const hardCapMessage = label + " hard cap " + Math.round(timeoutMs / 1000) + "s"
    const turn = runTurn(args)
    let deadlineTimer
    const deadline = new Promise((_, reject) => {
      deadlineTimer = setTimeout(() => {
        signalController.abort(new Error(hardCapMessage))
        reject(new Error(hardCapMessage))
      }, timeoutMs)
    })
    turn.catch(() => {})
    return Promise.race([turn, deadline]).finally(() => clearTimeout(deadlineTimer))
  }
  function hardDeadlineError(err) {
    return /hard cap/i.test(errorText(err))
  }
  function stepBudgetError(err) {
    return /review step budget reached/i.test(errorText(err))
  }
  resetIdle()
  try {
    try {
      await runTurnWithHardDeadline({
        turnId: randomUUID(),
        signal: controller.signal,
        llm,
        tools,
        maxSteps: input.mode === "smoke" || input.mode === "route" ? 1 : REVIEW_MAX_STEPS,
        // 1 = single attempt, no agent-core retry loop (retry.ts:31). The chain of
        // providers IS our retry mechanism; a thrown error (e.g. a 429 now surfaced
        // immediately by maxRetries:0) should fall through to the next provider, not
        // be re-driven here with backoff.
        maxRetryAttempts: 1,
        buildMessages: () => providerMessages(),
        dispatchEvent: createLoopEventDispatcher({ appendTranscriptRecord: async (event) => appendLoopEvent(event) }),
        hooks: {
          beforeStep: async () => {
            if (submittedVerdict) return { block: true, reason: "submit_verdict already captured; review complete" }
            deduper.beginStep()
            beforeStepCount++
            if (input.mode !== "smoke" && input.mode !== "route" && !submittedVerdict && verdictForced < 2 && beforeStepCount >= REVIEW_MAX_STEPS - 2) {
              verdictForced++
              pushHistory(createUserMessage("STOP investigating — you have read enough. Do NOT call any more read/grep/glob tools. Call submit_verdict NOW with the findings you have gathered so far."))
            }
          },
          afterStep: async () => {
            deduper.endStep()
            return submittedVerdict ? { stopTurn: true } : undefined
          },
          prepareToolExecution: async (ctx) => {
            const a = (() => { try { return JSON.stringify(ctx.args) } catch { return "" } })().slice(0, 70)
            if (submittedVerdict && ctx.toolCall.name !== "submit_verdict") {
              return { block: true, reason: "submit_verdict already captured; review complete" }
            }
            if (isCacheableReviewTool(ctx.toolCall.name)) {
              const key = stableToolCacheKey(ctx.toolCall.name, ctx.args)
              if (toolResultCache.has(key)) {
                process.stderr.write("  [" + configured.label + "]   (memoized) " + ctx.toolCall.name + " " + a + "\n")
                return { syntheticResult: toolResultCache.get(key) }
              }
            }
            const cached = deduper.checkSameStep(ctx.toolCall.id, ctx.toolCall.name, ctx.args)
            process.stderr.write("  [" + configured.label + "]   " + (cached !== null ? "(cached) " : "") + ctx.toolCall.name + " " + a + "\n")
            return cached !== null ? { syntheticResult: cached } : undefined
          },
          finalizeToolResult: async (ctx) => {
            const result = await deduper.finalizeResult(ctx.toolCall.id, ctx.toolCall.name, ctx.args, ctx.result)
            if (isCacheableReviewTool(ctx.toolCall.name)) {
              toolResultCache.set(stableToolCacheKey(ctx.toolCall.name, ctx.args), result)
            }
            return result
          },
        },
      }, controller, attemptTimeoutMs, configured.label)
    } catch (err) {
      if (isAbortError(err) && assistantTexts.length === 0) throw err
      if (hardDeadlineError(err)) throw err
      if (stepBudgetError(err)) {
        // Fall through to the verdict-only reask with the evidence gathered so far.
      } else if (!recoverable(err)) throw err
      // fall through to salvage with whatever assistantTexts we captured
    }
    let text = submittedVerdict ? JSON.stringify(submittedVerdict) : (assistantTexts.join("\n").trim() || reasoningTexts.join("\n").trim())
    const narratedText = text // preserve the model's own review prose; a failed reask must not erase it
    if (input.mode !== "smoke" && input.mode !== "route" && (!text || !hasVerdict(text))) {
      // Re-ask in a FRESH, COMPACT context — NOT the full multi-step history. A large
      // history (deepseek over ollama: 81KB of narration PLUS tool-result file contents)
      // makes the provider return an empty completion on the reask, while cogito's much
      // smaller history reasks fine. Feed back only the model's own analysis (capped to
      // the tail), dropping the bulky tool-call/tool-result turns, plus a strict JSON ask.
      const REASK_EVIDENCE_CAP = 24000
      const evidence = narratedText.length > REASK_EVIDENCE_CAP ? narratedText.slice(-REASK_EVIDENCE_CAP) : narratedText
      // Manifest of what the model actually inspected — so it does NOT claim "no files were
      // read" when the dropped tool-result turns are exactly the files it read. Dedup + cap.
      const manifest = [...new Set(readManifest)].slice(0, 40)
      const manifestNote = manifest.length
        ? "You ALREADY investigated the code. Files/patterns you inspected this session:\n- " + manifest.join("\n- ") + "\nBase your verdict on that investigation; do NOT claim you read nothing.\n\n"
        : ""
      const reaskMsg = createUserMessage(
        manifestNote + (evidence
          ? "Below is your own review analysis. Your investigation is complete — do NOT continue analysing, do NOT restate the analysis as prose.\n\n" + evidence + "\n\n"
          : "") + input.reask,
      )
      assistantTexts.length = 0
      reasoningTexts.length = 0
      stepNum = 0
      // Fresh controller (the main timer may already have aborted); bound salvage to the
      // remaining attempt budget (15s floor) so it can't hang to the outer kill
      // (qwen narrate->reask was ec=124).
      const salvageController = new AbortController()
      const salvageMs = Math.max(15000, Math.min(120000, attemptTimeoutMs - (Date.now() - attemptStart)))
      const salvageTimer = setTimeout(() => salvageController.abort(new Error("re-ask timed out")), salvageMs)
      try {
        await runTurnWithHardDeadline({
          turnId: randomUUID(),
          signal: salvageController.signal,
          llm,
          tools: [new SubmitVerdictTool()],
          maxSteps: 1,
          maxRetryAttempts: 2,
          buildMessages: () => [reaskMsg],
          dispatchEvent: createLoopEventDispatcher({ appendTranscriptRecord: async (event) => appendLoopEvent(event) }),
        }, salvageController, salvageMs, configured.label + " re-ask")
      } catch (err) {
        if (!recoverable(err)) throw err
      } finally {
        clearTimeout(salvageTimer)
      }
      // If the compact reask still produced nothing, fall back to the model's narration
      // rather than a false "empty response" — a verbose model DID review; the chain
      // then correctly treats it as "narrated" (no verdict) and falls through.
      text = submittedVerdict ? JSON.stringify(submittedVerdict) : ((assistantTexts.join("\n").trim() || reasoningTexts.join("\n").trim()) || narratedText)
    }
    if (!text) throw new Error(configured.label + " returned empty response")
    return { text, provider: configured.label, model: configured.model }
  } finally {
    clearTimeout(timer)
    clearTimeout(idleTimer)
  }
}

// Narration guard: some reasoning models (cogito) still fail to actually call
// tools even with temperature=0 — they either narrate a tool call as text
// ('<function>Read</function>') OR just reason ('<thinking>I'll use the Read
// tool...') and STOP without calling anything. Both leave the run with NO valid
// verdict (nothing was read). The robust signal is the absence of a verdict, not
// a specific narration shape (hasVerdict/looksNarrated live in chain-logic.mjs).
// Retry the same provider; temperature=0 makes each attempt ~80% land a real
// tool-using review, so a couple retries -> ~99%.
const MAX_NARRATION_RETRIES = 2

const failures = []
function recordChainFailure(configured, reason, meta = {}) {
  const row = {
    provider: configured.label,
    model: configured.model,
    providerID: configured.providerID,
    modelID: configured.modelID,
    reason,
    ...meta,
  }
  failures.push(row)
  process.stderr.write(
    "redteam-chain-hop: " + configured.label + " failed reason=" + JSON.stringify(reason) +
      (meta.elapsedMs != null ? " elapsedMs=" + meta.elapsedMs : "") +
      (meta.budgetMs != null ? " budgetMs=" + meta.budgetMs : "") + "\n",
  )
}
// Minimum budget a hop needs to do a REAL review (read a few files + conclude), not just
// to start. The old 20s floor let a near-exhausted hop START, make 1-2 tool calls, run
// out of time, and emit a HOLLOW verdict ("no investigation performed") — adopted but
// worthless. That slipped through on the long chains (qwen 6-hop / google 4-hop) the
// later hops of which inherit a tiny remaining budget. Failing the attempt instead lets
// the next hop — or the panel backfill — take over with a fresh full budget. The LAST
// provider is exempt: with nothing to fall through to, a hollow verdict still beats none.
const MIN_REVIEW_BUDGET_MS = 45000
for (let ci = 0; ci < configuredChain.length; ci++) {
  const configured = configuredChain[ci]
  const isLastProvider = ci === configuredChain.length - 1
  const floor = isLastProvider ? 20000 : MIN_REVIEW_BUDGET_MS
  if (deadline - Date.now() < floor) {
    recordChainFailure(configured, "insufficient budget for a real review before attempt (" + Math.round((deadline - Date.now()) / 1000) + "s left, need " + Math.round(floor / 1000) + "s)", {
      remainingMs: deadline - Date.now(),
      requiredMs: floor,
    })
    continue
  }
  // Reserve budget for the remaining fallbacks so a verbose provider (e.g.
  // kimi-for-coding over-reasoning, which streams reasoning forever without a verdict
  // and so never trips the idle timer) can't eat the whole deadline on one attempt and
  // starve them. The last provider gets whatever is left.
  //
  // BUT cap the reservation: a flat remainingProviders*45s over-reserves on a long
  // chain and starves the FIRST (usually BEST) provider down to the 30s floor — e.g. the
  // 6-hop qwen / 4-hop google chains floored provider 0 at 30s and hard-capped it while it
  // was still actively investigating (visible progress), the opposite of intended. The
  // reservation now never exceeds HALF the remaining deadline, so this attempt always keeps
  // at least ~half the runway to actually conclude, while fallbacks still get a real share.
  const remaining = deadline - Date.now()
  const remainingProviders = configuredChain.length - ci - 1
  const reservation = Math.min(remainingProviders * 45000, remaining / 2)
  const providerBudget = Math.max(30000, Math.min(PER_PROVIDER_CAP, remaining - reservation))
  const providerStartedAt = Date.now()
  try {
    // Hold the gate slot for THIS provider only across its attempts (the slow
    // model calls), then release before emit. A fast-failing provider (429)
    // acquires + releases in ~1s; the working provider holds it for the review,
    // which is what actually bounds e.g. ollama-cloud concurrency host-wide.
    const result = await withProviderSlot(configured.providerID, async () => {
      let r = await runWithProvider(configured, providerBudget, tools)
      // Retry the SAME provider (while budget remains) on a non-result: no verdict
      // (narration) OR a needs-attention verdict with no findings (a vague concern
      // that isn't actionable) — re-asking usually yields itemized findings or a
      // clean approve. Bounded so a slow provider isn't re-run 3x into the deadline.
      const needsRetry = (t) => input.mode !== "route" && (looksNarrated(t) || needsAttentionWithoutFindings(t))
      // Diversify on a non-result: re-asking the SAME provider only pays off as a
      // LAST resort. When a fallback provider remains, fall through to it (a
      // different lineage is less likely to narrate) instead of burning the deadline
      // re-asking a slow narrating provider — that was what starved the working
      // Alibaba fallback when ollama narrated 2x on a 42k-token file. The last
      // provider in the chain still retries (no fallback left to diversify to).
      const maxRetries = isLastProvider ? MAX_NARRATION_RETRIES : 0
      for (let i = 0; i < maxRetries && needsRetry(r.text) && (deadline - Date.now()) > 40000; i++) {
        r = await runWithProvider(configured, providerBudget, tools)
      }
      return r
    })
    // Fall through to the NEXT provider only on no verdict at all; a needs-attention
    // with no findings is accepted after retries (the schema_warning annotation
    // flags it) rather than burning the whole chain on it.
    if (input.mode !== "route" && looksNarrated(result.text)) {
      // Still no verdict after retries — treat as a provider failure and fall
      // through to the next provider in the chain rather than emitting narration.
      recordChainFailure(configured, "no verdict (narrated) after retries", {
        elapsedMs: Date.now() - providerStartedAt,
        budgetMs: providerBudget,
      })
      continue
    }
    process.stdout.write(JSON.stringify({ ...result, lineage, usage: null, providerFailures: failures }) + "\n")
    process.exit(0)
  } catch (err) {
    if (!providerFailure(err)) throw err
    recordChainFailure(configured, errorText(err).slice(0, 500), {
      elapsedMs: Date.now() - providerStartedAt,
      budgetMs: providerBudget,
    })
  }
}
// All providers in the chain failed — an EXPECTED outcome (quota/outage/short
// deadline), not a bridge bug. Emit a STRUCTURED error on stdout and exit 1 cleanly
// instead of throwing uncaught, which printed a scary "Node.js" crash banner to
// stderr and made an ordinary chain-exhaustion indistinguishable from a real crash.
// The parent (runBridge) reads _bridgeError and surfaces it as the failure message.
process.stdout.write(JSON.stringify({
  _bridgeError: "all " + lineage + " provider fallbacks failed: " + failures.map((f) => f.provider + ": " + f.reason).join(" | "),
  providerFailures: failures,
}) + "\n")
process.exit(1)