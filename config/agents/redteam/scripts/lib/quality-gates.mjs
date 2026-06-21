/**
 * quality-gates.mjs — reusable hallucination detection + reputation recording.
 *
 * Purpose: central home for the two cross-cutting quality mechanisms so they
 * are not duplicated across normal panel, ultrareview, and bughunt paths.
 *
 * This follows the Codex pattern: quality/result handling lives in its own
 * module (like codex-result-handling skill), not inlined in every dispatch path.
 */

import { spawnSync } from "node:child_process"
import { extractPotentialSymbols } from "../chain-logic.mjs"
import { recordApprove } from "../reputation.mjs"

let rgAvailable = null

function hasRipgrep() {
  if (rgAvailable !== null) return rgAvailable
  try {
    const probe = spawnSync("rg", ["--version"], { encoding: "utf8" })
    rgAvailable = probe.status === 0
  } catch {
    rgAvailable = false
  }
  return rgAvailable
}

/**
 * Return symbols from model prose that are absent from the repo (opt-in gate).
 *
 * Purpose: hallucination detection uses subprocess I/O — lives here, not chain-logic.
 * Consumer: applyHallucinationGate, checkApproveSummaryForHallucination.
 */
export function findMissingSymbols(symbols, repoRoot, env = process.env) {
  if (env.REDTEAM_HALLUCINATION_GATE === "0") return []
  if (!symbols?.length || !repoRoot) return []
  if (!hasRipgrep()) return []
  const root = String(repoRoot)
  const missing = []
  for (const sym of symbols) {
    try {
      const res = spawnSync("rg", ["--quiet", "--fixed-strings", "--", sym, root], { encoding: "utf8" })
      if (res.status !== 0) missing.push(sym)
    } catch {
      missing.push(sym)
    }
  }
  return missing
}

/**
 * Run hallucination gates on per-lineage verdict rows.
 *
 * Purpose: shared path for initial draw and backfill replacements.
 * Consumer: panel.mjs.
 */
export function gateVerdictRows(rows, { repoRoot, record = true, meta = {} } = {}) {
  const gated = applyHallucinationGate(rows, { repoRoot, record, meta })
  for (const v of gated) {
    checkApproveSummaryForHallucination(v, v.model, repoRoot, record, meta)
  }
  return gated
}

/**
 * Apply hallucination gate to an array of findings (or raw results).
 *
 * Each finding's prose (title + body + recommendation) is scanned for symbols.
 * If REDTEAM_HALLUCINATION_GATE=1 and any asserted symbols are missing from
 * the repo, the finding is annotated and the lineage is recorded with a
 * false-approve penalty.
 *
 * @param {Array} items - findings or {findings: [...], model} objects
 * @param {{repoRoot: string, record?: boolean}} opts
 * @returns {Array} gated items (same shape, possibly annotated)
 */
export function applyHallucinationGate(items, { repoRoot, record = true, meta = {} } = {}) {
  if (process.env.REDTEAM_HALLUCINATION_GATE === "0" || !items?.length) {
    return items
  }

  return items.map((item) => {
    const itemMeta = { ...meta, model: item.model || meta.model }
    if (item.findings) {
      const gatedFindings = (item.findings || []).map((f) => gateOneFinding(f, item.model, repoRoot, record, itemMeta))
      return { ...item, findings: gatedFindings }
    }
    return gateOneFinding(item, item.by || item.model, repoRoot, record, itemMeta)
  })
}

function gateOneFinding(finding, model, repoRoot, record, meta = {}) {
  const prose = `${finding.title || ""} ${finding.body || ""} ${finding.recommendation || ""}`
  const symbols = extractPotentialSymbols(prose)
  if (!symbols.length) return finding

  const missing = findMissingSymbols(symbols, repoRoot)
  if (!missing.length) return finding

  if (record && model) {
    const lineage = model.split("/")[0]
    recordApprove(lineage, true, {
      category: meta.errorCategory || "hallucination",
      latencyMs: meta.latencyMs,
      tokens: meta.tokens,
      provider: meta.provider,
    })
  }

  return {
    ...finding,
    title: finding.title + " [HALLUCINATED SYMBOLS]",
    body: (finding.body || "") + `\n[auto] Hallucination gate: asserted symbols not found: ${missing.join(", ")}`,
    _hallucination: { asserted: symbols, missing },
  }
}

