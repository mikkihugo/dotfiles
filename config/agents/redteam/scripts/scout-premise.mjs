#!/usr/bin/env node
// Premise experiment for #10 (scout→heavy bughunt): do CHEAP scan-tier models localize
// risk the same way DEEP-tier models do? Runs the SAME files through both tiers in review
// mode, scores each file by severity-weighted finding count, and measures whether the
// scan ranking correlates with the deep "ground-truth" hotspot ranking. If scan ≈ random
// (Spearman ~0), scout→heavy collapses to --scatter and should NOT be built.
//
// Reuses runner.mjs by lineage so the experiment uses the same live catalog chain as reviews.
import { spawn } from "node:child_process"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = dirname(fileURLToPath(import.meta.url))
const RUNNER = join(HERE, "runner.mjs")
const REPO = join(HERE, "..")

const FILES = [
  "scripts/runner.mjs",
  "scripts/panel.mjs",
  "scripts/deepseek-tool-parser.mjs",
  "scripts/model-discovery.mjs",
  "scripts/chain-logic.mjs",
  "scripts/build-bridge.mjs",
]
const SCAN = ["nemotron", "gpt-oss"]
const DEEP = ["deepseek", "mistral"]
const SEV = { critical: 4, high: 3, medium: 2, low: 1 }

function review(lineage, file) {
  const args = [RUNNER, lineage, "--lineage", lineage, "--mode", "review", "--input", file, "--target", file,
    "--repo-root", REPO, "--focus", "real, triggerable bugs in this specific file", "--no-deepwiki", "--timeout", "200000"]
  return new Promise((resolve) => {
    const p = spawn("node", args, { stdio: ["ignore", "pipe", "ignore"] })
    let out = ""
    p.stdout.on("data", (d) => (out += d))
    p.on("close", () => {
      let v = null
      try { v = JSON.parse(out.trim().split("\n").pop()) } catch {}
      const findings = v?.findings || []
      const score = findings.reduce((s, f) => s + (SEV[f.severity] || 0), 0)
      process.stderr.write(`  ${lineage}  ${file}  → ${findings.length} findings, score ${score}\n`)
      resolve({ lineage, file, n: findings.length, score, ok: !!v && v.verdict !== "error" && !/^Lineage review failed:/.test(v.summary || "") })
    })
    p.on("error", () => resolve({ lineage, file, n: 0, score: 0, ok: false }))
  })
}

// bounded parallel
async function pool(items, fn, width = 4) {
  const res = []; let i = 0
  await Promise.all(Array.from({ length: width }, async () => {
    while (i < items.length) { const j = i++; res[j] = await fn(items[j]) }
  }))
  return res
}

// Spearman rank correlation (ties → average rank). N is small; clarity over speed.
function ranks(xs) {
  const idx = xs.map((v, i) => [v, i]).sort((a, b) => a[0] - b[0])
  const r = new Array(xs.length)
  let k = 0
  while (k < idx.length) {
    let j = k
    while (j + 1 < idx.length && idx[j + 1][0] === idx[k][0]) j++
    const avg = (k + j) / 2 + 1
    for (let t = k; t <= j; t++) r[idx[t][1]] = avg
    k = j + 1
  }
  return r
}
function pearson(a, b) {
  const n = a.length, ma = a.reduce((s, x) => s + x, 0) / n, mb = b.reduce((s, x) => s + x, 0) / n
  let num = 0, da = 0, db = 0
  for (let i = 0; i < n; i++) { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) ** 2; db += (b[i] - mb) ** 2 }
  return da && db ? num / Math.sqrt(da * db) : 0
}
const spearman = (a, b) => pearson(ranks(a), ranks(b))

const jobs = []
for (const f of FILES) for (const m of [...SCAN, ...DEEP]) jobs.push({ m, f })
process.stderr.write(`scout-premise: ${jobs.length} reviews (${FILES.length} files × ${SCAN.length + DEEP.length} lineages)\n`)
const results = await pool(jobs, (j) => review(j.m, j.f))

// per-file mean score per tier
const byFile = {}
for (const f of FILES) byFile[f] = { scan: [], deep: [] }
for (const r of results) {
  if (!r.ok) continue
  if (SCAN.includes(r.lineage)) byFile[r.file].scan.push(r.score)
  else byFile[r.file].deep.push(r.score)
}
const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : 0)
const rows = FILES.map((f) => ({ file: f, scan: mean(byFile[f].scan), deep: mean(byFile[f].deep), scanN: byFile[f].scan.length, deepN: byFile[f].deep.length }))

const scanScores = rows.map((r) => r.scan)
const deepScores = rows.map((r) => r.deep)
const rho = spearman(scanScores, deepScores)

// recall@3: of the deep top-3 hotspot files, how many are in the scan top-3?
const topK = (scores, k) => rows.map((r, i) => [scores[i], i]).sort((a, b) => b[0] - a[0]).slice(0, k).map((x) => rows[x[1]].file)
const deepTop3 = topK(deepScores, 3)
const scanTop3 = topK(scanScores, 3)
const hit = deepTop3.filter((f) => scanTop3.includes(f)).length
// random baseline for recall@3 with 6 files: expected overlap = 3*3/6 = 1.5

console.log(JSON.stringify({
  experiment: "scout-premise",
  files: rows,
  deep_hotspot_ranking: topK(deepScores, FILES.length),
  scan_hotspot_ranking: topK(scanScores, FILES.length),
  spearman_scan_vs_deep: Number(rho.toFixed(3)),
  recall_at_3: hit,
  recall_at_3_random_expected: 1.5,
  verdict: rho > 0.5 && hit >= 2 ? "PREMISE HOLDS — scan localizes like deep, build scout→heavy"
    : rho < 0.2 ? "PREMISE FAILS — scan ≈ random, do NOT build (keep --scatter or all-files-tiered)"
    : "INCONCLUSIVE — weak signal, expand N before building",
}, null, 2))
