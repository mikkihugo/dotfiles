/**
 * reputation.mjs — lineage reputation tracking for false-approve de-weighting.
 *
 * Purpose: reduce selection probability of lineages that repeatedly emit
 * hallucinated "approve" verdicts (assert code/behaviour that does not exist).
 *
 * Storage: JSON file at $REDTEAM_REPUTATION_FILE or ~/.redteam/reputation.json
 * Schema:
 *   {
 *     "<lineage>": { false_approves: number, total_approves: number, last_updated: iso }
 *   }
 *
 * The module is a pure no-op when REDTEAM_REPUTATION !== "1".
 * It is completely general — works for any repo / any redteam user.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { homedir } from "node:os"

const DEFAULT_PATH = join(homedir(), ".redteam", "reputation.json")

function repoPath() {
  return process.env.REDTEAM_REPUTATION_FILE || DEFAULT_PATH
}

function enabled() {
  return process.env.REDTEAM_REPUTATION === "1"
}

function load() {
  if (!enabled()) return {}
  const p = repoPath()
  try {
    if (!existsSync(p)) return {}
    return JSON.parse(readFileSync(p, "utf8"))
  } catch {
    return {}
  }
}

function save(data) {
  if (!enabled()) return
  const p = repoPath()
  try {
    mkdirSync(dirname(p), { recursive: true })
    writeFileSync(p, JSON.stringify(data, null, 2))
  } catch {
    // best-effort; never throw on reputation write failure
  }
}

/**
 * Record that a lineage produced an approve verdict (and optionally whether it was later refuted).
 */
export function recordApprove(lineage, wasFalse = false, meta = {}) {
  if (!enabled() || !lineage) return
  const data = load()
  data[lineage] ??= { false_approves: 0, total_approves: 0, events: [] }
  data[lineage].total_approves = (data[lineage].total_approves || 0) + 1
  if (wasFalse) {
    data[lineage].false_approves = (data[lineage].false_approves || 0) + 1
  }
  data[lineage].last_updated = new Date().toISOString()

  // Store lightweight event for later analysis (category, latency, tokens, provider)
  if (Object.keys(meta).length) {
    data[lineage].events = data[lineage].events || []
    data[lineage].events.push({
      ts: data[lineage].last_updated,
      wasFalse,
      ...meta,
    })
    // Keep only the last 50 events per lineage to bound growth
    if (data[lineage].events.length > 50) data[lineage].events.shift()
  }

  save(data)
}

/**
 * Return a weight multiplier for a lineage (lower = less likely to be picked).
 * Base weight = 1.0. Every 10% false-approve rate adds a 0.2 penalty (down to 0.1 min).
 */
export function weightForLineage(lineage) {
  if (!enabled() || !lineage) return 1.0
  const data = load()
  const rec = data[lineage]
  if (!rec || !rec.total_approves) return 1.0
  const rate = (rec.false_approves || 0) / rec.total_approves
  const penalty = Math.floor(rate * 10) * 0.2
  return Math.max(0.1, 1.0 - penalty)
}

/**
 * Given an array of model ids, return a new array with reputation-adjusted
 * selection weights attached (for weighted random sampling).
 * Each entry becomes { model, weight }.
 */
export function adjustSelectionWeights(models, lineageOf = (m) => m.split("/")[0]) {
  if (!enabled()) return models.map((m) => ({ model: m, weight: 1.0 }))
  return models.map((m) => {
    const lin = lineageOf(m) || m
    return { model: m, weight: weightForLineage(lin) }
  })
}

/**
 * Pick one model using the adjusted weights (roulette wheel).
 */
export function pickWeighted(modelsWithWeights) {
  const total = modelsWithWeights.reduce((s, x) => s + x.weight, 0)
  if (total <= 0) return modelsWithWeights[0]?.model
  let r = Math.random() * total
  for (const entry of modelsWithWeights) {
    r -= entry.weight
    if (r <= 0) return entry.model
  }
  return modelsWithWeights.at(-1).model
}

export { load as loadReputation, save as saveReputation }