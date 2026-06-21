// Pure, side-effect-free decision logic for the redteam provider chain and the
// --all-files panel. Extracted from runner.mjs (bundled into
// bridge.bundle.mjs by build-bridge.mjs — esbuild inlines this import) and from
// panel.mjs so the logic is exhaustively unit-testable without the agent
// harness, the network, or the clock. Nothing here reads Date.now(), the
// filesystem, or env — callers pass time/inputs in. Tests: chain-logic.test.mjs.

import { jsonrepair } from "jsonrepair"

export const MIN_ATTEMPT_MS = 30000

// Single home for lineage-family inference (the runner runs models under a lineage; model
// discovery classifies discovered models the same way). One definition so the two can't
// drift. Returns null when no family matches.
export function inferLineage(modelId) {
  const m = String(modelId || "").toLowerCase()
  if (/glm|zai|z-ai|zhipu/.test(m)) return "glm"
  if (/kimi|moonshot/.test(m)) return "kimi"
  if (/minimax/.test(m)) return "minimax"
  // Match the MODEL name, not the Alibaba provider prefix — Alibaba serves qwen/deepseek/etc.
  if (/qwen/.test(m)) return "qwen"
  if (/deepseek/.test(m)) return "deepseek"
  if (/mimo|xiaomi/.test(m)) return "mimo"
  if (/devstral|ministral|mistral/.test(m)) return "mistral"
  if (/nemotron|nvidia/.test(m)) return "nemotron"
  if (/gpt-oss/.test(m)) return "gpt-oss"
  if (/cogito/.test(m)) return "cogito"
  if (/gemma|gemini|google/.test(m)) return "google"
  return null
}

/** MiniMax M3 — eligible for both scan (thinking off) and solve (thinking on) pools. */
export function isMinimaxM3Model(modelId) {
  const n = String(modelId || "").toLowerCase().split("/").pop()
  return /\bminimax[- ]?m3\b/.test(n)
}

/** @deprecated use isMinimaxM3Model */
export const isMinimaxM3ScanModel = isMinimaxM3Model

const THINKING_EFFORT_VALUES = ["off", "low", "medium", "high", "xhigh", "max"]

/**
 * M3 thinking: env wins; else scan → off, solve/default → high (kosong maps non-off to adaptive).
 *
 * Purpose: one model, two harness modes without duplicating catalog entries.
 * Consumer: runner.mjs buildProvider for minimax-coding-plan / M3 variants.
 */
export function resolveMinimaxM3ThinkingEffort({ env = {}, huntPhase = null, salvage = false } = {}) {
  const envThinking = String(env.REDTEAM_THINKING_EFFORT || "").trim().toLowerCase()
  if (THINKING_EFFORT_VALUES.includes(envThinking)) return envThinking
  if (salvage || huntPhase === "scan" || env.REDTEAM_SCAN_PHASE === "1") return "off"
  return "high"
}

/**
 * Resolve the provider/model id that actually served a review hop.
 *
 * Purpose: roster selection can differ from the chain's served model when a backend
 *          substitutes its own catalog entry (moonshot → kimi); attribution must
 *          follow the hop, not the pre-routing label.
 * Consumer: runner.mjs verdict emit; panel.mjs panel-result.json aggregation.
 */
export function resolveServedModelRef(bridgeResult, requestedRef = "") {
  const requested = String(requestedRef || "").trim()
  const label = typeof bridgeResult?.provider === "string" ? bridgeResult.provider.trim() : ""
  const short = typeof bridgeResult?.model === "string" ? bridgeResult.model.trim() : ""
  if (label.includes("/")) return label
  if (short.includes("/")) return short
  if (label && short) return `${label}/${short}`
  return label || short || requested
}

/**
 * Normalize roster.json cache to provider → model-id[] regardless of writer version.
 *
 * Purpose: runner and model-discovery shared one cache file with incompatible shapes.
 * Consumer: model-discovery.mjs discoverModels when a caller opts into a cachePath.
 */
export function parseRosterCacheByProvider(cache) {
  if (!cache || typeof cache !== "object") return null
  if (cache.byProvider && typeof cache.byProvider === "object") {
    return normalizeRosterByProvider(cache.byProvider)
  }
  const models = cache.models
  if (models && typeof models === "object" && !Array.isArray(models)) {
    return normalizeRosterByProvider(models)
  }
  if (Array.isArray(models)) {
    const out = {}
    for (const row of models) {
      const id = typeof row === "string" ? row : row?.id
      if (typeof id !== "string") continue
      const slash = id.indexOf("/")
      if (slash < 0) continue
      const pid = id.slice(0, slash)
      const name = id.slice(slash + 1)
      if (!name) continue
      if (!out[pid]) out[pid] = []
      if (!out[pid].includes(name)) out[pid].push(name)
    }
    return normalizeRosterByProvider(out)
  }
  return null
}

function normalizeRosterByProvider(byProvider) {
  const out = {}
  for (const [pid, names] of Object.entries(byProvider || {})) {
    if (!Array.isArray(names)) continue
    const list = names.filter((n) => typeof n === "string" && n.length > 0)
    if (list.length) out[pid] = list
  }
  return Object.keys(out).length ? out : null
}

/**
 * Canonical on-disk roster cache body (schema v2).
 *
 * Purpose: one writer shape for runner + model-discovery.
 * Consumer: model-discovery.mjs discoverModels when a caller opts into a cachePath.
 */
export function rosterCacheWriteBody(byProvider, at = Date.now()) {
  return { schema: 2, at, byProvider: normalizeRosterByProvider(byProvider) || {} }
}

/**
 * Flat roster entries for panel discovery from a provider-keyed catalog map.
 *
 * Purpose: model-discovery returns [{ id, lineage, tier }] from shared cache.
 * Consumer: model-discovery.mjs discoverModels.
 */
export function rosterEntriesFromByProvider(byProvider, classifyTierFn) {
  const classify = typeof classifyTierFn === "function" ? classifyTierFn : () => "deep"
  const out = []
  for (const [pid, names] of Object.entries(normalizeRosterByProvider(byProvider) || {})) {
    for (const name of names) {
      const id = `${pid}/${name}`
      out.push({ id, lineage: inferLineage(id), tier: classify(id) })
    }
  }
  return out
}

/**
 * One row in the panel attempt log (success or failure).
 *
 * Purpose: backfill may replace a failed lineage — the report must still show what failed
 *          and which replacement ran.
 * Consumer: panel.mjs lineage_attempts in panel-result.json.
 */
export function summarizeLineageAttempt(v, meta = {}) {
  const failed = isHarnessFailureVerdict(v)
  return {
    panel_slot: v?.panel_slot ?? meta.panel_slot ?? null,
    model: v?.model,
    requested: v?.requested ?? v?.model,
    verdict: v?.verdict,
    findings: (v?.findings || []).length,
    failed,
    ...(v?.summary ? { summary: String(v.summary).slice(0, 400) } : {}),
    ...(Array.isArray(v?.providerFailures) ? { providerFailures: v.providerFailures } : {}),
    ...(v?._auto ? { _auto: v._auto } : {}),
    ...(meta.backfill_round != null ? { backfill_round: meta.backfill_round } : {}),
  }
}

