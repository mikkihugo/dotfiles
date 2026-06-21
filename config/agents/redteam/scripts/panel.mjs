#!/usr/bin/env node
/**
 * panel.mjs — fan the adversarial review across a cross-lineage panel.
 *
 * Two tiers:
 *   small (default): a RANDOM 2 lineages, stratified so they don't all share a
 *                    heritage group (anti-blindness — a fixed subset would
 *                    reintroduce a permanent blind spot; random rotation samples
 *                    different blind spots across runs).
 *   wider:           `-n N`, `--package triage|audit`, or explicit `--models`.
 *
 * Merge is the UNION, not a consensus/dedup: every unique finding any lineage
 * raised is kept (the lone voice is often the prize — it's the blind spot the
 * others missed). Identical findings (file+line+title) are merged into one line
 * tagged with every lineage that raised it; agreement count only affects display
 * order, never whether a finding survives.
 *
 * Usage:
 *   node panel.mjs [-n 2] --repo-root <dir> [--base <ref>] [--focus <text>]
 *   node panel.mjs [-n 2] --plan <file>   # review a specific plan document (sets --text and --mode plan)
 */
if (process.argv.includes("--help") || process.argv.includes("-h")) {
  process.stderr.write(
    "Usage: panel.mjs [options]\n" +
      "  --repo-root <dir>     Review root (default cwd)\n" +
      "  --base <ref>          Git base for diff (default HEAD)\n" +
      "  --package <name>      triage|audit|free|harvest\n" +
      "  --models a,b          Explicit lineages\n" +
      "  --lane <name>         Route by bench lane: scout|review|deep-review|architect|builder|verify|summarize\n" +
      "  --bench <file>        Bench evidence file (default model-bench.json)\n" +
      "  --lane-planner-model <provider/model>  Optional exact model to rank eligible lane candidates\n" +
      "  --lane-planner-timeout <ms>  Planner call timeout (default 120000)\n" +
      "  --no-lane-route       Disable bench-backed lane routing\n" +
      "  --no-lane-planner     Disable REDTEAM_LANE_PLANNER_MODEL for this run\n" +
      "  --bughunt N           Two-phase scout+heavy hunt (N heavy files)\n" +
      "  --scout-count N       Bughunt scout model count (default 3)\n" +
      "  --ultrareview         Multi-lens pre-merge sweep\n" +
      "  --mode <name>         review|plan|decision|security|ultrareview|verify|harvest|hunt|smoke|solve\n" +
      "  --plan <file>         Review a plan document (implies --mode plan unless overridden)\n" +
      "  --verify              Run verification pass on findings\n" +
      "  --help                This message\n"
  )
  process.exit(0)
}

import { execFileSync, spawn } from "node:child_process"
import { appendFileSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join, basename } from "node:path"
import { fileURLToPath } from "node:url"
import { planJobs, aggregateAllFiles, synthesizeUltrareview, planLensRoutes, isChainFailure, scoutScores, selectScoutModels, selectHotspots, buildScoutHandoff, buildPanelAttribution, computePanelVerdict, isHarnessFailureVerdict, summarizeLineageAttempt, planBackfillReplacements, isPanelSlotSatisfied, pickDistinctLineagePanel, stratifyPanelSwap, mergeBackfillRound, classifyReviewLane, normalizeBenchEvidence, eligibleLaneCandidates, planLaneRoute, buildLanePlannerPrompt, planLaneRouteWithPlanner } from "./chain-logic.mjs"
import { adjustSelectionWeights, pickWeighted } from "./reputation.mjs"
import { classifyTier, discoverModels, getDeclaredModels, inferLineage } from "./model-discovery.mjs"
import { validateModelsPolicy } from "./model-policy.mjs"
import { applyHallucinationGate, recordReputationFromVerification, verifySchemaAndHardCap, checkApproveSummaryForHallucination, gateVerdictRows } from "./lib/quality-gates.mjs"
import { registerPanelJob, completePanelJob, redactTrace } from "./lib/job-state.mjs"
import { spawnTask } from "./lib/background-task.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
process.on("exit", (code) => {
  process.stderr.write(`\n=== REDTEAM EXIT status=${code} ===\n`)
})

const MODELS_JSON = JSON.parse(readFileSync(join(HERE, "..", "models.json"), "utf8"))
const MODELS_POLICY = validateModelsPolicy(MODELS_JSON)
if (!MODELS_POLICY.ok) {
  process.stderr.write(`redteam: invalid models.json policy: ${MODELS_POLICY.errors.join("; ")}\n`)
  process.exit(2)
}
const LINEAGES = Object.keys(MODELS_JSON.lineage_provider_seeds || {})
const DISABLED_LINEAGES = new Set(Object.keys(MODELS_JSON.disabled_lineages || {}))
const DEPRIORITIZED_LINEAGES = new Set(Object.keys(MODELS_JSON.deprioritized_lineages || {}))
const FREE_STATIC = MODELS_JSON.free || [] // curated fallback if catalog discovery fails
const WORKERS = {
  moonshot: join(HERE, "runner.mjs"),
}

const flag = (name, def = null) => {
  const i = process.argv.lastIndexOf(name) // last occurrence wins → template default + user override resolves to override
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def
}

// Discover ZERO-COST models from opencode's own catalog (models.dev cache) so the
// free panel self-updates and is defined by actual cost, NOT the ":free" suffix or
// the provider name — opencode/* is NOT uniformly free (Zen has paid models too),
// so we filter on cost.input===0 && cost.output===0. Restricted to providers whose
// keys are present (opencode = Zen via OPENCODE_API_KEY). A context floor drops
// 1-3B toys useless for code review, and
// we keep one model per lineage family for diversity.
function discoverFreeModels() {
  try {
    const cat = JSON.parse(readFileSync(join(homedir(), ".cache", "opencode", "models.json"), "utf8"))
    const usable = ["opencode"]
    const famOf = (id) => id.split("/").pop().replace(/:free$/, "").replace(/[-:.].*/, "").toLowerCase()
    const found = []
    for (const pid of usable) {
      for (const [id, m] of Object.entries(cat[pid]?.models || {})) {
        const c = m.cost || {}
        const zero = Number(c.input || 0) === 0 && Number(c.output || 0) === 0
        const ctx = m.limit?.context || m.limit?.input || 0
        // Must be able to READ code (agentic tool use) and emit text only — drops
        // audio/image models (lyria), meta-routers (auto), and no-tool stealth
        // models that can't open files. Covert/cloaked text models with tool_call
        // (the genuinely-useful free frontier evals) are kept.
        const out = m.modalities?.output || ["text"]
        const textOnly = out.length === 1 && out[0] === "text"
        if (zero && ctx >= 100000 && m.tool_call === true && textOnly) {
          found.push({ full: `${pid}/${id}`, ctx, fam: famOf(id) })
        }
      }
    }
    if (!found.length) return FREE_STATIC
    found.sort((a, b) => b.ctx - a.ctx) // prefer larger context within a family
    const byFam = new Map()
    for (const f of found) if (!byFam.has(f.fam)) byFam.set(f.fam, f.full)
    return [...byFam.values()]
  } catch {
    return FREE_STATIC
  }
}
// Per-session/per-run output isolation — mirrors the codex plugin's session-scoped
// dirs (its SessionStart hook captures the Claude session_id into env, then namespaces
// state by it). Without this, two concurrent Claude sessions both wrote
// /tmp/redteam/<provider>_<model>.json and clobbered each other's per-lineage JSONs
// (torn/partial writes). Group by session id, unique per run via mkdtemp.
const SID = (process.env.CLAUDE_CODE_SESSION_ID || process.env.CODEX_COMPANION_SESSION_ID || "nosession").replace(/[^\w.-]/g, "_")
mkdirSync("/tmp/redteam", { recursive: true })
// GC: a long-lived server (the SF pod can run for months) accumulates one results
// dir per run forever. Sweep dirs not touched in >7 days so /tmp/redteam can't
// grow unbounded. Best-effort — never let cleanup failure block a review.
try {
  const GC_AGE_MS = 7 * 24 * 60 * 60 * 1000
  const now = Date.now()
  for (const name of readdirSync("/tmp/redteam")) {
    const p = join("/tmp/redteam", name)
    try { if (now - statSync(p).mtimeMs > GC_AGE_MS) rmSync(p, { recursive: true, force: true }) } catch {}
  }
} catch {}
const OUT = mkdtempSync(join("/tmp/redteam", `${SID}-`))
const LOG_FILE = join(OUT, "panel.log")
const repoRoot = flag("--repo-root", process.cwd())
registerPanelJob(repoRoot, {
  id: basename(OUT),
  pid: process.pid,
  outDir: OUT,
  logFile: LOG_FILE,
  sessionId: SID,
  kind: "panel",
  argv: process.argv.slice(2),
})
const originalStderrWrite = process.stderr.write.bind(process.stderr)
process.stderr.write = (chunk, encoding, cb) => {
  const text = Buffer.isBuffer(chunk) ? chunk.toString(typeof encoding === "string" ? encoding : "utf8") : String(chunk)
  try { appendFileSync(LOG_FILE, redactTrace(text), "utf8") } catch {}
  return originalStderrWrite(chunk, encoding, cb)
}
process.stderr.write(`redteam: results dir = ${OUT}\n`)
process.stderr.write(`redteam: job id = ${basename(OUT)}\n`)
// Named presets ("packages") so callers pick intent, not a model count:
//   triage → stratified 3 ("is there a problem?")   audit → stratified 5 (facet sweet spot)
//   deep   → all 10 (keystone audits)
// A package sets the size; --models / -n still override if given explicitly.
const PACKAGES = { triage: { n: 3 }, audit: { n: 5 }, free: { free: true }, harvest: { n: 3, mode: "harvest" } }
const pkg = flag("--package", null)
if (pkg && !PACKAGES[pkg]) {
  process.stderr.write(`redteam: unknown --package "${pkg}" (expected: ${Object.keys(PACKAGES).join(", ")})\n`)
  process.exit(2)
}
const pkgCfg = pkg ? PACKAGES[pkg] : {}

