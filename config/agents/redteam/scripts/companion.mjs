#!/usr/bin/env node
/**
 * companion.mjs — status / result / cancel / setup for redteam panel jobs.
 *
 * Purpose: Codex-style operator surface for background runs (no polling in chat).
 * Consumer: commands/status.md, result.md, cancel.md, setup.md.
 */
import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import {
  cancelPanelJob,
  findPanelJob,
  formatElapsed,
  listPanelJobs,
  loadPanelResult,
  readPanelLog,
} from "./lib/job-state.mjs"
import { validateModelsPolicy } from "./model-policy.mjs"
import { inspectProviderStatus } from "./model-discovery.mjs"

const HERE = dirname(fileURLToPath(import.meta.url))
const PLUGIN = join(HERE, "..")
const MODELS_JSON = join(PLUGIN, "models.json")
const MODEL_BENCH_JSON = join(PLUGIN, "model-bench.json")
const STATUS_POLL_INTERVAL_MS = 2_000

const sessionId = () =>
  process.env.CLAUDE_CODE_SESSION_ID || process.env.CODEX_COMPANION_SESSION_ID || null

function flag(name, def = null) {
  const i = process.argv.indexOf(name)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def
}

function repoRoot() {
  return flag("--repo-root", process.cwd())
}

function firstPositionalArg() {
  const args = process.argv.slice(3)
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]
    if (arg.startsWith("-")) {
      if (arg === "--repo-root" || arg === "--timeout-ms" || arg === "--poll-interval-ms") i++
      continue
    }
    return arg
  }
  return null
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function handleSetup() {
  const checks = []
  const next = []
  checks.push({ name: "node", ok: true, detail: process.version })
  checks.push({ name: "panel.mjs", ok: existsSync(join(HERE, "panel.mjs")) })
  checks.push({ name: "runner.mjs", ok: existsSync(join(HERE, "runner.mjs")) })
  checks.push({ name: "command:architect", ok: existsSync(join(PLUGIN, "commands", "architect.md")) })
  checks.push({ name: "command:provider-status", ok: existsSync(join(PLUGIN, "commands", "provider-status.md")) })
  checks.push({ name: "prompt:route", ok: existsSync(join(PLUGIN, "prompts", "route-pdd.md")) })
  try {
    const bench = JSON.parse(readFileSync(MODEL_BENCH_JSON, "utf8"))
    const lanes = bench?.lanes && typeof bench.lanes === "object" ? bench.lanes : {}
    const laneCount = Object.keys(lanes).length
    const passed = Object.values(lanes).flatMap((rows) => Array.isArray(rows) ? rows : []).filter((row) => row?.pass === true).length
    checks.push({
      name: "model-bench.json",
      ok: true,
      detail: `${laneCount} lanes, ${passed} passed lane entries`,
    })
    if (passed === 0) next.push("Run /redteam:bench --run --write to enable bench-backed lane routing.")
  } catch (err) {
    checks.push({ name: "model-bench.json", ok: false, detail: err?.message ?? String(err) })
  }
  try {
    const cfg = JSON.parse(readFileSync(MODELS_JSON, "utf8"))
    const policy = validateModelsPolicy(cfg)
    checks.push({
      name: "models.json",
      ok: policy.ok,
      detail: policy.ok ? `${policy.lineages.length} lineage policies` : policy.errors.join("; "),
    })
  } catch (err) {
    checks.push({ name: "models.json", ok: false, detail: err?.message ?? String(err) })
  }
  const ready = checks.every((c) => c.ok)
  if (!ready) next.push("Fix missing harness files before running /redteam:review.")
  if (ready) next.push("Ready. Use /redteam:review; background runs → /redteam:status.")
  const json = process.argv.includes("--json")
  const lines = [
    ready ? "redteam: ready" : "redteam: not ready",
    ...checks.map((c) => `  ${c.ok ? "✓" : "✗"} ${c.name}${c.detail ? ` — ${c.detail}` : ""}`),
    "",
    ...next.map((n) => `→ ${n}`),
  ]
  if (json) console.log(JSON.stringify({ ready, checks, next }, null, 2))
  else console.log(lines.join("\n"))
}

function providerFromModel(model) {
  const slash = String(model || "").indexOf("/")
  return slash >= 0 ? String(model).slice(0, slash) : ""
}