/**
 * Pick the next backfill model refs for failed panel slots.
 *
 * Purpose: backfill switches to another roster lineage per failed slot — deterministic
 *          roster order, not a fresh random draw.
 * Consumer: panel.mjs backfill loop.
 */
export function planBackfillReplacements(roster, tried, deficit, usedGroups, groupOf) {
  if (deficit <= 0) return []
  const ranked = (Array.isArray(roster) ? roster : [])
    .filter((m) => !tried.has(m))
    .map((m, rosterIndex) => ({
      m,
      rosterIndex,
      groupPenalty: usedGroups.has(groupOf(m)) ? 1 : 0,
    }))
    .sort((a, b) => a.groupPenalty - b.groupPenalty || a.rosterIndex - b.rosterIndex)
  return ranked.slice(0, deficit).map((r) => r.m)
}

/**
 * Build authoritative panel attribution from per-lineage verdict rows.
 *
 * Purpose: panel-result.json must report served models, not pre-backend roster picks.
 * Consumer: panel.mjs when writing panel-result.json.
 */
export function buildPanelAttribution(verdicts) {
  const rows = Array.isArray(verdicts) ? verdicts : []
  const served = rows.map((v) => v?.model).filter(Boolean)
  const requested = rows.map((v) => v?.requested ?? v?.model).filter(Boolean)
  return {
    panel: served,
    panel_requested: requested,
    per_model: rows.map((v) => ({
      panel_slot: v?.panel_slot ?? null,
      model: v?.model,
      requested: v?.requested ?? v?.model,
      verdict: v?.verdict,
      findings: (v?.findings || []).length,
    })),
  }
}

// Flatten an error into a single searchable string (name/status/code/message).
export function errorText(err) {
  const parts = []
  if (err?.name) parts.push(String(err.name))
  if (err?.statusCode) parts.push(String(err.statusCode))
  if (err?.status) parts.push(String(err.status))
  if (err?.code) parts.push(String(err.code))
  if (err?.message) parts.push(String(err.message))
  if (parts.length === 0) parts.push(String(err))
  return parts.join(": ")
}

// True when an error means "this provider can't serve the request" — a 429/quota/
// auth/network/timeout/empty-response class fault that should fall through to the
// next provider in the chain rather than abort the whole review. Anything else is
// a real fault the caller should rethrow.
export function providerFailure(err) {
  const text = errorText(err)
  // NOTE: 'auth' as a bare token was too greedy (matched "author"/"oauth"/a
  // stacktrace) and could swallow a real code fault as a provider failure. Use
  // 'authenticat' (authentication/authenticated) + the explicit 401/403/
  // unauthorized/forbidden tokens instead.
  return /ChatProviderError|APIConnectionError|APITimeoutError|APIStatusError|APIProviderRateLimitError|APIEmptyResponse|only thinking content|thinking content without|apiKey is required|access_terminated|quota|billing|unauthori[sz]ed|forbidden|authenticat|401|403|429|rate.?limit|too many requests|empty response|timed? ?out|timeout|deadline|fetch failed|network|connection|connect|disconnect|terminated|ECONN|ENOTFOUND|ETIMEDOUT|ECONNRESET/i.test(text)
}

// A panel result is a CHAIN FAILURE (every provider hop failed — a hole to refill)
// rather than a real review when EITHER: runOne stamped verdict:"error" (the runner
// emitted non-JSON / the spawn crashed), OR the runner's fail() path emitted a
// needs-attention whose summary is the "Lineage review failed:" sentinel (runner.mjs
// throws "all <lineage> ... fallbacks failed" → fail() → needs-attention, because the
// runner's verdict enum has no "error"). The panel backfill must treat BOTH as a hole;
// a bare verdict!=="error" check missed the second — the FAR more common — case, so
// backfill never fired on a genuine chain exhaustion. A parseable object that simply
// lacks a verdict is NOT itself a chain failure (it is handled elsewhere).
export function isChainFailure(v) {
  if (!v || typeof v !== "object") return true
  if (v.verdict === "error") return true
  if (v.verdict === "needs-attention" && /^Lineage review failed:/.test(String(v.summary || ""))) return true
  return false
}

/**
 * True when a per-lineage row is a harness/runner failure, not a substantive review.
 *
 * Purpose: panel rollup must not treat parse/spawn/mode failures as "approve".
 * Consumer: computePanelVerdict.
 */
export function isHarnessFailureVerdict(v) {
  if (isChainFailure(v)) return true
  if (!v || typeof v !== "object") return false
  const auto = String(v._auto || "")
  if (
    auto === "json-parse-failed" ||
    auto === "invalid-verdict-value" ||
    auto === "schema-missing-confidence" ||
    auto === "hard-cap-or-broken-provider"
  ) {
    return true
  }
  const findings = Array.isArray(v.findings) ? v.findings : []
  if (findings.length > 0) return false
  const summary = String(v.summary || "")
  if (v.verdict !== "needs-attention") return false
  return /^(Bad --mode|Bad model|spawn failed:|Could not infer lineage|Moonshot reviewer did not return parseable|No input to review|--input read failed:|git diff failed:)/.test(
    summary,
  )
}

/**
 * True when a panel slot produced a substantive review (not a chain/harness hole).
 *
 * Purpose: one predicate for backfill, successfulVerdicts, and target counting.
 * Consumer: panel.mjs backfill loop.
 */
export function isPanelSlotSatisfied(v) {
  return !isChainFailure(v) && !isHarnessFailureVerdict(v)
}

/**
 * Pick up to n models from a shuffled roster with at most one per lineage family.
 *
 * Purpose: initial panel draw must reach -n distinct lineages when the roster allows it.
 * Consumer: panel.mjs random panel selection.
 */
export function pickDistinctLineagePanel(shuffled, n, linOf) {
  const seen = new Set()
  const models = []
  for (const m of shuffled || []) {
    if (models.length >= n) break
    const lin = linOf(m)
    if (lin) {
      if (seen.has(lin)) continue
      seen.add(lin)
    }
    models.push(m)
  }
  return models
}

/**
 * Swap the last panel pick for a different heritage group without duplicating lineage.
 *
 * Purpose: east/west stratification after distinct-lineage selection.
 * Consumer: panel.mjs random panel selection.
 */
export function stratifyPanelSwap(models, shuffled, groupOf, linOf) {
  const rows = Array.isArray(models) ? [...models] : []
  if (rows.length < 2 || new Set(rows.map(groupOf)).size > 1) return rows
  const seen = new Set()
  for (const m of rows) {
    const lin = linOf(m)
    if (lin) seen.add(lin)
  }
  const replacement = (shuffled || []).find((m) => {
    if (groupOf(m) === groupOf(rows[0])) return false
    if (rows.includes(m)) return false
    const lin = linOf(m)
    if (lin && seen.has(lin)) return false
    return true
  })
  if (!replacement) return rows
  rows[rows.length - 1] = replacement
  return rows
}