const n = Number.parseInt(flag("-n", String(pkgCfg.n ?? 2)), 10)
let panelTarget = n
const base = flag("--base", null)
// Substrate selectors — forwarded to each worker so the panel can review a
// document/subsystem, not only the git diff (redteam-moonshot.mjs accepts
// --text / --input / --target / --mode; the panel previously dropped them).
let text = flag("--text", null)
const input = flag("--input", null)
let target = flag("--target", null)

// --plan <file>: ergonomic way to review a specific plan document.
// Reads the file and forwards it via --text so runners treat it as the review target.
const planFile = flag("--plan", null)
if (planFile) {
  try {
    text = readFileSync(planFile, "utf8")
    if (!target) target = planFile // give runners a nice label
  } catch (err) {
    process.stderr.write(`redteam: failed to read --plan file "${planFile}": ${err.message}\n`)
    process.exit(2)
  }
}

const full = process.argv.includes("--full") // review the ENTIRE repository, not a diff
const mode = flag("--mode", planFile ? "plan" : pkgCfg.mode ?? null)
const thinkingCheck = flag("--thinking-check", null)
const maxTokens = flag("--max-tokens", null)
const noDeepwiki = process.argv.includes("--no-deepwiki")
const timeout = flag("--timeout", null)
const backend = flag("--backend", process.env.REDTEAM_BACKEND || "moonshot")
if (!WORKERS[backend]) {
  process.stderr.write(`redteam: unknown --backend "${backend}" (expected: ${Object.keys(WORKERS).join(", ")})\n`)
  process.exit(2)
}
// A BARE positional arg (no leading flag) is treated as --focus text, so
// `redteam … "review the X subsystem"` steers the review instead of being
// silently swallowed by the flag-only parser (the original bug).
const VALUE_FLAGS = new Set([
  "-n", "--repo-root", "--base", "--focus", "--concurrency",
  "--text", "--input", "--target", "--mode", "--timeout",
  "--models", "--package", "--verifier", "--scatter",
  "--thinking-check", "--max-tokens", "--backend", "--per-file", "--per-lens",
  "--bughunt", "--scout-models", "--scout-count", "--baseline-tail",
  "--plan", "--lane", "--bench", "--lane-planner-model", "--lane-planner-timeout",
])
const BOOL_FLAGS = new Set(["--no-deepwiki", "--all-files", "--changed", "--ultrareview", "--no-verify", "--full", "--no-lane-route", "--no-lane-planner"])
const positionals = []
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i]
  if (VALUE_FLAGS.has(a)) { i++; continue }
  if (BOOL_FLAGS.has(a) || a.startsWith("-")) continue
  positionals.push(a)
}
let focus = flag("--focus", null) || (positionals.length ? positionals.join(" ") : "(none)")
// PER-PROVIDER concurrency (see pool()). opencode-go and ollama-cloud are each a
// single flat-rate aggregator subscription — their 4 models share ONE upstream
// rate bucket, which was the "fetch failed" source under load — so each provider
// is capped independently while direct providers (minimax, kimi-for-coding) get
// their own slot. Default 2 per provider; override with --concurrency.
const concurrency = Number.parseInt(flag("--concurrency", "4"), 10)
// --verify: after the union-merge, adversarially REFUTE each finding with a
// DIFFERENT lineage (read the code, prove it wrong). Drops false positives the
// union otherwise keeps. --verifier pins the refuter model.
const verify = process.argv.includes("--verify")
const verifierOverride = flag("--verifier", null)
// Refuter lineages for --verify. Concrete models are resolved dynamically by runner.mjs.
const VERIFIER_POOL = ["kimi", "mistral", "minimax", "google"]
// --ultrareview lenses: focused remits, one per FIND-phase agent (our replica of
// ultrareview's fleet). Each lens is run by a DIFFERENT lineage, so coverage varies
// on two axes at once: what to look for (lens) AND who is looking (vendor).
// `tier` classifies each lens by REMIT difficulty (task classification — NOT model
// competence, which we never guess). `deep` = semantic, needs reasoning/tracing →
// staffed deep-tier only. `scan` = broad pattern sweep → a small/fast scan-tier model
// is a first-class reviewer here (the operator's "smaller models for scanning like
// antipatterns"), always under a deep anchor. planLensRoutes consumes this.
const ULTRA_LENSES = [
  { key: "correctness", tier: "deep", focus: "logic/correctness bugs ONLY: wrong conditions, off-by-one, inverted checks, bad state transitions, incorrect return values, edge cases that produce wrong results" },
  { key: "concurrency", tier: "deep", focus: "concurrency/async bugs ONLY: races, deadlocks, missing await, shared-state mutation, ordering assumptions, unsafe parallelism, TOCTOU" },
  { key: "error-handling", tier: "deep", focus: "error-handling/failure-mode bugs ONLY: swallowed errors, unhandled rejections, missing try/catch, partial failure left inconsistent, silent fallthrough, bad cleanup on error path" },
  { key: "security", tier: "deep", focus: "security bugs ONLY: injection, auth/authorization bypass, secret/credential exposure, path traversal, unsafe deserialization, SSRF, unvalidated input reaching a sink" },
  { key: "resource", tier: "deep", focus: "resource/lifecycle bugs ONLY: leaks, unclosed handles/fds/sockets, missing cleanup/finally, unbounded growth, lock never released, orphaned processes" },
  { key: "api-contract", tier: "deep", focus: "contract/invariant bugs ONLY: broken invariants, null/undefined misuse, off-spec API usage, type confusion, wrong argument order, violated pre/postconditions" },
  { key: "performance", tier: "deep", focus: "performance bugs ONLY: unbounded work, blocking calls on a hot path, N+1, accidental O(n^2), redundant I/O, missing memoization where it matters" },
  { key: "tests", tier: "deep", focus: "test-quality bugs ONLY: missing coverage for the change, assertions that can't fail, tests that don't test the claim, wrong fixtures, flaky timing assumptions" },
  { key: "antipatterns", tier: "scan", focus: "broad antipattern/code-smell SWEEP: TODO/FIXME left in shipped paths, copy-paste duplication, dead code, magic numbers, swallowed `.catch(()=>{})`, console.* in production paths, overly broad try/catch, sync I/O on a hot path, obvious style/hazard patterns. Breadth over depth — flag the pattern occurrences." },
]
// --scatter N: random codebase audit — pick N random source files under repoRoot
// and review each with a DIFFERENT lineage (one model per place). Breadth probe,
// not a deep single-target panel.
const scatterN = Number.parseInt(flag("--scatter", "0"), 10)

