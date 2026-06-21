// provider-gate.mjs — cross-process, per-provider concurrency gate.
//
// WHY: every redteam invocation (single-lineage /redteam:<model>, the panel,
// AND every concurrent Claude session) spawns runner.mjs, each of
// which boots its own throwaway opencode server. Nothing capped how many hit one
// provider at once, so opencode-go's shared rate bucket got buried under load and
// surfaced as "fetch failed"/timeout. panel's in-process pool() only capped a
// SINGLE panel process — it could not see single-lineage runs or other sessions.
//
// This gate lives in the worker (the one chokepoint all paths funnel through) and
// coordinates over the FILESYSTEM, so the cap is GLOBAL across processes/sessions:
// at most `limit` slots per provider, host-wide.
//
// Mechanism: a counting semaphore built from `limit` distinct slot files created
// with O_EXCL (atomic "create only if absent"). Holding a slot = owning its file.
// Crashed holders are reaped by PID-liveness (process.kill(pid,0) → ESRCH) so a
// dead worker never deadlocks the bucket; a stale-age fallback covers PID reuse.
import { mkdirSync, openSync, closeSync, writeSync, readFileSync, unlinkSync, readdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const HERE = dirname(fileURLToPath(import.meta.url))
const LOCK_ROOT = process.env.REDTEAM_SLOT_DIR || join(HERE, "..", ".locks")

export const PROVIDER_CONCURRENCY = Number.parseInt(process.env.REDTEAM_PROVIDER_CONCURRENCY || "2", 10)
// A slow reasoning model (671b/675b) legitimately holds a slot for minutes, so the
// age fallback is generous; PID-liveness is the real reaper. (ms)
const STALE_MS = Number.parseInt(process.env.REDTEAM_SLOT_STALE_MS || String(20 * 60 * 1000), 10)
// How long to queue for a slot before giving up. (ms)
const ACQUIRE_TIMEOUT_MS = Number.parseInt(process.env.REDTEAM_SLOT_ACQUIRE_MS || String(20 * 60 * 1000), 10)

const isAlive = (pid) => {
  if (!Number.isInteger(pid) || pid <= 0) return false
  try {
    process.kill(pid, 0) // signal 0 = liveness probe, never actually signals
    return true
  } catch (e) {
    // EPERM = process exists but is owned by another user and we cannot signal it.
    // Treat as alive — intentional for same-user operation where EPERM never occurs,
    // so this conservatively avoids reaping a slot we cannot verify as dead.
    return e?.code === "EPERM"
  }
}

/**
 * PURE: decide whether a slot file's holder is dead/stale and may be reaped.
 * `entry` is the parsed {pid, ts} (or null if unreadable/garbage). Unreadable or
 * non-numeric entries are reapable (a half-written file from a crash). Exported
 * for unit testing without touching the filesystem.
 */
export function isReapable(entry, now, staleMs, alive = isAlive) {
  if (!entry || !Number.isFinite(entry.ts) || !Number.isInteger(entry.pid)) return true
  if (!alive(entry.pid)) return true
  return now - entry.ts > staleMs
}

const slotPath = (provider, i) => join(LOCK_ROOT, encodeURIComponent(provider), `slot-${i}`)

// Try to take slot `i`: atomic O_EXCL create. If it already exists, reap it when
// its holder is dead/stale and retry the create once. Returns true on ownership.
function tryTake(provider, i, now) {
  const p = slotPath(provider, i)
  for (let attempt = 0; attempt < 2; attempt++) {
    let fd
    try {
      fd = openSync(p, "wx") // wx = O_CREAT|O_EXCL|O_WRONLY → fails if present
    } catch (e) {
      if (e?.code !== "EEXIST") throw e
      // Occupied — reap if the holder is gone, then loop to retry the create.
      let entry = null
      try {
        entry = JSON.parse(readFileSync(p, "utf8"))
      } catch {
        entry = null
      }
      if (isReapable(entry, now, STALE_MS)) {
        try {
          unlinkSync(p)
        } catch {}
        continue // slot freed (by us or a racer) → retry create
      }
      return false // live holder
    }
    try {
      writeSync(fd, JSON.stringify({ pid: process.pid, ts: now }))
    } finally {
      closeSync(fd)
    }
    return true
  }
  return false
}

/**
 * Acquire one slot for `provider`, blocking (poll + jittered backoff) until a slot
 * frees or the acquire timeout elapses. Returns a release() function. On timeout,
 * runs UNGATED rather than failing the review — degrade to "slow", never to "lost".
 */
export async function acquireProviderSlot(provider, limit = PROVIDER_CONCURRENCY, deadlineMs = ACQUIRE_TIMEOUT_MS) {
  if (!provider || limit <= 0) return () => {}
  mkdirSync(join(LOCK_ROOT, encodeURIComponent(provider)), { recursive: true })
  const start = Date.now()
  // index-of-this-process's start used only to vary backoff jitter deterministically
  let spin = 0
  for (;;) {
    const now = Date.now()
    for (let i = 0; i < limit; i++) {
      if (tryTake(provider, i, now)) {
        const p = slotPath(provider, i)
        let released = false
        return () => {
          if (released) return
          released = true
          // Only unlink if WE still own it (guard against a reaper that wrongly
          // freed us — re-read pid before removing).
          try {
            const cur = JSON.parse(readFileSync(p, "utf8"))
            if (cur?.pid === process.pid) unlinkSync(p)
          } catch {
            try {
              unlinkSync(p)
            } catch {}
          }
        }
      }
    }
    if (now - start > deadlineMs) return () => {} // give up gating, proceed ungated
    // Backoff 200–450ms; vary by pid+spin so racers don't sync up and thrash.
    const jitter = 200 + ((process.pid + spin++) % 250)
    await new Promise((r) => setTimeout(r, jitter))
  }
}

/** Run `fn` while holding one provider slot. Always releases, even on throw. */
export async function withProviderSlot(provider, fn, limit = PROVIDER_CONCURRENCY) {
  const release = await acquireProviderSlot(provider, limit)
  try {
    return await fn()
  } finally {
    release()
  }
}

/** Best-effort sweep of dead/stale slot files across all providers (housekeeping). */
export function reapStaleSlots() {
  let providers
  try {
    providers = readdirSync(LOCK_ROOT)
  } catch {
    return
  }
  const now = Date.now()
  for (const enc of providers) {
    let files
    try {
      files = readdirSync(join(LOCK_ROOT, enc))
    } catch {
      continue
    }
    for (const f of files) {
      const p = join(LOCK_ROOT, enc, f)
      let entry = null
      try {
        entry = JSON.parse(readFileSync(p, "utf8"))
      } catch {
        entry = null
      }
      if (isReapable(entry, now, STALE_MS)) {
        try {
          unlinkSync(p)
        } catch {}
      }
    }
  }
}