/**
 * Merge a backfill round without dropping failures that had no replacement attempt.
 *
 * Purpose: partial roster exhaustion must not erase failed slots from the verdict set.
 * Consumer: panel.mjs backfill loop.
 */
export function mergeBackfillRound({ verdicts, satisfied, fresh, stillFailed, unfilledFailures = [] }) {
  const ok = typeof satisfied === "function" ? satisfied : () => true
  return (verdicts || []).filter(ok).concat(fresh || [], stillFailed || [], unfilledFailures || [])
}

/**
 * Roll up per-lineage verdicts + merged findings into the panel-level verdict.
 *
 * Purpose: fail closed — errors and hollow harness failures must not read as approve.
 * Consumer: panel.mjs panel-result.json.
 */
export function computePanelVerdict(verdicts, findings = [], opts = {}) {
  const rows = Array.isArray(verdicts) ? verdicts : []
  const kept = Array.isArray(findings) ? findings : []
  const targetCount = opts.targetCount
  const satisfiedCount = opts.satisfiedCount

  if (
    typeof targetCount === "number" &&
    typeof satisfiedCount === "number" &&
    satisfiedCount < targetCount
  ) {
    return "needs-attention"
  }

  if (rows.some((v) => isHarnessFailureVerdict(v))) return "needs-attention"
  if (kept.some((f) => f.severity === "critical" || f.severity === "high")) return "needs-attention"
  if (kept.some((f) => f.severity === "medium" || f.severity === "low")) return "needs-attention"

  if (opts.verified) {
    if (rows.length > 0 && rows.every((v) => v?.verdict === "approve") && kept.length === 0) return "approve"
    return kept.length > 0 ? "needs-attention" : "approve"
  }

  if (rows.some((v) => v?.verdict === "needs-attention")) return "needs-attention"
  if (rows.length > 0 && rows.every((v) => v?.verdict === "approve")) return "approve"
  return "needs-attention"
}

// A TRANSIENT provider error — a rate-limit/overload/capacity fault that the SAME
// provider will likely serve on a short backoff (unlike auth/quota-exhausted/parse
// faults, which won't recover in seconds). A strict subset of providerFailure: used to
// decide whether to RETRY the same provider with backoff before falling through the
// chain. Google's free Gemini tier (~10 RPM) 503s/429s under a multi-step review; a
// brief backoff clears it. Kept narrow on purpose — a 401/parse error is not retried.
export function isTransient(err) {
  const text = errorText(err)
  // A DAILY/monthly quota or billing fault is NOT recoverable on a seconds-scale backoff —
  // exclude it even if it rides on a 429 (those just waste the deadline before failing).
  if (/quota|daily|per.?day|billing|exhausted your|insufficient balance|out of credit/i.test(text)) return false
  // \b-anchored numeric codes so a stray "503"/"429" inside an id/token-count is not a match.
  // "try again"/"temporarily" intentionally omitted — too broad (matches permanent auth errors).
  return /\b(503|429)\b|RESOURCE_EXHAUSTED|UNAVAILABLE|overloaded|high demand|too many requests|rate.?limit/i.test(text)
}

// Per-provider attempt budget under a SHARED deadline (NOT an even split of the
// total). Fast-failing providers (429 in ~1s) consume almost nothing, so the
// surviving working provider inherits the remaining budget, capped per attempt.
// Floored at MIN_ATTEMPT_MS so a near-exhausted deadline still gives one real try.
export function computeAttemptBudget(deadlineMs, nowMs, perProviderCap, minAttemptMs = MIN_ATTEMPT_MS) {
  return Math.max(minAttemptMs, Math.min(perProviderCap, deadlineMs - nowMs))
}

// Extract the verdict OBJECT: strip think/reasoning, take a fenced JSON block (else the
// outermost {...}), then JSON.parse with a jsonrepair fallback — returning it only if it
// carries a recognised verdict value. Shared by the reask gate (hasVerdict) and the final
// parser (runner.extractVerdict) so the gate matches what actually parses.
export function extractVerdictObject(text) {
  if (typeof text !== "string" || !text) return null
  let cand = text.trim().replace(/<think>[\s\S]*?<\/think>/gi, "").replace(/<reasoning>[\s\S]*?<\/reasoning>/gi, "").trim()
  const fence = cand.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (fence) cand = fence[1].trim()
  else {
    const i = cand.indexOf("{")
    const j = cand.lastIndexOf("}")
    if (i >= 0 && j > i) cand = cand.slice(i, j + 1)
  }
  let obj = null
  try {
    obj = JSON.parse(cand)
  } catch {
    try {
      obj = JSON.parse(jsonrepair(cand))
    } catch {
      return null
    }
  }
  if (!obj || typeof obj !== "object") return null
  if (!/^(approve|needs-attention|real|false-positive)$/.test(String(obj.verdict))) return null
  return obj
}

// A finished review must carry a PARSEABLE verdict object — not just a regex substring.
// A model quoting "verdict":"approve" in prose, or emitting schema-invalid JSON, must NOT
// pass the reask gate (a substring regex previously let both through).
export function hasVerdict(text) {
  return extractVerdictObject(text) !== null
}

export function looksNarrated(text) {
  return !hasVerdict(text)
}