// Heritage groups — keeps a small random pick from landing all-same-family.
const groupOf = (m) =>
  /deepseek|glm|qwen|mimo|minimax|kimi|moonshot/i.test(m) ? "east" : "west"

// Explicit subset: `--models a,b,c` (or repeated) runs exactly those lineages
// through the SAME concurrency-managed pool() as -n — so callers never
// have to hand-roll an xargs loop to target specific models. Entries may be
// lineage names or explicit `provider/model` direct chain heads.
const explicitModels = flag("--models", null)
const explicitLane = flag("--lane", null)
const laneRoutingEnabled = !process.argv.includes("--no-lane-route")
const lanePlannerModel = process.argv.includes("--no-lane-planner")
  ? null
  : flag("--lane-planner-model", process.env.REDTEAM_LANE_PLANNER_MODEL || null)
const lanePlannerTimeout = flag("--lane-planner-timeout", process.env.REDTEAM_LANE_PLANNER_TIMEOUT_MS || "120000")

function readBenchEvidence() {
  const benchPath = flag("--bench", join(HERE, "..", "model-bench.json"))
  try {
    return normalizeBenchEvidence(JSON.parse(readFileSync(benchPath, "utf8")))
  } catch {
    return normalizeBenchEvidence({})
  }
}

async function resolveLaneRoute(lane) {
  const discovered = await discoverModels({ cachePath: null })
  const live = new Set(discovered.map((d) => d.id))
  const metadata = new Set(discovered.map((d) => d.id))
  const configured = new Set(getDeclaredModels())
  const candidates = eligibleLaneCandidates({
    lane,
    bench: readBenchEvidence(),
    configured,
    live,
    metadata,
  })
  let plannerChoice = null
  if (lanePlannerModel && candidates.length > 1) {
    try {
      const plannerPrompt = buildLanePlannerPrompt({
        lane,
        candidates,
        context: [
          `mode=${mode || "review"}`,
          focus ? `focus=${focus}` : "",
          target ? `target=${target}` : "",
        ].filter(Boolean).join("; "),
      })
      const out = execFileSync(process.execPath, [
        WORKERS[backend],
        "--model", lanePlannerModel,
        "--repo-root", repoRoot,
        "--mode", "route",
        "--text", plannerPrompt,
        "--target", `lane-route:${lane}`,
        "--no-deepwiki",
        "--timeout", lanePlannerTimeout,
        "--max-tokens", "800",
      ], { cwd: repoRoot, encoding: "utf8", maxBuffer: 8 * 1024 * 1024 })
      plannerChoice = JSON.parse(out.trim().split("\n").filter(Boolean).at(-1))
      process.stderr.write(`redteam: lane planner ${lanePlannerModel} proposed primary=${plannerChoice.primary} failover=${(plannerChoice.failover || []).join(",")}\n`)
    } catch (err) {
      process.stderr.write(`redteam: lane planner unavailable: ${err?.message || err}\n`)
    }
  }
  const routePolicy = {
    directProviderByLineage: MODELS_JSON.direct_provider_by_lineage || {},
    providerPriority: MODELS_JSON.provider_priority || [],
  }
  return plannerChoice
    ? planLaneRouteWithPlanner(lane, candidates, plannerChoice, routePolicy)
    : planLaneRoute(lane, candidates, routePolicy)
}

function automaticLineagePool(lineages = LINEAGES) {
  const active = lineages.filter((lineage) => !DISABLED_LINEAGES.has(lineage))
  const normal = active.filter((lineage) => !DEPRIORITIZED_LINEAGES.has(lineage))
  const deprioritized = active.filter((lineage) => DEPRIORITIZED_LINEAGES.has(lineage))
  return [...normal, ...deprioritized]
}

const lineagePool = explicitModels ? LINEAGES : automaticLineagePool()
let models
if (explicitModels) {
  const want = explicitModels.split(",").map((s) => s.trim()).filter(Boolean)
  models = want.map((w) => lineagePool.find((m) => m === w) || lineagePool.find((m) => m.includes(w)) || w)
  panelTarget = models.length
} else if (pkgCfg.free) {
  // --package free: zero-cost models discovered live from opencode's catalog
  // (cost===0), self-updating, one per lineage.
  models = discoverFreeModels()
  if (models.length === 0) {
    process.stderr.write("redteam: no zero-cost models found in the live catalog\n")
    process.exit(2)
  }
  process.stderr.write(`redteam: free panel = ${models.length} zero-cost models — ${models.join(", ")}\n`)
} else {
  let laneRoute = null
  if (laneRoutingEnabled) {
    const lane = explicitLane || classifyReviewLane({ mode: mode || "review", focus })
    try {
      laneRoute = await resolveLaneRoute(lane)
      if (laneRoute) {
        process.stderr.write(`redteam: lane route ${laneRoute.lane} primary=${laneRoute.primary} failover=${laneRoute.failover.join(",")}\n`)
        models = [laneRoute.primary, ...laneRoute.failover]
        panelTarget = models.length
      }
    } catch (err) {
      process.stderr.write(`redteam: lane route unavailable: ${err?.message || err}\n`)
    }
  }
  if (!laneRoute) {
    let pool = lineagePool
    if (process.env.REDTEAM_REPUTATION === "1") {
      const weighted = adjustSelectionWeights(lineagePool)
      // Simple weighted sampling without replacement for the initial draw
      const picked = []
      const remaining = [...weighted]
      for (let i = 0; i < Math.min(n, remaining.length); i++) {
        const choice = pickWeighted(remaining)
        picked.push(choice)
        const idx = remaining.findIndex((x) => x.model === choice)
        if (idx >= 0) remaining.splice(idx, 1)
      }
      pool = picked.length ? picked : lineagePool
    }
    const shuffled = pool.map((m) => [Math.random(), m]).sort((a, b) => a[0] - b[0]).map((x) => x[1])
    const linOf = lineageForModel
    models = pickDistinctLineagePanel(shuffled, Math.min(n, lineagePool.length), linOf)
    models = stratifyPanelSwap(models, shuffled, groupOf, linOf)
  }
}

mkdirSync(OUT, { recursive: true })

