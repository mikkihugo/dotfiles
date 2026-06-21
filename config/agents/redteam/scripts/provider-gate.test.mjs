// provider-gate.test.mjs — node:test suite for the cross-process semaphore.
// Uses REDTEAM_SLOT_DIR to point at a temp dir, set before the dynamic import
// so LOCK_ROOT picks up the seam value at module-load time.
import { describe, it, before, after, beforeEach } from "node:test"
import assert from "node:assert/strict"
import { mkdirSync, mkdtempSync, rmSync, writeFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { tmpdir } from "node:os"

// ── helpers ──────────────────────────────────────────────────────────────────

let tmpBase
let gate // module reference, loaded once per process

before(async () => {
  tmpBase = mkdtempSync(join(tmpdir(), "pg-test-"))
  process.env.REDTEAM_SLOT_DIR = tmpBase
  // Dynamic import so LOCK_ROOT is computed AFTER we set the env var.
  gate = await import("./provider-gate.mjs")
})

after(() => {
  rmSync(tmpBase, { recursive: true, force: true })
  delete process.env.REDTEAM_SLOT_DIR
})

beforeEach(() => {
  // Wipe all slot files between tests so they don't interfere.
  try {
    for (const enc of readdirSync(tmpBase)) {
      rmSync(join(tmpBase, enc), { recursive: true, force: true })
    }
  } catch {
    // tmpBase may be empty on first run
  }
})

// ── (a) acquiring up to `limit` slots succeeds ───────────────────────────────
describe("acquiring slots", () => {
  it("(a) all slots up to limit can be acquired concurrently", async () => {
    const LIMIT = 3
    const PROVIDER = "test-provider-a"
    const releases = []
    for (let i = 0; i < LIMIT; i++) {
      // Short deadline — should not be needed since slots are free.
      const rel = await gate.acquireProviderSlot(PROVIDER, LIMIT, 2000)
      releases.push(rel)
    }
    // We should hold all 3 slots — verify slot files exist.
    const slotDir = join(tmpBase, encodeURIComponent(PROVIDER))
    let slotFiles
    try {
      slotFiles = readdirSync(slotDir).filter((f) => f.startsWith("slot-"))
    } catch {
      slotFiles = []
    }
    assert.equal(slotFiles.length, LIMIT, `expected ${LIMIT} slot files, got ${slotFiles.length}`)
    // Release all.
    for (const rel of releases) rel()
  })
})

// ── (b) (limit+1)th acquire blocks until a release ──────────────────────────
describe("backpressure", () => {
  it("(b) (limit+1)th acquire waits until a slot is released", async () => {
    const LIMIT = 2
    const PROVIDER = "test-provider-b"

    // Fill all slots.
    const rel1 = await gate.acquireProviderSlot(PROVIDER, LIMIT, 5000)
    const rel2 = await gate.acquireProviderSlot(PROVIDER, LIMIT, 5000)

    // Start the (limit+1)th acquire — it must block until we release.
    let thirdResolved = false
    const thirdPromise = gate.acquireProviderSlot(PROVIDER, LIMIT, 5000).then((rel) => {
      thirdResolved = true
      return rel
    })

    // Give it a moment — it should NOT have resolved yet.
    await new Promise((r) => setTimeout(r, 350))
    assert.equal(thirdResolved, false, "third acquire must block while all slots are taken")

    // Release one slot — now the third should unblock.
    rel1()
    const rel3 = await thirdPromise
    assert.equal(thirdResolved, true, "third acquire must succeed after a slot is freed")

    // Cleanup.
    rel2()
    rel3()
  })
})

// ── (c) release frees exactly one slot ──────────────────────────────────────
describe("release", () => {
  it("(c) release removes exactly one slot file and allows another acquire", async () => {
    const LIMIT = 2
    const PROVIDER = "test-provider-c"
    const slotDir = join(tmpBase, encodeURIComponent(PROVIDER))

    const rel1 = await gate.acquireProviderSlot(PROVIDER, LIMIT, 2000)
    const rel2 = await gate.acquireProviderSlot(PROVIDER, LIMIT, 2000)

    // Both slots taken.
    assert.equal(
      readdirSync(slotDir).filter((f) => f.startsWith("slot-")).length,
      2,
      "expected 2 slot files before any release",
    )

    // Release one.
    rel1()
    const afterRelease = readdirSync(slotDir).filter((f) => f.startsWith("slot-")).length
    assert.equal(afterRelease, 1, "expected exactly 1 slot file after one release")

    // The freed slot can be re-acquired immediately.
    const rel3 = await gate.acquireProviderSlot(PROVIDER, LIMIT, 2000)
    assert.equal(
      readdirSync(slotDir).filter((f) => f.startsWith("slot-")).length,
      2,
      "re-acquired slot restored count to 2",
    )

    rel2()
    rel3()
  })
})

// ── (d) stale/dead holder's slot is reclaimed by a new acquire ───────────────
describe("stale slot reclaim", () => {
  it("(d) a slot file from a dead/stale holder is reclaimed during acquire", async () => {
    const LIMIT = 1
    const PROVIDER = "test-provider-d"
    const slotDir = join(tmpBase, encodeURIComponent(PROVIDER))
    mkdirSync(slotDir, { recursive: true })

    // Fabricate a slot file with a dead pid (max-int — process cannot exist)
    // and an old timestamp (30 min ago) so isReapable returns true on both axes.
    const deadPid = 2147483647 // INT_MAX, virtually impossible to be a live PID
    const oldTs = Date.now() - 30 * 60 * 1000 // 30 minutes ago > STALE_MS (20 min)
    const slotFile = join(slotDir, "slot-0")
    writeFileSync(slotFile, JSON.stringify({ pid: deadPid, ts: oldTs }))

    // With LIMIT=1 and slot-0 occupied by a dead holder, acquire should reap it
    // and succeed rather than blocking.
    const rel = await gate.acquireProviderSlot(PROVIDER, LIMIT, 3000)

    // Verify we own the slot now: there should be exactly one slot file (ours).
    const slotFiles = readdirSync(slotDir).filter((f) => f.startsWith("slot-"))
    assert.equal(slotFiles.length, 1, "expected exactly 1 slot file after reclaim+acquire")

    // The function returned a release — confirm it's callable (not the ungated no-op
    // that returns undefined). The ungated no-op () => {} also works here.
    assert.equal(typeof rel, "function", "acquireProviderSlot must return a release function")

    rel()
    // After release the slot file should be gone.
    const remaining = readdirSync(slotDir).filter((f) => f.startsWith("slot-"))
    assert.equal(remaining.length, 0, "slot file should be removed after release")
  })
})

// ── isReapable pure-function unit tests ──────────────────────────────────────
describe("isReapable", () => {
  const alwaysDead = () => false
  const alwaysAlive = () => true

  it("returns true for null entry", () => {
    assert.equal(gate.isReapable(null, Date.now(), 60000, alwaysAlive), true)
  })

  it("returns true when pid is not alive", () => {
    assert.equal(gate.isReapable({ pid: 99999, ts: Date.now() }, Date.now(), 60000, alwaysDead), true)
  })

  it("returns true when entry is older than staleMs", () => {
    const old = Date.now() - 70000
    assert.equal(gate.isReapable({ pid: 1, ts: old }, Date.now(), 60000, alwaysAlive), true)
  })

  it("returns false for a live, fresh entry", () => {
    assert.equal(gate.isReapable({ pid: 1, ts: Date.now() }, Date.now(), 60000, alwaysAlive), false)
  })
})