function loadProviderBenchSummary() {
  const summary = new Map()
  try {
    const bench = JSON.parse(readFileSync(MODEL_BENCH_JSON, "utf8"))
    for (const rows of Object.values(bench?.lanes || {})) {
      if (!Array.isArray(rows)) continue
      for (const row of rows) {
        const provider = providerFromModel(row?.model)
        if (!provider) continue
        const current = summary.get(provider) || { bench_pass: 0, bench_fail: 0 }
        if (row?.pass === true) current.bench_pass += 1
        else current.bench_fail += 1
        summary.set(provider, current)
      }
    }
  } catch {
    /* bench evidence is optional */
  }
  return summary
}

function mergeProviderBench(rows) {
  const bench = loadProviderBenchSummary()
  return rows.map((row) => ({
    ...row,
    ...(bench.get(row.provider) || { bench_pass: 0, bench_fail: 0 }),
  }))
}

function renderProviderStatusTable(rows) {
  if (!rows.length) return "No providers found in Kimi config.\n"
  const header = "| provider | live | aliases | live aliases | bench | lineages | detail |"
  const sep = "|---|---|---:|---:|---:|---|---|"
  const body = rows.map((row) => {
    const bench = `${row.bench_pass}/${row.bench_pass + row.bench_fail}`
    const lineages = row.lineages.length ? row.lineages.join(",") : "-"
    const detail = row.error || row.catalog_url || "-"
    return `| \`${row.provider}\` | ${row.live} | ${row.declared_aliases} | ${row.live_declared_aliases} | ${bench} | ${lineages} | ${detail} |`
  })
  return [header, sep, ...body, ""].join("\n")
}

async function handleProviderStatus() {
  const json = process.argv.includes("--json")
  const live = !process.argv.includes("--no-live")
  const timeoutMs = Math.max(100, Number.parseInt(flag("--timeout-ms", "8000"), 10) || 8000)
  const rows = mergeProviderBench(await inspectProviderStatus({ live, timeoutMs }))
  if (json) console.log(JSON.stringify({ live, providers: rows }, null, 2))
  else {
    const offline = live ? "" : "Live catalog checks skipped (--no-live).\n\n"
    console.log(offline + renderProviderStatusTable(rows))
  }
}

function renderStatusTable(jobs) {
  if (!jobs.length) return "No redteam jobs for this workspace/session.\n"
  const header = "| job | kind | status | elapsed | summary | follow-up |"
  const sep = "|---|---|---|---|---|---|"
  const rows = jobs.map((j) => {
    const follow =
      j.status === "running"
        ? `/redteam:cancel ${j.id}`
        : j.status === "completed"
          ? `/redteam:result ${j.id}`
          : `/redteam:status ${j.id}`
    return `| \`${j.id}\` | ${j.kind} | ${j.status} | ${formatElapsed(j)} | ${(j.summary || j.verdict || "—").slice(0, 40)} | ${follow} |`
  })
  return [header, sep, ...rows, ""].join("\n")
}

function renderLogBlock(job) {
  const lines = readPanelLog(job, { maxLines: 80 })
  if (!lines.length) return ""
  return ["", "Recent trace:", "```text", ...lines, "```"].join("\n")
}

function stillRunningNotice(timeoutMs, ref = null) {
  const target = ref ? `job ${ref}` : "active jobs"
  const seconds = timeoutMs > 0 ? Math.max(1, Math.ceil(timeoutMs / 1000)) : 0
  return `Still running after ${seconds}s waiting for ${target}. Use /redteam:status${ref ? ` ${ref}` : ""} --wait or /redteam:result <job-id> when done.`
}

async function waitForStatus(root, ref, { timeoutMs, pollIntervalMs }) {
  const started = Date.now()
  let last = null
  while (timeoutMs === null || Date.now() - started <= timeoutMs) {
    if (ref) {
      const job = findPanelJob(root, ref)
      last = job ? { job, result: loadPanelResult(job) } : null
      if (!job || job.status !== "running") return { ...last, waitTimedOut: false }
    } else {
      const jobs = listPanelJobs(root, { sessionId: sessionId() })
      last = { jobs }
      if (!jobs.some((j) => j.status === "running")) return { ...last, waitTimedOut: false }
    }
    const remaining = timeoutMs === null ? pollIntervalMs : Math.max(0, timeoutMs - (Date.now() - started))
    await sleep(Math.min(pollIntervalMs, remaining))
  }
  return { ...last, waitTimedOut: true }
}