// ── --scatter: random codebase breadth audit (N places × N lineages) ────────
function scatterOne(pair, opts = {}) {
  const sep = pair.indexOf("::")
  const model = pair.slice(0, sep)
  const file = pair.slice(sep + 2)
  const worker = workerForModel(model)
  const fileFocus = opts.focus || "real, triggerable bugs in this specific file"
  const args = [worker, model, "--repo-root", repoRoot, "--input", file, "--mode", "review",
    "--target", file, "--focus", fileFocus, "--no-deepwiki", "--timeout", timeout || "200000"]
  const lineage = lineageForModel(model)
  // Curated models are REGISTRY lineage heads → --lineage (chain + fallback). Discovered
  // scan-tier models (gemma3 etc., used by the scout phase) are NOT chain heads → pin with
  // --model so the runner runs THAT model, not the inferred lineage's canonical head.
  if (lineage) args.push("--lineage", lineage)
  else args.push("--model", model)
  if (thinkingCheck) args.push("--thinking-check", thinkingCheck)
  if (maxTokens) args.push("--max-tokens", maxTokens)
  // Scout phase = cheap advisory pass: force effort OFF so big models (e.g. minimax-m3 via the
  // chain) don't burn thinking on each of 40 files. Deep phase leaves env unset → harness default.
  const childEnv = { ...process.env }
  if (opts.scout) { childEnv.REDTEAM_REASONING_EFFORT = "none"; childEnv.REDTEAM_THINKING_EFFORT = "off" }
  return new Promise((resolve) => {
    process.stderr.write(`  → ${file}  ← ${model}\n`)
    const p = spawn("node", args, { stdio: ["ignore", "pipe", "pipe"], env: childEnv })
    let out = ""
    p.stdout.on("data", (d) => (out += d))
    p.stderr.on("data", (d) => process.stderr.write(d))
    p.on("close", () => {
      let v = null
      try { v = JSON.parse(out.trim().split("\n").pop()) } catch {}
      const warn = v?.schema_warning ? " ⚠schema" : ""
      process.stderr.write(`  ✓ ${file} → ${v?.verdict || "error"} (${(v?.findings || []).length})${warn}\n`)
      resolve({ file, model, verdict: v?.verdict || "error", summary: v?.summary || "", findings: v?.findings || [], schema_warning: v?.schema_warning })
    })
    p.on("error", () => resolve({ file, model, verdict: "error", findings: [] }))
  })
}
if (scatterN > 0) {
  const SKIP = /(^|\/)(node_modules|dist|\.git|\.sf|\.agents|\.claude|worktrees|result|\.direnv|coverage|build|\.cache|\.next|out|vendor|fixtures?)(\/|$)/
  const EXT = /\.(ts|js|mjs|cjs|tsx|jsx)$/
  let candidates = []
  try {
    candidates = readdirSync(repoRoot, { recursive: true })
      .map((p) => String(p))
      .filter((p) => EXT.test(p) && !SKIP.test(p) && !/\.(test|spec|d)\./.test(p))
  } catch (e) {
    process.stderr.write(`scatter: file discovery failed: ${e?.message ?? e}\n`)
    process.exit(2)
  }
  const files = candidates
    .map((p) => { try { return statSync(join(repoRoot, p)).size > 800 && statSync(join(repoRoot, p)).size < 180000 ? p : null } catch { return null } })
    .filter(Boolean)
  if (!files.length) {
    process.stderr.write("scatter: no candidate source files found under " + repoRoot + "\n")
    process.exit(2)
  }
  const shuffle = (arr) => arr.map((x) => [Math.random(), x]).sort((a, b) => a[0] - b[0]).map((x) => x[1])
  const picks = shuffle(files).slice(0, Math.min(scatterN, files.length))
  const modelPool = shuffle(automaticLineagePool())
  const pairs = picks.map((f, i) => `${modelPool[i % modelPool.length]}::${f}`)
  process.stderr.write(`redteam: scatter — ${picks.length} random places × ${new Set(pairs.map((p) => p.split("/")[0])).size} providers\n`)
  const results = (await pool(pairs, concurrency, scatterOne)).filter(Boolean)
  const report = {
    mode: "scatter",
    reviewed: results.length,
    places: results.map((r) => ({
      file: r.file, model: r.model, verdict: r.verdict,
      findings: (r.findings || []).map((f) => ({ severity: f.severity, title: f.title, line: f.line_start, confidence: f.confidence })),
    })),
  }
  console.log(JSON.stringify(report, null, 2))
  process.exit(0)
}

