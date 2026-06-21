// Live model discovery for redteam lineages. kimi-cli already discovers models
// dynamically (listModelsFromHarness + kosong's models.dev catalog); the providers are
// `models:(dynamic)` in the kimi config for exactly this reason. Rather than hand-maintain
// concrete model ids in models.json, derive provider/model availability from each
// provider's /v1/models endpoint, and classify a scan/deep tier.
//
// Pure classifiers (classifyTier, inferLineage) are side-effect-free and unit-tested in
// model-discovery.test.mjs. discoverModels() wraps them with injectable fs/fetch/clock
// seams so the I/O is testable without the network.
import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { parse as parseToml } from "smol-toml"
import { inferLineage, isMinimaxM3Model, modelsListUrl, resolveModelsCatalogBaseUrl, parseRosterCacheByProvider, rosterCacheWriteBody, rosterEntriesFromByProvider } from "./chain-logic.mjs"

// Tier by parameter count first (most reliable), then by name keyword. Unknown size →
// "deep" (conservative: never put an unsized model in the cheap scan tier by accident).
// Scan = small/fast for broad antipattern sweeps; deep = heavyweight semantic review.
export function classifyTier(modelId) {
  const name = String(modelId || "").toLowerCase().split("/").pop()
  const pm = name.match(/[:-](\d+(?:\.\d+)?)(b|t)\b/) // :31b, :1t, -8b, :397b
  if (pm) {
    const n = pm[2] === "t" ? Number(pm[1]) * 1000 : Number(pm[1])
    return n <= 32 ? "scan" : "deep"
  }
  if (isMinimaxM3Model(name)) return "deep"
  if (/\b(flash|nano|mini|small|lite|tiny|fast)\b/.test(name)) return "scan"
  if (/\b(large|pro|max|ultra|thinking|coder)\b/.test(name)) return "deep"
  return "deep"
}

/**
 * Hunt/bughunt three-tier bucket: small (skip), scan (explore), solve (verify).
 * Keep in sync with classifyHuntTier inside runner.mjs BRIDGE template.
 */
export function classifyHuntTier(modelId) {
  const n = String(modelId || "").toLowerCase().split("/").pop()
  const pm = n.match(/[:-](\d+(?:\.\d+)?)(b|t)\b/)
  let size = 0
  if (pm) {
    size = pm[2] === "t" ? parseFloat(pm[1]) * 1000 : parseFloat(pm[1])
  }

  if (/\bgemma.?4\b/.test(n) || /\bflash\b/.test(n)) return "scan"

  if (size > 70) return "solve"
  if (size > 25 && size <= 70) return "scan"
  if (size > 0 && size <= 25) return "small"

  if (/\b(tiny|nano|mini|small|lite|light)\b/.test(n)) return "small"
  if (/\b(medium|light-pro)\b/.test(n)) return "scan"
  if (/\b(large|pro|max|ultra|thinking|coder|reasoner|deepseek-v4-pro)\b/.test(n)) return "solve"

  return "solve"
}

/** Hunt scan rotation pool — includes M3 (thinking off at runtime). */
export function isHuntScanPoolModel(modelId) {
  return classifyHuntTier(modelId) === "scan" || isMinimaxM3Model(modelId)
}

/** Hunt solve rotation pool — includes M3 (thinking on at runtime). */
export function isHuntSolvePoolModel(modelId) {
  return classifyHuntTier(modelId) === "solve" || isMinimaxM3Model(modelId)
}

// Lineage family from a model id (mirrors runner.mjs inferLineage; kept in sync so the
// discovered catalog maps onto the same provider-fallback families). Returns null if none.
// inferLineage lives in chain-logic.mjs (single home, shared with the runner); re-exported
// here so discovered models classify under the SAME family the runner runs them as.
export { inferLineage }