// A "needs-attention" verdict with no findings is a reached verdict, so the
// panel slot still counts as satisfied. This detector is only a pre-acceptance
// quality signal for the bridge retry loop: if budget remains, re-ask the SAME
// provider once for itemized findings. Heuristic + fail-open: a false positive
// only costs one extra retry, never a dropped result.
export function needsAttentionWithoutFindings(text) {
  if (typeof text !== "string") return false
  if (!/"verdict"\s*:\s*"needs-attention"/i.test(text)) return false
  const m = text.match(/"findings"\s*:\s*\[([\s\S]*?)\]/)
  if (!m) return true // verdict present but no findings array at all
  return !/\{/.test(m[1]) // findings array has no object => empty
}

// ── model_params catalog (redteam-only harness contract) ─────────────────────

export const HARNESS_DEFAULT_TEMPERATURE = 0
export const HARNESS_DEFAULT_REASONING_EFFORT = "none"
export const HARNESS_DEFAULT_THINKING_EFFORT = "high"
export const HARNESS_SALVAGE_REASONING_EFFORT = "none"
export const HARNESS_SALVAGE_THINKING_EFFORT = "off"

export function normalizeParamValues(raw) {
  if (raw == null) return null
  if (Array.isArray(raw)) return raw
  if (typeof raw === "object" && Array.isArray(raw.values)) return raw.values
  return null
}

export function mergeModelParamsCatalog(catalogEntry = {}, overlayEntry = {}) {
  return { ...overlayEntry, ...catalogEntry }
}

/**
 * Base URL for GET /v1/models (or /models) discovery.
 *
 * Purpose: Alibaba Code Plan (`alibaba-token-plan`) may chat on `/apps/anthropic` but
 * publishes its model list on the OpenAI-compatible `/compatible-mode/v1` path.
 * Consumer: runner.mjs discoverLive, model-discovery.mjs discoverModels.
 */
export function resolveModelsCatalogBaseUrl(providerId, providerBaseUrl = "") {
  const pid = String(providerId || "")
  const base = String(providerBaseUrl || "").replace(/\/$/, "")
  if (
    pid === "alibaba-token-plan" ||
    /token-plan\.ap-southeast-1\.maas\.aliyuncs\.com\/apps\/anthropic/i.test(base)
  ) {
    return "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
  }
  if (pid === "zai" || pid === "z-ai" || /api\.z\.ai\/api\/anthropic/i.test(base)) {
    return "https://api.z.ai/api/paas/v4"
  }
  if (pid === "google" || pid === "google-genai" || pid === "gemini" || /generativelanguage\.googleapis\.com/i.test(base)) {
    return base || "https://generativelanguage.googleapis.com/v1beta"
  }
  return base
}

/** Build the models-list URL for a provider base (catalog discovery, not chat). */
export function modelsListUrl(catalogBase) {
  const base = String(catalogBase || "").replace(/\/$/, "")
  if (!base) return ""
  if (/\/paas\/v\d+$/i.test(base) || /\/v\d+(?:beta)?$/i.test(base)) return `${base}/models`
  return base.endsWith("/v1") ? `${base}/models` : `${base}/v1/models`
}

export function resolveModelProtocol({ modelCfg = {}, providerType = null } = {}) {
  const fromCatalog = modelCfg.protocol
  if (typeof fromCatalog === "string" && fromCatalog) return fromCatalog
  if (typeof providerType === "string" && providerType) return providerType
  return null
}

/** Apply redteam model_params wire/base_url on top of agent-core ProviderManager output. */
export function applyHarnessProviderOverlay(provider = {}, harnessCfg = {}, providerType = null) {
  const wire = resolveModelProtocol({ modelCfg: harnessCfg, providerType: providerType || provider.type })
  const out = { ...provider }
  if (wire) out.type = wire
  const baseUrl = harnessCfg.base_url ?? harnessCfg.baseUrl
  if (typeof baseUrl === "string" && baseUrl) out.baseUrl = baseUrl
  return out
}

function pickParamValue({ supported, requested, policyDefault }) {
  const values = normalizeParamValues(supported)
  if (!values?.length) return null
  if (requested != null && values.includes(requested)) return requested
  if (policyDefault != null && values.includes(policyDefault)) return policyDefault
  return values[0]
}

export function resolveModelReviewParams({
  modelCfg = {},
  salvage = false,
  env = {},
  modelLabel = null,
  huntPhase = null,
} = {}) {
  const kwargs = {}
  const envTemp = Number(env.REDTEAM_TEMPERATURE)
  const temp = pickParamValue({
    supported: modelCfg.temperature,
    requested: Number.isFinite(envTemp) ? envTemp : null,
    policyDefault: salvage ? null : HARNESS_DEFAULT_TEMPERATURE,
  })
  kwargs.temperature = temp != null ? temp : HARNESS_DEFAULT_TEMPERATURE

  const envReasoning = String(env.REDTEAM_REASONING_EFFORT || env.REDTEAM_NORTH_EFFORT || "").trim().toLowerCase()
  const reasoning = pickParamValue({
    supported: modelCfg.reasoning_effort,
    requested: salvage ? null : (envReasoning || null),
    policyDefault: salvage ? HARNESS_SALVAGE_REASONING_EFFORT : HARNESS_DEFAULT_REASONING_EFFORT,
  })
  if (reasoning != null) kwargs.reasoning_effort = reasoning

  let thinkingEffort = null
  if (modelLabel && isMinimaxM3Model(modelLabel)) {
    const raw = resolveMinimaxM3ThinkingEffort({ env, huntPhase, salvage })
    const supported = normalizeParamValues(modelCfg.thinking_effort)
    thinkingEffort =
      supported?.length && supported.includes(raw)
        ? raw
        : THINKING_EFFORT_VALUES.includes(raw)
          ? raw
          : null
  } else {
    const envThinking = String(env.REDTEAM_THINKING_EFFORT || env.REDTEAM_KIMI_THINKING || "").trim().toLowerCase()
    const thinking = pickParamValue({
      supported: modelCfg.thinking_effort,
      requested: salvage ? null : (envThinking || null),
      policyDefault: salvage ? HARNESS_SALVAGE_THINKING_EFFORT : HARNESS_DEFAULT_THINKING_EFFORT,
    })
    thinkingEffort =
      thinking != null && THINKING_EFFORT_VALUES.includes(String(thinking)) ? String(thinking) : null
  }

  return { kwargs, thinkingEffort }
}

export function modelHasThinkingCapability(modelCfg = {}) {
  const caps = Array.isArray(modelCfg.capabilities) ? modelCfg.capabilities : []
  return caps.some((cap) => /thinking|always_thinking/i.test(String(cap)))
}

export function stripAssistantThinkParts(parts) {
  if (!Array.isArray(parts)) return []
  return parts.filter((part) => part && part.type !== "think")
}

export function reviewProseText({ assistantTexts = [], reasoningTexts = [], submittedVerdict = null } = {}) {
  if (submittedVerdict) return JSON.stringify(submittedVerdict)
  const assistant = assistantTexts.join("\n").trim()
  if (assistant) return assistant
  return reasoningTexts.join("\n").trim()
}

export function reaskEvidenceText({ assistantTexts = [], cap = 24000 } = {}) {
  const prose = assistantTexts.join("\n").trim()
  if (!prose) return ""
  return prose.length > cap ? prose.slice(-cap) : prose
}

export const mergeModelReviewCatalog = mergeModelParamsCatalog

// --all-files planning: expand a file list into `${model}::${file}` job pairs,
// assigning `perFile` lineages per file, rotated through `spread` with a per-file
// offset so the K lineages on one file differ and provider lanes rotate across
// files (direct lanes run parallel to the gated ollama lane). Pure: same inputs ->
// same pairs.
// Hard ceiling so --all-files over a large repo can't explode into thousands of model
// runs (every pair is a real review). perFile is also capped at spread.length — assigning
// more lineages to one file than exist just repeats them, wastefully.
export const MAX_PLAN_JOBS = 2000
export function planJobs(files, spread, perFile = 1) {
  if (!Array.isArray(files) || !Array.isArray(spread) || spread.length === 0) return []
  const k = Math.min(Math.max(1, perFile), spread.length)
  const pairs = []
  for (let fi = 0; fi < files.length && pairs.length < MAX_PLAN_JOBS; fi++) {
    for (let j = 0; j < k && pairs.length < MAX_PLAN_JOBS; j++) {
      pairs.push(`${spread[(fi + fi * k + j) % spread.length]}::${files[fi]}`)
    }
  }
  return pairs
}

// ── scout → heavy bughunt (#10) ──────────────────────────────────────────────
const DEFAULT_SCOUT_MODEL_COUNT = 3
const SCOUT_PREFERENCE_PATTERNS = [
  /minimax[- ]?m3/i,
  /devstral[-_.:]?small[-_.:]?2|devstral[-_.:]?small/i,
  /qwen3[-_.:]?(?:coder[-_.:]?next|next[-_.:]?coder|coder)/i,
  /qwen3[-_.:]?next/i,
  /gpt-oss:?20b|gpt-oss-20b/i,
  /gemma4:?31b|gemma-4-31b/i,
  /gemma(?:3|4).*?(?:4b|12b|31b)|gemma(?:3|4)[:.-]?4b/i,
  /devstral/i,
  /deepseek[-_.:]?v4[-_.:]?flash/i,
  /nemotron[-_.:]?3[-_.:]?nano/i,
  /gpt-oss:?120b/i,
]

function scoutPreferenceRank(model) {
  const rank = SCOUT_PREFERENCE_PATTERNS.findIndex((pattern) => pattern.test(String(model || "")))
  return rank >= 0 ? rank : SCOUT_PREFERENCE_PATTERNS.length
}

function scoutProviderRank(model, opts = {}) {
  const lineage = inferLineage(model)
  const provider = String(model || "").split("/")[0]
  const direct = lineage ? opts.directProviderByLineage?.[lineage] : null
  if (direct && provider === direct) return 0
  const fallback = Array.isArray(opts.providerPriority) && opts.providerPriority.length
    ? opts.providerPriority
    : ["ollama-cloud", "opencode-go", "alibaba-token-plan", "openrouter"]
  const rank = fallback.indexOf(provider)
  return rank >= 0 ? rank + 1 : fallback.length + 1
}

/**
 * Pick a bounded scout set from live discovery.
 *
 * Purpose: bughunt scout must route files cheaply; using every fast model turns
 *          one run into hundreds of duplicate reviews. M3 is the heavy
 *          non-thinking scout slot when available; the remaining slots are
 *          directed code/compile-style scouts from distinct lineages.
 * Consumer: panel.mjs --bughunt.
 */
export function selectScoutModels(models, opts = {}) {
  const count = Math.max(1, Number.isFinite(opts.count) ? Math.floor(opts.count) : DEFAULT_SCOUT_MODEL_COUNT)
  const seen = new Set()
  const uniq = []
  for (const model of models || []) {
    if (typeof model !== "string" || !model || seen.has(model)) continue
    seen.add(model)
    uniq.push(model)
  }
  const ranked = uniq.sort((a, b) => {
    const ar = scoutPreferenceRank(a)
    const br = scoutPreferenceRank(b)
    const al = inferLineage(a) || a
    const bl = inferLineage(b) || b
    const as = String(a)
    const bs = String(b)
    return ar - br || al.localeCompare(bl) || scoutProviderRank(a, opts) - scoutProviderRank(b, opts) || as.length - bs.length || as.localeCompare(bs)
  })
  const selected = []
  const selectedLineages = new Set()
  for (const model of ranked) {
    const lineage = inferLineage(model) || model
    if (selectedLineages.has(lineage)) continue
    selected.push(model)
    selectedLineages.add(lineage)
    if (selected.length >= count) return selected
  }
  for (const model of ranked) {
    if (selected.includes(model)) continue
    selected.push(model)
    if (selected.length >= count) break
  }
  return selected
}

export const REVIEW_LANES = ["scout", "review", "deep-review", "architect", "builder", "verify", "summarize"]

export function classifyReviewLane({ mode = "review", focus = "", command = "" } = {}) {
  const m = String(mode || "review").toLowerCase()
  const f = `${focus || ""} ${command || ""}`.toLowerCase()
  if (m === "decision" || m === "design" || m === "critique" || m === "plan" || /\b(architect|adr|design|plan)\b/.test(f)) return "architect"
  if (m === "verify" || /\b(verify|refute|false.?positive)\b/.test(f)) return "verify"
  if (m === "solve" || /\b(build|implement|builder|fix)\b/.test(f)) return "builder"
  if (m === "harvest" || /\b(summary|summari[sz]e|harvest)\b/.test(f)) return "summarize"
  if (m === "security" || m === "ultrareview" || /\b(deep|security|concurrency|race|auth|authorization|data loss|correctness)\b/.test(f)) return "deep-review"
  if (m === "hunt" || /\b(scout|scan|hotspot|bughunt)\b/.test(f)) return "scout"
  return "review"
}

function benchScore(row = {}) {
  if (Number.isFinite(row.score)) return Number(row.score)
  const verdict = Number(row.verdict_rate ?? row.verdictRate ?? 0)
  const recall = Number(row.recall_at_5 ?? row.recallAt5 ?? row.recall_at_3 ?? row.recallAt3 ?? 0)
  const precision = Number(row.precision ?? row.finding_precision ?? row.findingPrecision ?? 0)
  const seconds = Number(row.median_seconds ?? row.medianSeconds ?? 0)
  const speedPenalty = seconds > 0 ? Math.min(0.2, seconds / 1000) : 0
  return Number((verdict * 0.45 + recall * 0.35 + precision * 0.2 - speedPenalty).toFixed(4))
}

export function normalizeBenchEvidence(raw = {}) {
  const lanes = {}
  const source = raw?.lanes && typeof raw.lanes === "object" ? raw.lanes : {}
  for (const [lane, rows] of Object.entries(source)) {
    if (!REVIEW_LANES.includes(lane) || !Array.isArray(rows)) continue
    lanes[lane] = rows
      .filter((row) => row && typeof row.model === "string" && row.model.length)
      .map((row) => ({
        ...row,
        lane,
        pass: row.pass === true,
        score: benchScore(row),
      }))
      .sort((a, b) => b.score - a.score || String(a.model).localeCompare(String(b.model)))
  }
  return {
    generated_at: typeof raw.generated_at === "string" ? raw.generated_at : null,
    lanes,
  }
}

export function mergeBenchEvidence(existing = {}, update = {}, opts = {}) {
  const previous = opts.reset ? { lanes: {} } : normalizeBenchEvidence(existing)
  const next = normalizeBenchEvidence(update)
  return {
    schema: Number.isFinite(update?.schema) ? update.schema : Number.isFinite(existing?.schema) ? existing.schema : 1,
    generated_at: next.generated_at || previous.generated_at || null,
    source: typeof update?.source === "string" ? update.source : typeof existing?.source === "string" ? existing.source : "merged",
    lanes: {
      ...(previous.lanes || {}),
      ...(next.lanes || {}),
    },
  }
}

export function rankLaneBenchCandidates(models, lane, scoreFn, opts = {}) {
  const limit = Math.max(1, Number.isFinite(opts.limit) ? Math.floor(opts.limit) : 8)
  const scorer = typeof scoreFn === "function" ? scoreFn : () => 0
  const rows = [...(models || [])]
    .map((model) => {
      const lineage = inferLineage(model) || model
      return { model, score: Number(scorer(model, lane) || 0), lineage, providerRank: laneProviderRank(model, lineage, opts) }
    })
    .filter((row) => row.score >= (Number.isFinite(opts.minScore) ? opts.minScore : 0.8))
    .sort(compareLaneCandidateRows)
  const selected = []
  const selectedLineages = new Set()
  for (const row of rows) {
    if (selectedLineages.has(row.lineage)) continue
    selected.push(row)
    selectedLineages.add(row.lineage)
    if (selected.length >= limit) break
  }
  for (const row of rows) {
    if (selected.includes(row)) continue
    selected.push(row)
    if (selected.length >= limit) break
  }
  return selected.map(({ model, score }) => ({ model, score }))
}

function laneProviderRank(model, lineage, opts = {}) {
  const directProviderByLineage = opts.directProviderByLineage && typeof opts.directProviderByLineage === "object" ? opts.directProviderByLineage : {}
  const providerPriority = Array.isArray(opts.providerPriority) ? opts.providerPriority : []
  const slash = String(model || "").indexOf("/")
  const provider = slash >= 0 ? String(model).slice(0, slash) : ""
  if (directProviderByLineage[lineage] === provider) return 0
  const idx = providerPriority.indexOf(provider)
  return idx >= 0 ? idx + 1 : providerPriority.length + 1
}

function compareLaneCandidateRows(a, b) {
  if (a.lineage === b.lineage) return a.providerRank - b.providerRank || b.score - a.score || a.model.localeCompare(b.model)
  return b.score - a.score || a.providerRank - b.providerRank || a.lineage.localeCompare(b.lineage) || a.model.localeCompare(b.model)
}

function hasInSetOrArray(collection, value) {
  if (collection instanceof Set) return collection.has(value)
  if (Array.isArray(collection)) return collection.includes(value)
  return false
}

export function eligibleLaneCandidates({ lane, bench, configured, live, metadata } = {}) {
  const rows = normalizeBenchEvidence(bench).lanes?.[lane] || []
  return rows
    .filter((row) => row.pass === true)
    .filter((row) => hasInSetOrArray(configured, row.model))
    .filter((row) => hasInSetOrArray(live, row.model))
    .filter((row) => hasInSetOrArray(metadata, row.model))
}

export function planLaneRoute(lane, candidates, opts = {}) {
  const rows = [...(candidates || [])]
    .filter((row) => row && row.lane === lane && typeof row.model === "string" && row.model.length)
    .map((row) => {
      const lineage = inferLineage(row.model) || row.model
      return { ...row, lineage, providerRank: laneProviderRank(row.model, lineage, opts), score: Number(row.score || 0) }
    })
    .sort(compareLaneCandidateRows)
  const primary = rows[0]
  if (!primary) return null
  const primaryLineage = inferLineage(primary.model) || primary.model
  const failoverCount = Math.max(1, Number.isFinite(opts.failoverCount) ? Math.floor(opts.failoverCount) : 1)
  const failover = []
  for (const row of rows.slice(1)) {
    const lineage = inferLineage(row.model) || row.model
    if (lineage === primaryLineage) continue
    failover.push(row.model)
    if (failover.length >= failoverCount) break
  }
  if (failover.length < failoverCount) return null
  return {
    lane,
    primary: primary.model,
    failover,
    confidence: Number(primary.score || 0),
    reason: "bench-backed lane route with distinct failover",
  }
}

function shortPlannerReason(value) {
  return String(value || "").replace(/\s+/g, " ").trim().slice(0, 240)
}

export function buildLanePlannerPrompt({ lane, candidates, context = "" } = {}) {
  const rows = [...(candidates || [])]
    .filter((row) => row && row.lane === lane && typeof row.model === "string" && row.model.length)
    .map((row) => ({
      model: row.model,
      lane: row.lane,
      lineage: inferLineage(row.model) || row.model,
      score: Number(row.score || 0),
      median_seconds: row.median_seconds ?? row.medianSeconds ?? null,
      notes: row.notes || row.note || "",
    }))
  return [
    "You are selecting a redteam model route from pre-validated candidates.",
    "JSON only. Do not invent models. Choose primary and at least one failover from candidates.",
    "The failover must be a distinct lineage from primary.",
    JSON.stringify({ lane, context: String(context || ""), candidates: rows }, null, 2),
    'Return: {"primary":"provider/model","failover":["provider/model"],"reason":"one short sentence"}',
  ].join("\n\n")
}

export function parseLanePlannerChoice(input) {
  if (!input) return null
  const raw = typeof input === "string" ? input.trim() : input
  let obj = raw
  if (typeof raw === "string") {
    const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)\s*```/i)
    const text = fenced ? fenced[1] : raw
    try {
      obj = JSON.parse(text)
    } catch {
      return null
    }
  }
  if (!obj || typeof obj !== "object") return null
  const primary = typeof obj.primary === "string" ? obj.primary.trim() : ""
  const failover = Array.isArray(obj.failover)
    ? obj.failover.map((item) => String(item || "").trim()).filter(Boolean)
    : typeof obj.failover === "string" && obj.failover.trim()
      ? [obj.failover.trim()]
      : []
  if (!primary || failover.length === 0) return null
  return { primary, failover, reason: shortPlannerReason(obj.reason) }
}

function lanePlannerRejection(lane, candidates, choice, failoverCount, opts = {}) {
  if (!choice) return "planner returned no parseable route"
  const eligible = new Map(
    [...(candidates || [])]
      .filter((row) => row && row.lane === lane && typeof row.model === "string" && row.model.length)
      .map((row) => [row.model, row]),
  )
  const primary = eligible.get(choice.primary)
  if (!primary) return "primary is not an eligible candidate"
  const primaryLineage = inferLineage(primary.model) || primary.model
  const failovers = []
  for (const model of choice.failover || []) {
    const row = eligible.get(model)
    if (!row) return "failover is not an eligible candidate"
    if (row.model === primary.model) return "failover must differ from primary"
    const lineage = inferLineage(row.model) || row.model
    if (lineage === primaryLineage) return "failover must use a distinct lineage"
    if (!failovers.includes(row.model)) failovers.push(row.model)
  }
  if (failovers.length < failoverCount) return "planner did not provide enough distinct failovers"
  const ordered = [...eligible.values()]
    .map((row) => {
      const lineage = inferLineage(row.model) || row.model
      return { ...row, lineage, providerRank: laneProviderRank(row.model, lineage, opts), score: Number(row.score || 0) }
    })
    .sort(compareLaneCandidateRows)
  const bestByLineage = new Map()
  for (const row of ordered) {
    if (!bestByLineage.has(row.lineage)) bestByLineage.set(row.lineage, row.model)
  }
  for (const model of [choice.primary, ...failovers]) {
    const row = eligible.get(model)
    const lineage = inferLineage(row.model) || row.model
    if (bestByLineage.get(lineage) !== row.model) return "planner selected a fallback provider while a higher-priority provider was eligible"
  }
  return ""
}

export function planLaneRouteWithPlanner(lane, candidates, plannerChoice, opts = {}) {
  const failoverCount = Math.max(1, Number.isFinite(opts.failoverCount) ? Math.floor(opts.failoverCount) : 1)
  const fallback = planLaneRoute(lane, candidates, { ...opts, failoverCount })
  const choice = parseLanePlannerChoice(plannerChoice)
  const rejection = lanePlannerRejection(lane, candidates, choice, failoverCount, opts)
  if (rejection) {
    return fallback ? { ...fallback, planner_rejected: rejection } : null
  }
  const byModel = new Map((candidates || []).map((row) => [row.model, row]))
  const primary = byModel.get(choice.primary)
  return {
    lane,
    primary: primary.model,
    failover: choice.failover.slice(0, failoverCount),
    confidence: Number(primary.score || 0),
    reason: "planner-selected bench-backed lane route",
    planner_reason: choice.reason,
  }
}

/**
 * Build bounded scout context for a selected heavy-review file.
 *
 * Purpose: advisory scouts should alert the later heavy reviewer to concrete
 *          gate/pattern failures without making the scout verdict authoritative.
 * Consumer: panel.mjs --bughunt heavy phase focus text.
 */
export function buildScoutHandoff(scoutRows, file, opts = {}) {
  const limit = Math.max(1, Number.isFinite(opts.limit) ? Math.floor(opts.limit) : 5)
  const rows = []
  for (const row of scoutRows || []) {
    if (row?.file !== file) continue
    const model = row.model ? String(row.model) : "unknown-scout"
    for (const finding of row.findings || []) {
      const title = String(finding?.title || finding?.summary || "").trim()
      if (!title) continue
      const severity = String(finding?.severity || "unknown").trim()
      const line = finding?.line != null ? ` line ${finding.line}` : ""
      rows.push(`- ${model}: ${severity}${line}: ${title}`)
      if (rows.length >= limit) break
    }
    if (rows.length >= limit) break
  }
  if (!rows.length) return ""
  return `Scout handoff for this file (advisory; verify before trusting):\n${rows.join("\n")}`
}

// SCOUT phase: cheap scan-tier models review the candidate files; each (file,model)
// yields a severity-weighted risk score. scoutScores collapses those to a per-file
// MEAN score, sorted high→low. The premise experiment (scout-premise.mjs) showed
// scan-tier scores reliably surface the top hotspots (ρ≈0.78, recall@3=3/3) even
// though they go flat (0) on the cold tail — which is fine: the score is ADVISORY
// STEERING for the heavy phase, never a verdict. Pure.
export function scoutScores(results) {
  const byFile = new Map()
  for (const r of results || []) {
    if (!r || !r.file) continue
    if (!byFile.has(r.file)) byFile.set(r.file, [])
    byFile.get(r.file).push(Number(r.score) || 0)
  }
  const rows = [...byFile.entries()].map(([file, ss]) => ({ file, score: ss.reduce((s, x) => s + x, 0) / ss.length }))
  rows.sort((a, b) => b.score - a.score || a.file.localeCompare(b.file))
  return rows
}

// Pick which files the HEAVY phase deep-reviews: the top `heavyK` scout HOTSPOTS
// (score > 0 — never pad hotspots with cold files), then `baselineTail` coverage
// files drawn from the zero-scored tail so a scout FALSE-NEGATIVE (a real hotspot the
// cheap models missed) still has a path to deep review. With fillToK, top up the heavy
// budget from the ranked tail when there are fewer hotspots than heavyK. Pure +
// deterministic (caller pre-shuffles `scored` if it wants run-to-run variety in the
// tail). Returns { hotspots, baseline, selected } (selected = hotspots → fill → baseline,
// deduped, order-preserving).
export function selectHotspots(scored, opts = {}) {
  const heavyK = Math.max(1, opts.heavyK ?? 5)
  const baselineTail = Math.max(0, opts.baselineTail ?? 2)
  const ranked = [...(scored || [])].sort((a, b) => (b.score - a.score) || String(a.file).localeCompare(String(b.file)))
  const hotspots = ranked.filter((r) => (Number(r.score) || 0) > 0).slice(0, heavyK).map((r) => r.file)
  const rest = ranked.map((r) => r.file).filter((f) => !hotspots.includes(f))
  const fill = opts.fillToK ? rest.slice(0, Math.max(0, heavyK - hotspots.length)) : []
  const tailPool = rest.filter((f) => !fill.includes(f))
  const baseline = tailPool.slice(0, baselineTail)
  const selected = [...new Set([...hotspots, ...fill, ...baseline])]
  return { hotspots, baseline, selected }
}

// Lens → reviewer routing for the ultrareview pipeline. Replaces the old arbitrary
// `fleet[i % fleet.length]` (which could seat a single weak/small model as the SOLE
// reviewer of a hard lens once scan-tier models enter the roster). Rules, all pure:
//   - Each lens gets up to `perLens` reviewers, DISTINCT lineage within the lens
//     (mirrors the panel's anti-blindness: never two of one family on one remit).
//   - A `deep`-tier lens (semantic: security/concurrency/correctness/api-contract)
//     is staffed deep-first; scan models are used only as a last resort if no deep
//     model is left (graceful degradation — a lens is never wholly unreviewed when
//     ANY model exists), never as a preferred reviewer.
//   - A `scan`-eligible lens (broad antipattern sweep) always gets ONE deep ANCHOR
//     first, then fills with scan models (the cheap-breadth layer the operator asked
//     for) before falling back to more deep. Scan models are first-class ONLY here.
//   - Cross-lens ROTATION: the pool is consumed from a per-lens offset so consecutive
//     lenses don't all anchor on the same top model.
// Tier classifies the LENS by remit difficulty (task classification the operator
// endorsed for antipattern sweeps) — NOT model competence, which we never guess.
// roster items: { id, lineage, tier:"deep"|"scan" }. Returns [{ lens, model }].
function pickDistinct(pool, count, offset, taken) {
  const out = []
  const n = pool.length
  for (let s = 0; s < n && out.length < count; s++) {
    const e = pool[(offset + s) % n]
    if (taken.has(e.lineage)) continue
    taken.add(e.lineage)
    out.push(e)
  }
  return out
}
export function planLensRoutes(lenses, roster, opts = {}) {
  const perLens = Math.max(1, opts.perLens ?? 2)
  const deep = (roster || []).filter((r) => r && r.tier === "deep")
  const scan = (roster || []).filter((r) => r && r.tier === "scan")
  const routes = []
  ;(lenses || []).forEach((lens, li) => {
    const taken = new Set() // lineages already seated on THIS lens
    const chosen = []
    if (lens.tier === "scan") {
      // deep anchor first, then scan breadth, then more deep as fill
      chosen.push(...pickDistinct(deep, 1, li, taken))
      chosen.push(...pickDistinct(scan, perLens - chosen.length, li, taken))
      chosen.push(...pickDistinct(deep, perLens - chosen.length, li + 1, taken))
    } else {
      // deep lens: deep-first; scan only as last-resort so the lens is never empty
      chosen.push(...pickDistinct(deep, perLens, li, taken))
      chosen.push(...pickDistinct(scan, perLens - chosen.length, li, taken))
    }
    for (const e of chosen) routes.push({ lens: lens.key, model: e.id })
  })
  return routes
}

// ultrareview Dedupe phase: collapse findings that point at the same issue (same
// file + nearby line) into one, agreement-weighted by how many DISTINCT lineages
// raised it (independent multi-lineage agreement = higher confidence, the same
// signal ultrareview surfaces), then rank by severity then agreement. Pure.
export function synthesizeUltrareview(findings) {
  const sevRank = { critical: 0, high: 1, medium: 2, low: 3 }
  const lineOf = (f) => Number(f.line_start ?? f.line) || 0
  const groups = new Map()
  for (const f of findings || []) {
    if (!f) continue
    const key = `${f.file || "?"}:${Math.floor(lineOf(f) / 8)}` // bucket ~8 lines
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key).push(f)
  }
  const issues = [...groups.values()].map((g) => {
    const lenses = [...new Set(g.map((x) => x.lens).filter(Boolean))]
    const lineages = [...new Set(g.flatMap((x) => x.lineages || (x.by ? [x.by] : [])))]
    const rep = g.slice().sort((a, b) => (sevRank[a.severity] ?? 9) - (sevRank[b.severity] ?? 9))[0]
    return {
      severity: rep.severity,
      title: rep.title,
      file: rep.file,
      line: lineOf(rep) || null,
      body: rep.body,
      recommendation: rep.recommendation,
      lenses,
      lineages,
      agreement: lineages.length,
    }
  })
  issues.sort((a, b) => (sevRank[a.severity] ?? 9) - (sevRank[b.severity] ?? 9) || b.agreement - a.agreement)
  return issues
}

// --all-files aggregation: group per-file review results into a matrix + findings.
// `approve` only if every non-error lineage approved; `all-error` if none produced
// a verdict; otherwise `needs-attention`.
/**
 * Extract likely code identifiers (CamelCase, snake_case, ENV_VAR, dotted paths)
 * from a free-form verdict summary. Used by the hallucination gate.
 *
 * Purpose: catch models that assert "function X does Y" when X does not exist in the repo.
 * Consumer: approve-gate in panel.mjs and runner post-processing.
 */
export function extractPotentialSymbols(text) {
  if (!text) return [];
  const src = String(text);
  const out = new Set();
  // mixedCase / CamelCase / PascalCase (any identifier containing at least one uppercase after first char)
  for (const m of src.matchAll(/\b([a-zA-Z_][a-zA-Z0-9_]*[A-Z][a-zA-Z0-9_]*)\b/g)) out.add(m[0]);
  // snake_case or SCREAMING_SNAKE
  for (const m of src.matchAll(/\b([A-Z0-9_]{3,})\b/g)) out.add(m[0]);
  // private/test globals such as __SF_SELF_FEEDBACK_CORPUS_CACHE
  for (const m of src.matchAll(/(^|[^A-Za-z0-9])(__[A-Za-z0-9_]{3,})\b/g)) out.add(m[2]);
  // dotted paths like foo.bar.baz (common in JS/TS)
  for (const m of src.matchAll(/\b([a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_.]*)\b/g)) out.add(m[0]);
  // env var style SF_FOO, DB_*, etc.
  for (const m of src.matchAll(/\b([A-Z][A-Z0-9_]{2,})\b/g)) out.add(m[0]);
  return [...out].filter((s) => s.length >= 3);
}

function sortJsonValue(value) {
  if (Array.isArray(value)) return value.map(sortJsonValue)
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortJsonValue(value[key])]))
  }
  return value
}

/**
 * Stable cache key for deterministic read-only inspection tool calls.
 *
 * Purpose: repeated Read/Grep/Glob calls across agent steps should reuse the same result.
 * Consumer: runner.mjs prepare/finalize tool hooks.
 */
export function stableToolCacheKey(name, args) {
  return `${String(name || "")}:${JSON.stringify(sortJsonValue(args ?? null))}`
}

/**
 * True for tools whose outputs are deterministic enough to reuse inside one review attempt.
 *
 * Purpose: avoid caching network/MCP/verdict side effects while still eliminating repeated file inspection.
 * Consumer: runner.mjs tool-result cache.
 */
export function isCacheableReviewTool(name) {
  return name === "Read" || name === "Grep" || name === "Glob"
}

/**
 * Build a compact evidence preface from git metadata before the model starts exploring.
 *
 * Purpose: give every reviewer the changed-file map so first calls can prove claims instead of rediscovering the diff.
 * Consumer: runner.mjs prompt construction.
 */
export function buildReviewEvidencePack({ repoRoot, targetLabel, inputKind, shortstat = "", nameStatus = "", repoMapText = "", repoMapMaxChars = 12000 } = {}) {
  const files = String(nameStatus || "")
    .trim()
    .split(/\r?\n/)
    .filter(Boolean)
    .slice(0, 80)
    .map((line) => line.replace(/\t/g, " "))
  const lines = [
    "<review_evidence_pack>",
    `repo: ${repoRoot || "(unknown)"}`,
    `target: ${targetLabel || "(unknown)"}`,
    `kind: ${inputKind || "(unknown)"}`,
  ]
  if (String(shortstat || "").trim()) lines.push(`shortstat: ${String(shortstat).trim()}`)
  if (files.length) {
    lines.push("changed_files:")
    for (const file of files) lines.push(`- ${file}`)
  }
  const repoMap = String(repoMapText || "").trim()
  if (repoMap) {
    lines.push("repo_map_excerpt:")
    lines.push(repoMap.slice(0, repoMapMaxChars))
  }
  lines.push("</review_evidence_pack>")
  return lines.join("\n")
}

/**
 * Non-redteam reviews should not spend budget inspecting this harness's own verdict tools.
 *
 * Purpose: prevent models from confusing the redteam runner contract with the target repository.
 * Consumer: runner.mjs prompt construction.
 */
export function shouldWarnAboutHarnessInternals(repoRoot) {
  return !/\/\.claude\/redteam(?:\/|$)/.test(String(repoRoot || ""))
}

export function aggregateAllFiles(results) {
  const byFile = {}
  for (const r of results || []) (byFile[r.file] ??= []).push(r)
  return {
    mode: "all-files",
    reviewed: (results || []).length,
    files: Object.keys(byFile).sort().map((file) => {
      const rs = byFile[file]
      const ok = rs.filter((r) => r.verdict && r.verdict !== "error")
      return {
        file,
        status: ok.length === 0 ? "all-error" : ok.every((r) => r.verdict === "approve") ? "approve" : "needs-attention",
        lineages: rs.map((r) => ({ model: r.model, verdict: r.verdict, findings: (r.findings || []).length, ...(r.schema_warning ? { schema_warning: r.schema_warning } : {}) })),
        findings: rs.flatMap((r) => (r.findings || []).map((x) => ({ severity: x.severity, title: x.title, line: x.line_start, recommendation: x.recommendation, by: r.model }))),
      }
    }),
  }
}