// ── --bughunt K: scout → heavy two-phase codebase bughunt ────────────────────
// Upgrade of --scatter (which picks files at RANDOM): cheap scan-tier models SCOUT
// every candidate file and score its bug-risk, then deep-tier models HEAVY-review
// only the top-K hotspots (+ a small random baseline tail to cover scout misses).
// Premise validated (scout-premise.mjs): scan scores surface the real hotspots
// (ρ≈0.78, recall@3=3/3). Scout scores are ADVISORY routing only — never surfaced
// as findings; the report carries the HEAVY verdicts. Reuses scatterOne/pool.
const bughuntN = Number.parseInt(flag("--bughunt", "0"), 10)
if (bughuntN > 0) {
  const SEV = { critical: 4, high: 3, medium: 2, low: 1 }
  const baselineTail = Math.max(0, Number.parseInt(flag("--baseline-tail", "2"), 10))
  const SKIP = /(^|\/)(node_modules|dist|\.git|\.sf|\.agents|\.claude|worktrees|result|\.direnv|coverage|build|\.cache|\.next|out|vendor|fixtures?)(\/|$)|bridge\.bundle\.mjs$/
  const EXT = /\.(ts|js|mjs|cjs|tsx|jsx)$/
  let files
  try {
    files = readdirSync(repoRoot, { recursive: true })
      .map((p) => String(p))
      .filter((p) => EXT.test(p) && !SKIP.test(p) && !/\.(test|spec|d)\./.test(p))
      .filter((p) => { try { const s = statSync(join(repoRoot, p)).size; return s > 800 && s < 180000 } catch { return false } })
      .sort()
  } catch (e) {
    process.stderr.write(`bughunt: file discovery failed: ${e?.message ?? e}\n`)
    process.exit(2)
  }
  if (!files.length) { process.stderr.write("bughunt: no candidate source files under " + repoRoot + "\n"); process.exit(2) }
  // Cap the SCOUT candidate set so the cheap phase stays cheap on a big repo (largest
  // files first — biggest surface area). The heavy phase only ever sees the top-K + tail.
  const SCOUT_CAP = 40
  if (files.length > SCOUT_CAP) {
    files = files.map((f) => [statSync(join(repoRoot, f)).size, f]).sort((a, b) => b[0] - a[0]).slice(0, SCOUT_CAP).map((x) => x[1])
  }
  // SCOUT ensemble: use a bounded 2-3 model scout team over the candidate files.
  // Scout scores are ADVISORY routing only; use --scout-count or --scout-models
  // to override the default small team.
  // Fast = flash, MiniMax M3 (scan pool, thinking off via scout env), or sized 20-200B.
  // Smaller models can be useful for very specific mechanical scouts, but they are opt-in
  // through --scout-models; the default general bughunt needs enough semantic capacity.
  const sizeOf = (id) => { const m = String(id).toLowerCase().match(/[:-](\d+(?:\.\d+)?)(b|t)\b/); return m ? (m[2] === "t" ? Number(m[1]) * 1000 : Number(m[1])) : null }
  const isFastScout = (id) => {
    const size = sizeOf(id)
    return /flash/i.test(id) || /\bminimax[- ]?m3\b/i.test(id) || /qwen3[-_.:]?(?:coder[-_.:]?next|next[-_.:]?coder|coder|next)/i.test(id) || (size !== null && size >= 20 && size <= 200)
  }
  // Excluded from the candidate pool (--scout-models still overrides):
  // - ministral: tiny model — high raw finding count but low precision/noisy; dropped per operator.
  // - rnj-1:8b: tiny unvetted model; dropped per operator.
  // The selector prefers M3, Devstral Small/Qwen coder, gpt-oss 20B, then
  // Gemma and flash/nano fallbacks such as DeepSeek and Nemotron.
  // opencode\/ = OpenCode Zen provider (unusable: no API key + 429s); anchored slash so it does
  //   NOT match the working opencode-go/ provider. gemini = drop gemini-flash from the scout pool
  //   per operator (noisy/rate-limited; google/gemini-2.5-flash stays available for panels).
  const SCOUT_EXCLUDE = /ministral|rnj|gemini|opencode\//i
  const scoutCount = Math.max(1, Number.parseInt(flag("--scout-count", "3"), 10) || 3)
  let scanModels = []
  try {
    const scoutRoute = laneRoutingEnabled ? await resolveLaneRoute("scout") : null
    if (scoutRoute) {
      scanModels = [scoutRoute.primary, ...scoutRoute.failover].slice(0, Math.max(2, scoutCount))
      process.stderr.write(`bughunt: scout lane route primary=${scoutRoute.primary} failover=${scoutRoute.failover.join(",")}\n`)
    }
  } catch (err) {
    process.stderr.write(`bughunt: scout lane route unavailable: ${err?.message || err}\n`)
  }
  try {
    const discovered = new Set((await discoverModels()).map((d) => d.id))
    const base = [...discovered].filter((id) => isFastScout(id) && !SCOUT_EXCLUDE.test(id))
    if (!scanModels.length) scanModels = selectScoutModels(base, {
      count: scoutCount,
      directProviderByLineage: MODELS_JSON.direct_provider_by_lineage || {},
      providerPriority: MODELS_JSON.provider_priority || [],
    })
  } catch { /* discovery best-effort */ }
  const scoutOverride = flag("--scout-models", null)
  if (scoutOverride) scanModels = scoutOverride.split(",").map((s) => s.trim()).filter(Boolean)
  if (!scanModels.length) { process.stderr.write("bughunt: no usable scout models discovered; pass --scout-models a,b\n"); process.exit(2) }
  let deepModels = []
  try {
    const deepRoute = laneRoutingEnabled ? await resolveLaneRoute("deep-review") : null
    if (deepRoute) {
      deepModels = [deepRoute.primary, ...deepRoute.failover]
      process.stderr.write(`bughunt: deep-review lane route primary=${deepRoute.primary} failover=${deepRoute.failover.join(",")}\n`)
    }
  } catch (err) {
    process.stderr.write(`bughunt: deep-review lane route unavailable: ${err?.message || err}\n`)
  }
  if (!deepModels.length) deepModels = lineagePool.filter((m) => !/cogito|google/i.test(m)).slice(0, 3)

  // PHASE 1 — SCOUT: scan models score every candidate file (advisory).
  const scoutPairs = files.flatMap((f) => scanModels.map((m) => `${m}::${f}`))
  process.stderr.write(`bughunt: SCOUT — ${files.length} files × ${scanModels.length} scan model(s) = ${scoutPairs.length} cheap passes\n`)
  const scoutRaw = (await pool(scoutPairs, concurrency, (p) => scatterOne(p, { scout: true }))).filter(Boolean)
  // Robust ensemble mean: a scout that NARRATED or timed out (chain failure) does not vote —
  // drop it so it can't drag a file's mean toward 0. scoutScores then means per file over the
  // EMITTING scouts only.
  const emitting = scoutRaw
    .filter((r) => !isChainFailure({ verdict: r.verdict, summary: r.summary }))
    .map((r) => ({ file: r.file, score: (r.findings || []).reduce((s, f) => s + (SEV[f.severity] || 0), 0) }))
  let ranked = scoutScores(emitting)
  // A file that NO scout could review (all narrated/timed out) still belongs in the tail at
  // score 0 so it stays baseline-eligible — never silently dropped from the candidate set.
  const scored = new Set(ranked.map((r) => r.file))
  for (const f of files) if (!scored.has(f)) ranked.push({ file: f, score: 0 })
  ranked.sort((a, b) => b.score - a.score || a.file.localeCompare(b.file))
  const emittedPct = scoutPairs.length ? Math.round((emitting.length / scoutPairs.length) * 100) : 0
  process.stderr.write(`bughunt: SCOUT done — ${emitting.length}/${scoutPairs.length} passes emitted a verdict (${emittedPct}%)\n`)
  const { hotspots, baseline, selected } = selectHotspots(ranked, { heavyK: bughuntN, baselineTail, fillToK: true })
  process.stderr.write(`bughunt: hotspots → ${hotspots.join(", ") || "(none scored)"}  | baseline → ${baseline.join(", ") || "(none)"}\n`)

  // PHASE 2 — HEAVY: deep models review the selected files. Spread deep models across
  // the selected files (one distinct deep model per file, rotated) so providers parallelise.
  const heavyPairs = selected.map((f, i) => `${deepModels[i % deepModels.length]}::${f}`)
  process.stderr.write(`bughunt: HEAVY — ${selected.length} hotspot(s) × deep review = ${heavyPairs.length} passes\n`)
  const heavyRaw = (await pool(heavyPairs, concurrency, (p) => {
    const file = p.slice(p.indexOf("::") + 2)
    const scoutHandoff = buildScoutHandoff(scoutRaw, file)
    const focus = scoutHandoff
      ? `real, triggerable bugs in this specific file\n\n${scoutHandoff}`
      : "real, triggerable bugs in this specific file"
    return scatterOne(p, { focus })
  })).filter(Boolean)

  // Apply unified quality gates to bughunt heavy phase.
  const gatedHeavy = applyHallucinationGate(heavyRaw, { repoRoot, record: true })
  recordReputationFromVerification(gatedHeavy.flatMap((r) => r.findings || []), [], { errorCategory: "bughunt" })

  const heavyAgg = aggregateAllFiles(gatedHeavy)
  const report = {
    mode: "bughunt",
    pipeline: "scout (scan-tier, advisory) → heavy (deep-tier, authoritative)",
    scout_models: scanModels,
    deep_models: deepModels,
    scouted: files.length,
    scout_ranking: ranked.map((r) => ({ file: r.file, score: Number(r.score.toFixed(2)) })),
    hotspots,
    baseline,
    heavy_reviewed: selected,
    files: heavyAgg.files,
    summary: `${heavyAgg.files.reduce((n, f) => n + f.findings.length, 0)} findings across ${selected.length} deep-reviewed file(s) (scout localized ${hotspots.length} hotspot(s) from ${files.length} scouted)`,
  }
  console.log(JSON.stringify(report, null, 2))
  process.exit(0)
}