/**
 * Return the model labels that are explicitly declared in a kimi-code TOML
 * under [models.*]. This is the synchronous "what can I actually call right now"
 * view for the user's local config. Used by panel/runner when the live catalog
 * needs configured aliases for provider metadata.
 */
export function getDeclaredModels(configPath = null) {
  const p = configPath || process.env.KIMI_CODE_CONFIG || join(homedir(), ".kimi-code", "config.toml")
  try {
    const txt = readFileSync(p, "utf8")
    const cfg = parseToml(txt)
    return Object.keys(cfg.models || {})
  } catch {
    return []
  }
}

function envRef(v, env = process.env) {
  return typeof v === "string" ? v.replace(/^\{env:([^}]+)\}$/, (_, k) => env[k] || "") : v
}

function providerKey(provider, providerCfg = {}, env = process.env) {
  const key = envRef(providerCfg?.api_key, env) || ""
  const type = typeof providerCfg?.type === "string" ? providerCfg.type : ""
  if (key) return key
  if (type === "kimi" || provider === "managed:kimi-code") return env.KIMI_API_KEY || env.MOONSHOT_API_KEY || ""
  return ""
}

function catalogHeaders(provider, key) {
  if (provider === "google" || provider === "google-genai" || provider === "gemini") {
    return { "x-goog-api-key": key, "User-Agent": "KimiCLI/1.43.0" }
  }
  return { Authorization: `Bearer ${key}`, "User-Agent": "KimiCLI/1.43.0" }
}