async function handleStatus() {
  const root = repoRoot()
  const ref = firstPositionalArg()
  const json = process.argv.includes("--json")
  const wait = process.argv.includes("--wait")
  const timeoutFlag = flag("--timeout-ms", null)
  const timeoutMs = timeoutFlag === null ? null : Math.max(0, Number.parseInt(timeoutFlag, 10) || 0)
  const pollIntervalMs = Math.max(100, Number.parseInt(flag("--poll-interval-ms", String(STATUS_POLL_INTERVAL_MS)), 10) || STATUS_POLL_INTERVAL_MS)

  if (ref) {
    const waited = wait ? await waitForStatus(root, ref, { timeoutMs, pollIntervalMs }) : null
    const job = waited?.job ?? findPanelJob(root, ref)
    if (!job) {
      console.log(`No job matching "${ref}".`)
      process.exit(1)
    }
    const payload = { job, result: loadPanelResult(job), trace: readPanelLog(job, { maxLines: 80 }), waitTimedOut: Boolean(waited?.waitTimedOut) }
    if (json) console.log(JSON.stringify(payload, null, 2))
    else {
      console.log(
        [
          waited?.waitTimedOut && job.status === "running" && timeoutMs !== null ? stillRunningNotice(timeoutMs, ref) : "",
          `job: ${job.id}`,
          `status: ${job.status}`,
          `kind: ${job.kind}`,
          `elapsed: ${formatElapsed(job)}`,
          `out: ${job.outDir}`,
          job.logFile ? `log: ${job.logFile}` : "",
          job.status === "completed" ? `result: /redteam:result ${job.id}` : "",
          renderLogBlock(job),
        ]
          .filter(Boolean)
          .join("\n"),
      )
    }
    return
  }

  const waited = wait ? await waitForStatus(root, null, { timeoutMs, pollIntervalMs }) : null
  const jobs = waited?.jobs ?? listPanelJobs(root, { sessionId: sessionId() })
  if (json) console.log(JSON.stringify({ jobs, waitTimedOut: Boolean(waited?.waitTimedOut) }, null, 2))
  else {
    const notice = waited?.waitTimedOut && timeoutMs !== null && jobs.some((j) => j.status === "running")
      ? `${stillRunningNotice(timeoutMs)}\n\n`
      : ""
    console.log(notice + renderStatusTable(jobs))
  }
}

function handleResult() {
  const root = repoRoot()
  const ref = process.argv[3] && !process.argv[3].startsWith("-") ? process.argv[3] : null
  const job = findPanelJob(root, ref)
  if (!job) {
    console.log(ref ? `No job matching "${ref}".` : "No job id. Usage: /redteam:result <job-id>")
    process.exit(1)
  }
  const result = loadPanelResult(job)
  const json = process.argv.includes("--json")
  if (json) console.log(JSON.stringify({ job, result }, null, 2))
  else if (!result) console.log(`Job ${job.id} (${job.status}) has no stored panel-result.json yet.`)
  else console.log(JSON.stringify(result, null, 2))
}

function handleCancel() {
  const root = repoRoot()
  const ref = process.argv[3] && !process.argv[3].startsWith("-") ? process.argv[3] : null
  if (!ref) {
    console.log("Usage: /redteam:cancel <job-id>")
    process.exit(1)
  }
  const out = cancelPanelJob(root, ref)
  if (!out.ok) {
    console.log(out.error)
    process.exit(1)
  }
  console.log(`Cancelled job ${out.job.id}.`)
}

const sub = process.argv[2]
switch (sub) {
  case "setup":
    handleSetup()
    break
  case "provider-status":
    await handleProviderStatus()
    break
  case "status":
    await handleStatus()
    break
  case "result":
    handleResult()
    break
  case "cancel":
    handleCancel()
    break
  default:
    console.error("Usage: companion.mjs <setup|provider-status|status|result|cancel> [args] [--repo-root dir] [--json]")
    process.exit(2)
}
