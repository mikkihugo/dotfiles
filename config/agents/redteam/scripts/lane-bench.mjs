#!/usr/bin/env node
import { spawn } from "node:child_process"
import { createRequire } from "node:module"
import { existsSync, readFileSync, writeFileSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { classifyReviewLane, mergeBenchEvidence, normalizeBenchEvidence, rankLaneBenchCandidates, REVIEW_LANES } from "./chain-logic.mjs"
import { discoverModels, getDeclaredModels, inferLineage } from "./model-discovery.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(HERE, "..")
const OUT = join(ROOT, "model-bench.json")
const RUNNER = join(HERE, "runner.mjs")
const require = createRequire(import.meta.url)
const MODELS_JSON = require("../models.json")

function flag(name, def = null) {
  const i = process.argv.lastIndexOf(name)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def
}
function has(name) {
  return process.argv.includes(name)
}

const LANE_FOCUS = {
  scout: "quick scout: route smoke for broad hotspot discovery",
  review: "normal adversarial code review route smoke",
  "deep-review": "deep semantic/security/concurrency review route smoke",
  architect: "architecture, ADR, plan, and design critique route smoke",
  builder: "implementation-agent route smoke",
  verify: "finding verification/refutation route smoke",
  summarize: "summarization and harvest route smoke",
}

const LANE_MODE = {
  scout: "smoke",
  review: "smoke",
  "deep-review": "smoke",
  architect: "smoke",
  builder: "smoke",
  verify: "smoke",
  summarize: "smoke",
}

function laneScore(model, lane) {
  const m = String(model || "").toLowerCase()
  const lineage = inferLineage(model)
  if (lane === "scout") {
    if (/mimo-v2\.5$/.test(m)) return 0.93
    if (/glm-4\.7-flashx|glm-4\.7-flash/.test(m)) return 0.9
    if (/devstral-small|qwen3-coder-next|gpt-oss:?20b|gemma4:?31b/.test(m)) return 0.84
  }
  if (lane === "architect") {
    if (/minimax.*m3/.test(m)) return 0.94
    if (/mimo-v2\.5-pro|grok-4\.3|glm-5\.2|kimi-k2\.7-code/.test(m)) return 0.9
  }
  if (lane === "deep-review") {
    if (/mimo-v2\.5-pro|glm-5\.2|minimax.*m3|kimi-k2\.7-code/.test(m)) return 0.92
  }
  if (lane === "builder") {
    if (/kimi-for-coding|kimi-k2\.7-code|qwen3.*coder/.test(m)) return 0.92
    if (/mimo-v2\.5-pro|minimax.*m3|glm-5\.1|deepseek-v4-pro/.test(m)) return 0.84
  }
  if (lane === "verify") {
    if (/gemini|google|gpt-oss|qwen3.*coder/.test(m)) return 0.9
    if (/devstral-small|gemma4:?31b|deepseek-v4-flash|mimo-v2\.5/.test(m)) return 0.84
  }
  if (lane === "summarize") {
    if (/gemini.*flash|gpt-oss:?20b|gemma|glm-4\.7-flash/.test(m)) return 0.86
    if (/qwen3-coder-next|devstral-small|mimo-v2\.5|deepseek-v4-flash/.test(m)) return 0.82
  }
  if (lane === "review") {
    if (/minimax.*m3|mimo-v2\.5-pro|qwen3.*coder|kimi-for-coding/.test(m)) return 0.9
  }
  return lineage ? 0.55 : 0
}

function candidateRows(models, lanes) {
  const rows = {}
  for (const lane of lanes) {
    rows[lane] = rankLaneBenchCandidates(models, lane, laneScore, {
      limit: 8,
      directProviderByLineage: MODELS_JSON.direct_provider_by_lineage || {},
      providerPriority: MODELS_JSON.provider_priority || [],
    })
  }
  return rows
}

function runOne(model, lane, opts = {}) {
  const args = [
    RUNNER,
    model,
    "--model",
    model,
    "--mode",
    LANE_MODE[lane] || "smoke",
    "--repo-root",
    ROOT,
    "--text",
    `Lane bench for ${lane}: ${LANE_FOCUS[lane] || lane}.`,
    "--target",
    `lane:${lane}`,
    "--focus",
    LANE_FOCUS[lane] || lane,
    "--no-deepwiki",
    "--timeout",
    String(opts.timeoutMs || 180000),
  ]
  const started = Date.now()
  return new Promise((resolve) => {
    const p = spawn("node", args, { stdio: ["ignore", "pipe", "pipe"] })
    let stdout = ""
    let stderr = ""
    p.stdout.on("data", (d) => { stdout += d })
    p.stderr.on("data", (d) => { stderr += d })
    p.on("close", (code) => {
      let verdict = null
      try { verdict = JSON.parse(stdout.trim().split("\n").pop()) } catch {}
      const ok = code === 0 && verdict && verdict.verdict !== "error" && !/^Lineage review failed:/.test(String(verdict.summary || ""))
      resolve({
        model,
        pass: ok,
        verdict_rate: ok ? 1 : 0,
        median_seconds: Number(((Date.now() - started) / 1000).toFixed(2)),
        findings: Array.isArray(verdict?.findings) ? verdict.findings.length : 0,
        error: ok ? undefined : String(verdict?.summary || stderr || `exit ${code}`).slice(0, 300),
      })
    })
    p.on("error", (err) => {
      resolve({ model, pass: false, verdict_rate: 0, median_seconds: Number(((Date.now() - started) / 1000).toFixed(2)), error: err.message })
    })
  })
}

async function main() {
  if (has("--help") || has("-h")) {
    process.stdout.write(
      "Usage: lane-bench.mjs [--lanes scout,review,architect] [--dry-run] [--run] [--write]\n" +
      "  --dry-run  plan candidates without calling models (default unless --run)\n" +
      "  --run      call exact models through runner smoke mode\n" +
      "  --write    merge lane results into model-bench.json\n" +
      "  --reset    with --write, replace model-bench.json instead of merging\n",
    )
    return
  }
  const lanes = (flag("--lanes", REVIEW_LANES.join(",")) || "")
    .split(",")
    .map((s) => classifyReviewLane({ mode: s.trim(), focus: s.trim() }))
    .filter((lane, idx, arr) => REVIEW_LANES.includes(lane) && arr.indexOf(lane) === idx)
  const run = has("--run")
  const write = has("--write")
  const reset = has("--reset")
  const discovered = await discoverModels({ cachePath: null })
  const configured = new Set(getDeclaredModels())
  const available = discovered.map((r) => r.id).filter((id) => configured.has(id))
  const planned = candidateRows(available, lanes)
  const evidence = {
    schema: 1,
    generated_at: new Date().toISOString(),
    source: run ? "real-smoke" : "dry-run-plan",
    lanes: {},
  }
  for (const lane of lanes) {
    const rows = planned[lane] || []
    if (!run) {
      evidence.lanes[lane] = rows.map((r) => ({
        model: r.model,
        pass: false,
        score: r.score,
        verdict_rate: 0,
        median_seconds: 0,
        note: "dry-run candidate only; run with --run --write to promote",
      }))
      continue
    }
    const out = []
    for (const row of rows) {
      process.stderr.write(`bench ${lane}: ${row.model}\n`)
      const result = await runOne(row.model, lane)
      out.push({ ...result, score: result.pass ? row.score : 0 })
    }
    evidence.lanes[lane] = out
  }
  const normalized = normalizeBenchEvidence(evidence)
  const nextEvidence = { ...evidence, lanes: normalized.lanes }
  let outputEvidence = nextEvidence
  if (write && !reset && existsSync(OUT)) {
    try {
      outputEvidence = mergeBenchEvidence(JSON.parse(readFileSync(OUT, "utf8")), nextEvidence)
    } catch {
      outputEvidence = nextEvidence
    }
  }
  const body = JSON.stringify(outputEvidence, null, 2)
  if (write) writeFileSync(OUT, `${body}\n`)
  process.stdout.write(`${body}\n`)
  if (write) process.stderr.write(`wrote ${OUT}\n`)
  if (!existsSync(OUT) && !write) process.stderr.write("model-bench.json not written; pass --write to persist evidence\n")
}

main().catch((err) => {
  process.stderr.write(`${err?.stack || err}\n`)
  process.exit(1)
})
