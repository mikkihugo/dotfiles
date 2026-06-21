/**
 * Workspace-scoped job registry for background redteam panel runs.
 *
 * Purpose: power /redteam:status, :result, :cancel like Codex companion.
 * Consumer: panel.mjs (register/complete), companion.mjs (read/cancel).
 */
import { createHash } from "node:crypto"
import { existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { basename, join } from "node:path"

const STATE_ROOT = join(homedir(), ".cache", "redteam", "jobs")
const MAX_JOBS = 50

export function redactTrace(text) {
  return String(text)
    .replace(/\b([A-Za-z0-9_]*API_KEY)\b([=:]\s*["']?)([^"'\s]+)/g, "$1$2<redacted>")
    .replace(/\b(Bearer|token|api[_-]?key)\s+([A-Za-z0-9._~+/=-]{16,})/gi, "$1 <redacted>")
    .replace(/("api[_-]?key"\s*:\s*")([^"]+)(")/gi, "$1<redacted>$3")
}

/**
 * Resolve per-repo job store directory.
 *
 * Purpose: isolate jobs by workspace like Codex companion state.
 * Consumer: all job-state exports.
 */
export function resolveJobsDir(repoRoot) {
  let canonical = repoRoot
  try {
    canonical = realpathSync(repoRoot)
  } catch {
    canonical = repoRoot
  }
  const slug = (basename(canonical) || "workspace").replace(/[^a-zA-Z0-9._-]+/g, "-") || "workspace"
  const hash = createHash("sha256").update(canonical).digest("hex").slice(0, 16)
  return join(STATE_ROOT, `${slug}-${hash}`)
}

function jobsFile(repoRoot) {
  return join(resolveJobsDir(repoRoot), "jobs.json")
}

function loadJobs(repoRoot) {
  const file = jobsFile(repoRoot)
  if (!existsSync(file)) return []
  try {
    const rows = JSON.parse(readFileSync(file, "utf8"))
    return Array.isArray(rows) ? rows : []
  } catch {
    return []
  }
}

function saveJobs(repoRoot, rows) {
  const dir = resolveJobsDir(repoRoot)
  mkdirSync(dir, { recursive: true })
  writeFileSync(jobsFile(repoRoot), JSON.stringify(rows.slice(0, MAX_JOBS), null, 2), "utf8")
}

/**
 * Register a new panel run at startup.
 *
 * Purpose: give Claude a stable job id for status/result after background launch.
 * Consumer: panel.mjs.
 */
export function registerPanelJob(repoRoot, job) {
  const rows = loadJobs(repoRoot).filter((j) => j.id !== job.id)
  const row = {
    id: job.id,
    status: "running",
    pid: job.pid,
    outDir: job.outDir,
    logFile: job.logFile ?? null,
    sessionId: job.sessionId ?? null,
    kind: job.kind ?? "panel",
    repoRoot,
    argv: job.argv ?? [],
    startedAt: new Date().toISOString(),
    completedAt: null,
    summary: null,
    verdict: null,
    resultPath: null,
    exitCode: null,
  }
  rows.unshift(row)
  saveJobs(repoRoot, rows)
  return row
}

/**
 * Mark a panel job completed with the merged JSON report.
 *
 * Purpose: persist final output for /redteam:result without polling.
 * Consumer: panel.mjs.
 */
export function completePanelJob(repoRoot, jobId, report, { exitCode = 0 } = {}) {
  const existing = loadJobs(repoRoot).find((j) => j.id === jobId)
  const resultPath = join(existing?.outDir ?? "", "panel-result.json")
  if (existing?.outDir && report) {
    try {
      writeFileSync(resultPath, JSON.stringify(report, null, 2), "utf8")
    } catch {
      /* best-effort */
    }
  }
  const rows = loadJobs(repoRoot).map((j) =>
    j.id === jobId
      ? {
          ...j,
          status: exitCode === 0 ? "completed" : "failed",
          completedAt: new Date().toISOString(),
          summary: report?.verdict ? String(report.verdict) : j.summary,
          verdict: report?.verdict ?? null,
          resultPath: existing?.outDir ? resultPath : j.resultPath,
          exitCode,
          pid: null,
        }
      : j,
  )
  saveJobs(repoRoot, rows)
}

/**
 * Mark a panel job failed.
 *
 * Purpose: record harness errors for status/result surfaces.
 * Consumer: panel.mjs and companion.mjs cancel path.
 */
export function failPanelJob(repoRoot, jobId, message, exitCode = 1) {
  const rows = loadJobs(repoRoot).map((j) =>
    j.id === jobId
      ? {
          ...j,
          status: "failed",
          completedAt: new Date().toISOString(),
          summary: String(message || "failed").slice(0, 200),
          exitCode,
          pid: null,
        }
      : j,
  )
  saveJobs(repoRoot, rows)
}

function pidAlive(pid) {
  if (!pid || pid <= 0) return false
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

function refreshJob(row) {
  if (row.status !== "running") return row
  if (pidAlive(row.pid)) return row
  const resultPath = join(row.outDir || "", "panel-result.json")
  if (existsSync(resultPath)) {
    try {
      const report = JSON.parse(readFileSync(resultPath, "utf8"))
      return {
        ...row,
        status: "completed",
        completedAt: row.completedAt || new Date().toISOString(),
        verdict: report.verdict ?? row.verdict,
        summary: report.verdict ?? row.summary,
        resultPath,
        pid: null,
      }
    } catch {
      return { ...row, status: "failed", summary: "stale run (no result)", pid: null }
    }
  }
  const partial = row.outDir && existsSync(row.outDir)
    ? readdirSync(row.outDir).filter((n) => n.endsWith(".json")).length
    : 0
  return {
    ...row,
    status: partial > 0 ? "completed" : "failed",
    summary: partial > 0 ? `${partial} lineage file(s)` : "exited without result",
    pid: null,
  }
}

/**
 * List jobs for a workspace, optionally filtered by Claude session id.
 *
 * Purpose: /redteam:status table source.
 * Consumer: companion.mjs.
 */
export function listPanelJobs(repoRoot, { sessionId = null, all = false } = {}) {
  let rows = loadJobs(repoRoot).map(refreshJob)
  if (!all && sessionId) rows = rows.filter((j) => j.sessionId === sessionId)
  saveJobs(repoRoot, rows)
  return rows
}

/**
 * Find one job by id prefix or exact match.
 *
 * Purpose: /redteam:result and /redteam:cancel lookup.
 * Consumer: companion.mjs.
 */
export function findPanelJob(repoRoot, ref) {
  const rows = listPanelJobs(repoRoot, { all: true })
  if (!ref) return rows[0] ?? null
  return rows.find((j) => j.id === ref || j.id.startsWith(ref)) ?? null
}

/**
 * Cancel a running panel job by pid.
 *
 * Purpose: /redteam:cancel.
 * Consumer: companion.mjs.
 */
export function cancelPanelJob(repoRoot, ref) {
  const job = findPanelJob(repoRoot, ref)
  if (!job) return { ok: false, error: `no job matching "${ref}"` }
  if (job.status !== "running" || !pidAlive(job.pid)) {
    return { ok: false, error: `job ${job.id} is not running` }
  }
  try {
    process.kill(job.pid, "SIGTERM")
  } catch (err) {
    return { ok: false, error: err?.message ?? String(err) }
  }
  failPanelJob(repoRoot, job.id, "cancelled", 130)
  return { ok: true, job: findPanelJob(repoRoot, job.id) }
}

/**
 * Load stored panel result JSON for a job.
 *
 * Purpose: /redteam:result payload.
 * Consumer: companion.mjs.
 */
export function loadPanelResult(job) {
  if (!job) return null
  const path = job.resultPath || join(job.outDir || "", "panel-result.json")
  if (!existsSync(path)) return null
  try {
    return JSON.parse(readFileSync(path, "utf8"))
  } catch {
    return null
  }
}

/**
 * Read recent job log lines.
 *
 * Purpose: show live panel/agent progress in /redteam:status without polling task streams.
 * Consumer: companion.mjs.
 */
export function readPanelLog(job, { maxLines = 80 } = {}) {
  if (!job?.logFile || !existsSync(job.logFile)) return []
  try {
    return redactTrace(readFileSync(job.logFile, "utf8")).split(/\r?\n/).filter(Boolean).slice(-maxLines)
  } catch (err) {
    return [`<log unavailable: ${err?.message ?? String(err)}>`]
  }
}

/**
 * Format elapsed ms for status display.
 *
 * Purpose: human-readable status table.
 * Consumer: companion.mjs.
 */
export function formatElapsed(job) {
  const start = Date.parse(job.startedAt || "")
  const end = job.completedAt ? Date.parse(job.completedAt) : Date.now()
  if (!start) return "—"
  const sec = Math.max(0, Math.round((end - start) / 1000))
  if (sec < 60) return `${sec}s`
  return `${Math.floor(sec / 60)}m${sec % 60}s`
}