// --all-files: review EVERY tracked source file (not a random sample like
// --scatter), each by --per-file lineages SPREAD across provider lanes so the
// direct providers (minimax, kimi, xiaomi) run truly parallel with the gated
// ollama lane. Deterministic in-process swarm through the same pool()/scatterOne
// the rest of the panel uses — replaces brittle shell loops over the single-file
// runner (where a tab-split bug silently fed garbage and every job "passed" in 0s).
const allFiles = process.argv.includes("--all-files")
const perFile = Math.max(1, Number.parseInt(flag("--per-file", "1"), 10))
if (allFiles) {
  const SKIP = /(^|\/)(node_modules|dist|\.git|worktrees|result|coverage|build|\.tmp)(\/|$)|bridge\.bundle\.mjs$|package-lock\.json$/
  const REVIEWABLE = /\.(ts|js|mjs|cjs|tsx|jsx|json|md|sh)$/
  let tracked = []
  try {
    tracked = execFileSync("git", ["-C", repoRoot, "ls-files"], { encoding: "utf8" })
      .split("\n").map((s) => s.trim()).filter(Boolean)
  } catch (e) {
    process.stderr.write(`all-files: git ls-files failed: ${e?.message ?? e}\n`)
    process.exit(2)
  }
  let files = tracked
    .filter((p) => REVIEWABLE.test(p) && !SKIP.test(p))
    .filter((p) => { try { const s = statSync(join(repoRoot, p)).size; return s > 200 && s < 200000 } catch { return false } })
    .sort()
  if (!files.length) {
    process.stderr.write("all-files: no reviewable tracked files under " + repoRoot + "\n")
    process.exit(2)
  }
  // --changed: incremental review — only files that differ from --base (default
  // HEAD: working-tree edits; pass --base origin/main for a whole branch). Avoids
  // re-reviewing an unchanged codebase every run, the single biggest token saver.
  if (process.argv.includes("--changed")) {
    const ref = base || "HEAD"
    let changed
    try {
      const diff = execFileSync("git", ["-C", repoRoot, "diff", "--name-only", ref], { encoding: "utf8" })
      const untracked = execFileSync("git", ["-C", repoRoot, "ls-files", "--others", "--exclude-standard"], { encoding: "utf8" })
      changed = new Set(`${diff}\n${untracked}`.split("\n").map((s) => s.trim()).filter(Boolean))
    } catch (e) {
      process.stderr.write(`all-files --changed: git diff vs ${ref} failed: ${e?.message ?? e}\n`)
      process.exit(2)
    }
    files = files.filter((p) => changed.has(p))
    process.stderr.write(`redteam: all-files --changed vs ${ref} — ${files.length} changed reviewable file(s)\n`)
    if (!files.length) {
      process.stderr.write(`all-files --changed: nothing reviewable changed vs ${ref}\n`)
      process.exit(0)
    }
  }
  // Use lineage names only. runner.mjs resolves the concrete provider/model
  // chain from Kimi/models.dev plus live provider discovery.
  const SPREAD = ["minimax", "kimi", "mimo", "nemotron", "mistral", "gpt-oss", "deepseek"]
    .filter((m) => lineagePool.includes(m))
  const pairs = planJobs(files, SPREAD, perFile)
  process.stderr.write(`redteam: all-files — ${files.length} files × ${perFile} lineage(s) = ${pairs.length} reviews, ${concurrency}/provider\n`)
  const results = (await pool(pairs, concurrency, scatterOne)).filter(Boolean)
  const report = aggregateAllFiles(results)
  if (verify) {
    // Adversarial refutation: flatten every finding into a verify-shaped object
    // (carrying its file + raising lineage), refute each with a DIFFERENT lineage,
    // and DROP only explicit false-positives (errors/timeouts fail open). Confirmed
    // findings stay on their file; refuted ones move to a top-level refuted_dropped.
    const flat = report.files.flatMap((fe) =>
      fe.findings.map((fd) => ({ severity: fd.severity, title: fd.title, file: fe.file, line_start: fd.line, body: "", recommendation: fd.recommendation, lineages: [fd.by] })))
    if (flat.length) {
      process.stderr.write(`redteam: all-files --verify → refuting ${flat.length} findings…\n`)
      const checks = await poolVerifyFindings(flat)
      const refutedKeys = new Set()
      const refuted = []
      flat.forEach((f, i) => {
        const v = checks[i] || { verdict: "unverified" }
        if (v.verdict === "false-positive") {
          refutedKeys.add(`${f.file}\n${f.title}`)
          refuted.push({ ...f, _verify: v })
        }
      })
      for (const fe of report.files) fe.findings = fe.findings.filter((fd) => !refutedKeys.has(`${fe.file}\n${fd.title}`))
      report.verify_summary = `${flat.length - refuted.length} confirmed / ${refuted.length} refuted of ${flat.length}`
      report.refuted_dropped = refuted
    }
  }
  console.log(JSON.stringify(report, null, 2))
  process.exit(0)
}

// One FIND-phase lens pass: review the diff/target through a single lens with a
// single lineage, returning findings tagged with both. item = "model::lensKey".
function runLensPass(item) {
  const sep = item.indexOf("::")
  const model = item.slice(0, sep)
  const lensKey = item.slice(sep + 2)
  const lens = ULTRA_LENSES.find((l) => l.key === lensKey)
  const worker = workerForModel(model)
  const args = [worker, model, "--repo-root", repoRoot, "--mode", "ultrareview", "--focus", lens.focus, "--no-deepwiki", "--timeout", timeout || "260000"]
  const lineage = lineageForModel(model)
  // Curated models are REGISTRY lineage heads → run via --lineage (chain + fallback).
  // Discovered scan models (gemma4 etc.) are NOT chain heads → pin with --model so the
  // runner runs THAT model, not the inferred lineage's canonical chain head.
  if (lineage) args.push("--lineage", lineage)
  else args.push("--model", model)
  if (base) args.push("--base", base)
  if (text) args.push("--text", text)
  if (input) args.push("--input", input)
  if (target) args.push("--target", target); if (full) args.push("--full")
  if (maxTokens) args.push("--max-tokens", maxTokens)
  return new Promise((resolve) => {
    process.stderr.write(`  → [${lensKey}] ${model} …\n`)
    const p = spawn("node", args, { stdio: ["ignore", "pipe", "pipe"] })
    let out = ""
    p.stdout.on("data", (d) => (out += d))
    p.stderr.on("data", (d) => process.stderr.write(d))
    p.on("close", () => {
      let v
      try { v = JSON.parse(out.trim().split("\n").pop()) } catch { v = { findings: [] } }
      const findings = (v?.findings || []).map((f) => ({ ...f, lens: lensKey, by: model }))
      process.stderr.write(`  ✓ [${lensKey}] ${model} → ${findings.length}\n`)
      resolve(findings)
    })
    p.on("error", () => resolve([]))
  })
}

// ── --ultrareview: our replica of Claude Code's ultrareview, with vendor diversity.
// Pipeline FIND → VERIFY → DEDUPE: a fleet of focused lenses (each a distinct
// lineage) hunts the diff, every finding is refuted by a different lineage, then
// nearby findings are merged and agreement-weighted. Reviews a change, so it needs
// a target (--base <ref> | --input <file> | --target <file> | --text).
if (process.argv.includes("--ultrareview")) {
  if (!base && !text && !input && !target && !full) {
    process.stderr.write(
      "ultrareview: needs something to review — one of:\n" +
      "  --base <ref>      diff vs a ref (e.g. --base origin/main)\n" +
      "  --input <file>    a specific file/diff\n" +
      "  --target <file>   a file to deep-review\n" +
      "  --full            the ENTIRE repository (each lens explores the whole tree)\n",
    )
    process.exit(2)
  }
  // FIND fleet: tier-aware routing (planLensRoutes). Each lens gets --per-lens distinct-
  // lineage reviewers; deep (semantic) lenses are staffed deep-tier, the scan-eligible
  // antipattern lens gets a deep anchor + cheap scan-tier breadth. The DEEP pool is the
  // dynamic lineage pool (skip cogito = narrates on big inputs, google = rate-limited; both fine
  // as verifiers); the SCAN pool is discovered live (gemma4 etc.) and ADDITIVE — if
  // discovery fails the scan lens degrades to a deep anchor, never blocking the run.
  const perLens = Math.max(1, Number.parseInt(flag("--per-lens", "2"), 10))
  const fleet = lineagePool.filter((m) => !/cogito|google/i.test(m))
  if (fleet.length === 0) { process.stderr.write("ultrareview: no usable lineages\n"); process.exit(2) }
  const deepPool = fleet.map((id) => ({ id, lineage: id, tier: "deep" }))
  const scanPool = []
  try {
    const seen = new Set()
    for (const d of await discoverModels()) {
      if (d?.tier !== "scan" || !d.lineage || seen.has(d.lineage)) continue
      seen.add(d.lineage)
      scanPool.push({ id: d.id, lineage: d.lineage, tier: "scan" })
      if (scanPool.length >= 3) break // bound the cheap-breadth layer to a few distinct lineages
    }
  } catch { /* discovery best-effort — scan lens degrades to its deep anchor */ }
  const routes = planLensRoutes(ULTRA_LENSES, [...deepPool, ...scanPool], { perLens })
  const passes = routes.map((r) => `${r.model}::${r.lens}`)
  process.stderr.write(`ultrareview: FIND — ${ULTRA_LENSES.length} lenses × ≤${perLens} reviewers = ${passes.length} passes (deep:${deepPool.length} scan:${scanPool.length}), ${concurrency}/provider\n`)
  const found = (await pool(passes, concurrency, runLensPass)).flat().filter(Boolean)

  // Apply unified quality gates to ultrareview findings.
  const gatedFound = applyHallucinationGate(found, { repoRoot, record: true })

  let verifiedFindings = gatedFound
  let refuted = []
  let checks = []
  if (!process.argv.includes("--no-verify") && gatedFound.length) {
    process.stderr.write(`ultrareview: VERIFY — refuting ${gatedFound.length} findings…\n`)
    const vshaped = gatedFound.map((f) => ({ severity: f.severity, title: f.title, file: f.file, line_start: f.line_start ?? f.line, body: f.body ?? "", recommendation: f.recommendation, lineages: [f.by] }))
    checks = await poolVerifyFindings(vshaped)
    verifiedFindings = gatedFound.filter((f, i) => (checks[i]?.verdict ?? "unverified") !== "false-positive")
    refuted = gatedFound.filter((f, i) => (checks[i]?.verdict) === "false-positive").map((f, i) => ({ ...f }))
  }

  recordReputationFromVerification(gatedFound, checks, { errorCategory: "verify" })

  process.stderr.write(`ultrareview: DEDUPE — ${verifiedFindings.length} verified findings\n`)
  const issues = synthesizeUltrareview(verifiedFindings)
  const sev = (s) => issues.filter((i) => i.severity === s).length
  const report = {
    mode: "ultrareview",
    pipeline: "find → verify → dedupe",
    lenses: ULTRA_LENSES.map((l) => l.key),
    fleet: passes,
    summary: `${issues.length} issue(s) found — ${sev("critical")} critical / ${sev("high")} high / ${sev("medium")} medium / ${sev("low")} low (${found.length} raw findings, ${verifiedFindings.length} verified, ${refuted.length} refuted)`,
    issues,
    refuted_dropped: refuted,
  }
  console.log(JSON.stringify(report, null, 2))
  process.exit(0)
}