/**
 * Scan an "approve" verdict's summary/prose for hallucinated symbols and
 * record a false-approve if any are missing. Used for reputation weighting
 * even when the verdict itself is not downgraded.
 */
export function checkApproveSummaryForHallucination(verdict, model, repoRoot, record = true, meta = {}) {
  if (!verdict || verdict.verdict !== "approve") return
  const prose = `${verdict.summary || ""} ${(verdict.findings || []).map(f => f.body || "").join(" ")}`
  const symbols = extractPotentialSymbols(prose)
  if (!symbols.length) return
  const missing = findMissingSymbols(symbols, repoRoot)
  if (!missing.length) return
  if (record) {
    const lineage = (model || verdict.model || "").split("/")[0]
    recordApprove(lineage, true, {
      category: meta.errorCategory || "approve-summary",
      latencyMs: meta.latencyMs,
      tokens: meta.tokens,
      provider: meta.provider,
    })
  }
}

/**
 * Record reputation outcomes from a verification pass.
 *
 * @param {Array} findings - gated findings (may contain _hallucination)
 * @param {Array} checks - corresponding verify results
 */
export function recordReputationFromVerification(findings, checks, meta = {}) {
  if (process.env.REDTEAM_REPUTATION !== "1" || !checks?.length) return

  const byLineage = {}
  findings.forEach((f, i) => {
    const model = f.by || (f._verify && f._verify.verifier) || ""
    const lin = model.split("/")[0]
    if (!lin) return
    byLineage[lin] ??= { total: 0, bad: 0 }
    byLineage[lin].total++
    const check = checks[i]
    if (check?.verdict === "false-positive" || f._hallucination) {
      byLineage[lin].bad++
    }
  })

  Object.entries(byLineage).forEach(([lin, stats]) => {
    const falseRate = stats.bad / stats.total
    recordApprove(lin, falseRate > 0.3, {
      category: meta.errorCategory || "verification",
      latencyMs: meta.latencyMs,
      tokens: meta.tokens,
      provider: meta.provider,
    })
  })
}

/** Known-broken providers that consistently fail tool schema validation. */
const KNOWN_BROKEN_PROVIDERS = new Set(["ollama-cloud/mistral-large-3"])

/**
 * Post-parse validation + hard-cap detection.
 * Returns a sanitized verdict object. If the raw output indicates a hard cap
 * or missing required schema fields, the verdict is forced to "error" with a
 * clear synthetic finding so it does not pollute aggregates.
 */
export function verifySchemaAndHardCap(rawOut, model) {
  const provider = model.split("/")[0]
  if (KNOWN_BROKEN_PROVIDERS.has(provider) || /hard.?cap|hardcap/i.test(rawOut)) {
    return {
      verdict: "error",
      model,
      findings: [{ severity: "high", title: "Provider hard-cap or schema failure", body: "Lineage skipped due to known tool-schema or timeout failure.", recommendation: "Remove from roster or fix provider integration.", confidence: 1 }],
      next_steps: [],
      _auto: "hard-cap-or-broken-provider",
    }
  }

  let v
  try {
    v = JSON.parse(rawOut.trim().split("\n").pop())
  } catch {
    return { verdict: "error", model, findings: [], next_steps: [], _auto: "json-parse-failed" }
  }

  // Minimal schema check for review verdicts
  if (v.verdict && !["approve", "needs-attention", "error"].includes(v.verdict)) {
    v.verdict = "error"
    v._auto = "invalid-verdict-value"
  }
  if (v.verdict === "approve" || v.verdict === "needs-attention") {
    if (!Array.isArray(v.findings)) v.findings = []
    // confidence is required on findings in the review schema
    const missing = (v.findings || []).some(f => typeof f.confidence !== "number")
    if (missing && !v.schema_warning) {
      v.verdict = "error"
      v.findings = []
      v._auto = "schema-missing-confidence"
      v.summary = v.summary || "Review findings missing required confidence field"
      recordApprove(model.split("/")[0], true)
    }
  }
  return v
}