function normalizeCatalogModelName(name) {
  return String(name || "").replace(/^models\//, "")
}

function modelNameForAlias(alias, modelCfg = {}) {
  const slash = String(alias || "").indexOf("/")
  return typeof modelCfg?.model === "string" && modelCfg.model.length
    ? modelCfg.model
    : slash >= 0
      ? String(alias).slice(slash + 1)
      : String(alias || "")
}

const DEFAULT_TTL_MS = 6 * 60 * 60 * 1000 // 6h — model lists change rarely

export async function inspectProviderStatus(opts = {}) {
  const {
    configPath = join(homedir(), ".kimi-code", "config.toml"),
    fetchImpl = globalThis.fetch,
    live = true,
    timeoutMs = 8_000,
    env = process.env,
  } = opts

  let cfg
  try {
    cfg = parseToml(readFileSync(configPath, "utf8"))
  } catch {
    return []
  }

  const aliasesByProvider = new Map()
  for (const [alias, modelCfg] of Object.entries(cfg.models || {})) {
    const provider = typeof modelCfg?.provider === "string" ? modelCfg.provider : String(alias).split("/")[0]
    if (!aliasesByProvider.has(provider)) aliasesByProvider.set(provider, [])
    aliasesByProvider.get(provider).push({
      alias,
      model: modelNameForAlias(alias, modelCfg),
      lineage: inferLineage(alias) || inferLineage(modelNameForAlias(alias, modelCfg)),
    })
  }

  const providers = new Set([...Object.keys(cfg.providers || {}), ...aliasesByProvider.keys()])
  const rows = []
  for (const provider of [...providers].sort()) {
    const providerCfg = cfg.providers?.[provider]
    const aliases = aliasesByProvider.get(provider) || []
    const key = providerKey(provider, providerCfg, env)
    const base = resolveModelsCatalogBaseUrl(provider, envRef(providerCfg?.base_url, env) || "")
    const catalogUrl = base ? modelsListUrl(base) : ""
    const lineages = [...new Set(aliases.map((entry) => entry.lineage).filter(Boolean))].sort()
    const row = {
      provider,
      configured: Boolean(providerCfg),
      has_key: Boolean(key),
      type: typeof providerCfg?.type === "string" ? providerCfg.type : "",
      catalog_url: catalogUrl,
      live: live ? "unchecked" : "skipped",
      live_model_count: 0,
      declared_aliases: aliases.length,
      live_declared_aliases: 0,
      lineages,
      error: "",
    }
    if (!live) {
      rows.push(row)
      continue
    }
    if (!providerCfg) {
      row.live = "missing-config"
      row.error = "provider is referenced by a model alias but missing provider config"
      rows.push(row)
      continue
    }
    if (!key) {
      row.live = "missing-key"
      row.error = "provider has no resolved api_key"
      rows.push(row)
      continue
    }
    if (!catalogUrl) {
      row.live = "missing-catalog"
      row.error = "provider has no usable /models catalog URL"
      rows.push(row)
      continue
    }
    try {
      const signal = Number.isFinite(timeoutMs) && timeoutMs > 0 && typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function"
        ? AbortSignal.timeout(timeoutMs)
        : undefined
      const response = await fetchImpl(catalogUrl, { headers: catalogHeaders(provider, key), signal })
      if (!response.ok) {
        row.live = "error"
        row.error = `HTTP ${response.status || "not-ok"}`
        rows.push(row)
        continue
      }
      const body = await response.json()
      const raw = Array.isArray(body?.data) ? body.data : Array.isArray(body?.models) ? body.models : Array.isArray(body) ? body : []
      const names = new Set(raw
        .map((model) => typeof model === "string" ? model : model?.id || model?.name)
        .filter((name) => typeof name === "string")
        .map(normalizeCatalogModelName))
      row.live = "ok"
      row.live_model_count = names.size
      row.live_declared_aliases = aliases.filter((entry) => names.has(entry.model)).length
    } catch (err) {
      row.live = "error"
      row.error = err?.message || String(err)
    }
    rows.push(row)
  }
  return rows
}

// Fetch live models from the dynamic-catalog providers (ollama-cloud, opencode-go) in the
// kimi config and return [{ id: "provider/model", lineage, tier }]. cachePath is opt-in;
// returns [] on total failure so the caller can degrade or ask for explicit lineages.
export async function discoverModels(opts = {}) {
  const {
    configPath = join(homedir(), ".kimi-code", "config.toml"),
    cachePath = null,
    ttlMs = DEFAULT_TTL_MS,
    fetchImpl = globalThis.fetch,
    now = Date.now,
    providerFilter = /ollama|opencode|zen|go|openrouter|alibaba-token-plan|token-plan|minimax-coding-plan/i,
    includeLiveOnly = false,
  } = opts

  let stale = null
  try {
    if (cachePath && existsSync(cachePath)) {
      const c = JSON.parse(readFileSync(cachePath, "utf8"))
      const byProvider = parseRosterCacheByProvider(c)
      if (byProvider) {
        const entries = rosterEntriesFromByProvider(byProvider, classifyTier)
        if (entries.length) {
          if (c.at && now() - c.at < ttlMs) return entries
          stale = entries
        }
      }
    }
  } catch {
    /* fall through to live discovery */
  }

  let cfg
  try {
    cfg = parseToml(readFileSync(configPath, "utf8"))
  } catch {
    return stale || []
  }
  const out = []
  const seen = new Set()
  const declaredNamesByProvider = new Map()
  const pushModel = (id) => {
    if (typeof id !== "string" || !id || seen.has(id)) return
    seen.add(id)
    out.push({ id, lineage: inferLineage(id), tier: classifyTier(id) })
  }

  for (const [alias, modelCfg] of Object.entries(cfg.models || {})) {
    const pid = typeof modelCfg?.provider === "string" ? modelCfg.provider : alias.split("/")[0]
    if (!providerFilter.test(pid)) continue
    const provider = cfg.providers?.[pid]
    const key = envRef(provider?.api_key) || ""
    if (!provider || !key) continue
    const name = typeof modelCfg?.model === "string" && modelCfg.model.length ? modelCfg.model : alias.slice(pid.length + 1)
    if (!declaredNamesByProvider.has(pid)) declaredNamesByProvider.set(pid, new Set())
    declaredNamesByProvider.get(pid).add(name)
    pushModel(alias)
  }

  for (const [pid, p] of Object.entries(cfg.providers || {})) {
    if (!providerFilter.test(pid)) continue
    const base = resolveModelsCatalogBaseUrl(pid, envRef(p?.base_url) || "")
    const key = envRef(p?.api_key) || ""
    if (!base || !key) continue
    const url = modelsListUrl(base)
    try {
      const r = await fetchImpl(url, { headers: { Authorization: `Bearer ${key}`, "User-Agent": "KimiCLI/1.43.0" } })
      if (!r.ok) continue
      const j = await r.json()
      let raw = j.data || j.models || j || []
      // COST GUARD: OpenRouter exposes ~315 PAID models. Keep only models whose pricing is
      // actually $0 (prompt+completion+request) — broader & safer than the ":free" suffix,
      // which misses genuinely-$0 models. Also require text output so we skip $0 image/audio
      // generators (e.g. google/lyria-* music models) that can't act as code-review scouts.
      if (pid === "openrouter") raw = (Array.isArray(raw) ? raw : []).filter((m) => {
        const p = m?.pricing || {}
        const zero = ["prompt", "completion", "request"].every((k) => Number(p[k] ?? 0) === 0)
        // OUTPUT modality must be text-ONLY: reject $0 models that also emit audio/image
        // (e.g. google/lyria-* output ["text","audio"]) — useless as code-review scouts.
        const arch = m?.architecture || {}
        const outs = Array.isArray(arch.output_modalities) && arch.output_modalities.length
          ? arch.output_modalities.map(String)
          : String(arch.modality || "text").split("->").pop().split("+")
        const textOnlyOut = outs.length > 0 && outs.every((o) => /text/i.test(o))
        return zero && textOnlyOut
      })
      let list = (Array.isArray(raw) ? raw : []).map((m) => m?.id || m?.name || m).filter((x) => typeof x === "string")

      // Version-sort every lineage: highest M* / dotted version first.
      // Non-versioned names fall back to alpha-desc. This guarantees the
      // newest variant the provider currently advertises is always tried first.
      list = list.sort((a, b) => {
        const ra = a.match(/M(\d+(?:\.\d+)?)/i) || a.match(/(\d+\.\d+)/)
        const rb = b.match(/M(\d+(?:\.\d+)?)/i) || b.match(/(\d+\.\d+)/)
        const na = ra ? parseFloat(ra[1]) : 0
        const nb = rb ? parseFloat(rb[1]) : 0
        if (na !== nb) return nb - na
        return b.localeCompare(a)
      })

      const declaredNames = declaredNamesByProvider.get(pid)
      for (const id of list) {
        if (!includeLiveOnly && declaredNames && !declaredNames.has(id)) continue
        if (!includeLiveOnly && !declaredNames) continue
        pushModel(`${pid}/${id}`)
      }
    } catch {
      /* skip an unreachable provider */
    }
  }

  if (out.length) {
    try {
      const byProvider = {}
      for (const row of out) {
        const id = row.id
        const slash = id.indexOf("/")
        if (slash < 0) continue
        const pid = id.slice(0, slash)
        const name = id.slice(slash + 1)
        if (!byProvider[pid]) byProvider[pid] = []
        byProvider[pid].push(name)
      }
      if (!cachePath) return out
      mkdirSync(dirname(cachePath), { recursive: true })
      // atomic replace: write a temp then rename, so a concurrent reader never sees a
      // half-written file (which would JSON.parse-fail and empty the cached catalog).
      const tmp = `${cachePath}.tmp-${process.pid}`
      writeFileSync(tmp, JSON.stringify(rosterCacheWriteBody(byProvider, now())))
      renameSync(tmp, cachePath)
    } catch {
      /* cache is best-effort */
    }
    return out
  }
  // live discovery turned up nothing (provider outage / all unreachable) — serve the
  // expired cache rather than an empty catalog, so a transient failure doesn't blank it.
  return stale || []
}