function runOne(m, opts = {}) {
  return new Promise((resolve) => {
    const worker = workerForModel(m)
    const args = [worker, m, "--repo-root", repoRoot, "--focus", focus]
    const lineage = lineageForModel(m)
    if (lineage) args.push("--lineage", lineage)
    if (base) args.push("--base", base)
    if (text) args.push("--text", text)
    if (input) args.push("--input", input)
    if (target) args.push("--target", target); if (full) args.push("--full")
    if (mode) args.push("--mode", mode)
    if (thinkingCheck) args.push("--thinking-check", thinkingCheck)
    if (maxTokens) args.push("--max-tokens", maxTokens)
    if (noDeepwiki) args.push("--no-deepwiki")
    if (timeout) args.push("--timeout", timeout)
    const safe = m.replace(/[/:]/g, "_")
    process.stderr.write(`  → ${m} …\n`)
    let out = ""
    const task = spawnTask("node", args, { cwd: process.cwd() })
    task.start({
      signal: null,
      appendOutput(chunk) { out += chunk },
      async settle() {
        writeFileSync(join(OUT, `${safe}.json`), out)
        const v = verifySchemaAndHardCap(out, m)
        v.requested = m
        v.model = v.model || m
        if (opts.panel_slot != null) v.panel_slot = opts.panel_slot
        const failureKind = isChainFailure(v) ? " chain-failure" : ""
        process.stderr.write(`  ✓${failureKind} ${m} → ${v.verdict} (${(v.findings || []).length} findings) [served ${v.model}]\n`)
        resolve(v)
      },
    }).catch((e) => {
      // Surface spawn failure as a failed verdict so the panel can continue/backfill.
      const v = { verdict: "needs-attention", summary: `spawn failed: ${e?.message || e}`, findings: [], next_steps: [] }
      v.requested = m
      v.model = m
      if (opts.panel_slot != null) v.panel_slot = opts.panel_slot
      resolve(v)
    })
  })
}

// Concurrency is capped PER PROVIDER, not globally. The transient "fetch failed"
// came from overloading ONE shared aggregator (opencode-go); independent backends
// (ollama-cloud, minimax, kimi-for-coding) have their own capacity. So each
// provider runs up to `perProvider` workers concurrently and the providers run in
// parallel — total peak = perProvider × (distinct providers in the panel), which
// is much faster when the selected lineages span direct providers. providerOf = prefix
// before the first "/" (e.g. "opencode-go/deepseek-v4-pro" → "opencode-go").
async function pool(items, perProvider, fn) {
  const modelRef = (item) => (typeof item === "string" ? item : item.m)
  const providerOf = (item) => String(modelRef(item)).split("/")[0]
  const idxByProvider = new Map()
  items.forEach((item, idx) => {
    const p = providerOf(item)
    if (!idxByProvider.has(p)) idxByProvider.set(p, [])
    idxByProvider.get(p).push(idx)
  })
  const res = []
  await Promise.all(
    [...idxByProvider.values()].map(async (idxs) => {
      let i = 0
      await Promise.all(
        Array.from({ length: Math.min(perProvider, idxs.length) }, async () => {
          while (i < idxs.length) {
            const j = idxs[i++]
            res[j] = await fn(items[j])
          }
        }),
      )
    }),
  )
  return res
}

// Fail LOUD instead of silently reviewing an irrelevant diff. If no document
// (--text/--input) and no commit range (--base) was given, and the working tree
// has no diff, there is nothing meaningful to review — a bare arg only STEERS a
// diff (via --focus), it does not supply one. Tell the caller how to aim it.
if (!text && !input && !base) {
  let diff = ""
  try {
    diff = execFileSync("git", ["diff"], { cwd: repoRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] }).trim()
    if (!diff) diff = execFileSync("git", ["diff", "--cached"], { cwd: repoRoot, encoding: "utf8", maxBuffer: 64 * 1024 * 1024, stdio: ["ignore", "pipe", "ignore"] }).trim()
  } catch {
    /* git absent / not a repo — let the worker surface its own error */
  }
  if (!diff) {
    // A bare positional can't STEER a diff that doesn't exist — by elimination
    // it IS the content to review. Promote it to --text (forgiving: prose/design
    // reviews commonly omit the --text flag, e.g. via `$ARGUMENTS` passthrough).
    if (positionals.length) {
      text = positionals.join(" ")
      focus = flag("--focus", null) || "(none)"
      process.stderr.write(
        "redteam: no diff to steer — treating the bare argument as --text prose to review.\n",
      )
    } else {
      process.stderr.write(
        "redteam: nothing to review — no working-tree diff, and no --text/--input/--base given.\n" +
        '  Review prose or a subsystem not in the diff:  --text "<your question + code/config>"\n' +
        "  Review a written doc/ADR:                     --input <path>\n" +
        "  Review a commit range:                        --base <ref>\n" +
        "  A bare argument is treated as --focus — it STEERS a diff review, it does not supply one.\n",
      )
      process.exit(2)
    }
  }
}

process.stderr.write(
  `redteam: random ${models.length} lineages [${[...new Set(models.map(groupOf))].join("+")}]\n`,
)
const initialJobs = models.map((m, i) => ({ m, panel_slot: i + 1 }))
let verdicts = await pool(initialJobs, concurrency, ({ m, panel_slot }) => runOne(m, { panel_slot }))
const lineageAttempts = verdicts.map((v) =>
  summarizeLineageAttempt(v, { panel_slot: v.panel_slot, backfill_round: 0 }),
)

// Apply unified quality gates (hallucination + reputation) to normal panel verdicts.
// Pass any per-verdict metadata we have (latency, tokens, error category) so reputation
// recording can be richer.
verdicts = gateVerdictRows(verdicts, {
  repoRoot,
  record: true,
  meta: { errorCategory: "review" },
})

// Automatic backfill: a lineage whose WHOLE chain failed (every provider hop 404/503/
// quota) returns verdict:"error" — a hole in the panel. Don't ship N-k responses; walk
// the lineage pool in order for the next untried lineage per failed panel slot (not a fresh
// random draw). Re-run until we have `panelTarget` satisfied slots or the pool is
// exhausted. Bounded by pool size + a hard round cap so a global outage can't loop
// forever. Off for --all-files and when an explicit --models set was pinned.
const wantBackfill = !allFiles && !explicitModels
if (wantBackfill) {
  const target = panelTarget
  const tried = new Set(models)
  let rounds = 0
  const MAX_BACKFILL_ROUNDS = lineagePool.length + 2
  const slotOk = isPanelSlotSatisfied
  while (verdicts.filter(slotOk).length < target && rounds < MAX_BACKFILL_ROUNDS) {
    rounds++
    const failing = verdicts
      .map((v, idx) => ({ v, panel_slot: v.panel_slot ?? idx + 1 }))
      .filter(({ v }) => !slotOk(v))
    const deficit = failing.length
    if (deficit === 0) break
    const usedGroups = new Set(verdicts.filter(slotOk).map((v) => groupOf(v.requested ?? v.model)))
    const replacements = planBackfillReplacements(lineagePool, tried, deficit, usedGroups, groupOf)
    if (replacements.length === 0) break
    const backfillJobs = replacements.map((m, i) => {
      tried.add(m)
      const panel_slot = failing[i]?.panel_slot ?? target + i + 1
      return { m, panel_slot }
    })
    process.stderr.write(
      `redteam: backfill round ${rounds} — ${deficit} failed slot(s), trying ${backfillJobs.map((j) => `${j.panel_slot}:${j.m}`).join(", ")}\n`,
    )
    let more = await pool(backfillJobs, concurrency, ({ m, panel_slot }) => runOne(m, { panel_slot }))
    more = gateVerdictRows(more, { repoRoot, record: true, meta: { errorCategory: "review" } })
    for (const v of more) {
      lineageAttempts.push(summarizeLineageAttempt(v, { panel_slot: v.panel_slot, backfill_round: rounds }))
    }
    const fresh = more.filter(slotOk)
    const stillFailed = more.filter((v) => !slotOk(v))
    const unfilledFailures = failing.slice(replacements.length).map(({ v }) => v)
    verdicts = mergeBackfillRound({ verdicts, satisfied: slotOk, fresh, stillFailed, unfilledFailures })
  }
  const got = verdicts.filter(slotOk).length
  if (got < target) {
    process.stderr.write(`redteam: backfill exhausted — ${got}/${target} lineages returned a verdict (no more working lineages)\n`)
  }
  const failedAttempts = lineageAttempts.filter((a) => a.failed)
  if (failedAttempts.length) {
    process.stderr.write(
      `redteam: lineage failures (${failedAttempts.length}): ${failedAttempts.map((a) => `slot ${a.panel_slot} ${a.requested || a.model}→${a.verdict}`).join(", ")}\n`,
    )
  }
}

const successfulVerdicts = verdicts.filter(isPanelSlotSatisfied)

// UNION merge — keep every finding; merge only identical; attribute lineages.
const union = []
for (const v of successfulVerdicts) {
  for (const f of v.findings || []) {
    const key = `${f.file}:${f.line_start}:${(f.title || "").slice(0, 60).toLowerCase()}`
    const hit = union.find((x) => x._key === key)
    if (hit) {
      hit.lineages.push(v.model)
      hit.confidence = Math.max(hit.confidence || 0, f.confidence || 0)
    } else {
      union.push({ _key: key, ...f, lineages: [v.model] })
    }
  }
}
const rank = { critical: 0, high: 1, medium: 2, low: 3 }
union.sort(
  (a, b) => (rank[a.severity] ?? 9) - (rank[b.severity] ?? 9) || b.lineages.length - a.lineages.length,
)

// ── --verify: adversarial refutation pass ───────────────────────────────────
// Pick a refuter NOT among the finding's raisers (avoid confirmation bias). A
// finding is dropped ONLY on an explicit "false-positive" verdict; verifier
// errors/timeouts fail OPEN (kept, marked unverified) so a real bug is never
// silently lost to a flaky refuter. (VERIFIER_POOL is defined earlier so the
// --all-files block, which exits before this point, can also refute.)
function pickVerifier(f) {
  if (verifierOverride) return verifierOverride
  const raisers = new Set(f.lineages || [])
  return VERIFIER_POOL.find((m) => !raisers.has(m)) || VERIFIER_POOL[0]
}

function poolVerifyFindings(findings) {
  const jobs = findings.map((f) => ({ m: pickVerifier(f), finding: f }))
  return pool(jobs, concurrency, (j) => verifyFinding(j.finding, j.m))
}
function verifyFinding(f, verifierModel = null) {
  const vmodel = verifierModel || pickVerifier(f)
  const worker = workerForModel(vmodel)
  const text =
    `A prior reviewer raised the FINDING below. Verify whether it is REAL or a FALSE POSITIVE by READING the cited code with your tools.\n\n` +
    `severity: ${f.severity}\ntitle: ${f.title}\nfile: ${f.file}:${f.line_start ?? ""}\nbody: ${f.body ?? ""}\nrecommendation: ${f.recommendation ?? ""}`
  const args = [worker, vmodel, "--repo-root", repoRoot, "--mode", "verify", "--text", text, "--no-deepwiki", "--timeout", "150000"]
  const lineage = lineageForModel(vmodel)
  if (lineage) args.push("--lineage", lineage)
  if (thinkingCheck) args.push("--thinking-check", thinkingCheck)
  if (maxTokens) args.push("--max-tokens", maxTokens)
  return new Promise((resolve) => {
    let out = ""
    const task = spawnTask("node", args, { cwd: process.cwd() })
    task.start({
      signal: null,
      appendOutput(chunk) { out += chunk },
      async settle() {
        let v = null
        try { v = JSON.parse(out.trim().split("\n").pop()) } catch {}
        const verdict = v?.verdict === "false-positive" ? "false-positive" : v?.verdict === "real" ? "real" : "unverified"
        process.stderr.write(`  ⚖ [${verdict}] ${(f.title || "").slice(0, 52)} ← ${vmodel}\n`)
        resolve({ verdict, confidence: v?.confidence ?? null, reason: v?.reason ?? null, verifier: vmodel })
      },
    }).catch(() => resolve({ verdict: "unverified", verifier: vmodel }))
  })
}

function workerForModel(_model) {
  // Single backend: every lineage is driven by the Moonshot agent-core runner.
  return WORKERS.moonshot
}

function lineageForModel(model) {
  if (LINEAGES.includes(model)) return model
  return inferLineage(model)
}

const confirmed = []
const refuted = []
if (verify && union.length) {
  process.stderr.write(`redteam: --verify → refuting ${union.length} findings…\n`)
  const checks = await poolVerifyFindings(union)
  union.forEach((f, i) => {
    f._verify = checks[i] || { verdict: "unverified" }
    ;(f._verify.verdict === "false-positive" ? refuted : confirmed).push(f)
  })
} else {
  confirmed.push(...union)
}

const kept = confirmed
const attribution = buildPanelAttribution(successfulVerdicts)
const report = {
  mode: "random",
  backend,
  ...attribution,
  lineage_attempts: lineageAttempts,
  groups: [...new Set(attribution.panel.map(groupOf))],
  ...(verify ? { verify_summary: `${confirmed.length} confirmed / ${refuted.length} refuted of ${union.length}` } : {}),
  verdict: computePanelVerdict(verdicts, kept, {
    targetCount: wantBackfill ? panelTarget : undefined,
    satisfiedCount: wantBackfill ? successfulVerdicts.length : undefined,
    verified: !!verify,
  }),
  harness_failures: verdicts
    .filter((v) => isHarnessFailureVerdict(v))
    .map((v) => ({
      panel_slot: v.panel_slot ?? null,
      model: v.model,
      requested: v.requested,
      verdict: v.verdict,
      summary: v.summary,
      _auto: v._auto,
    })),
  findings_union: kept.map(({ _key, ...f }) => f),
  ...(verify ? { refuted_dropped: refuted.map(({ _key, ...f }) => f) } : {}),
}
completePanelJob(repoRoot, basename(OUT), report)
console.log(JSON.stringify(report, null, 2))
process.exit(0)
