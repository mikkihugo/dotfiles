import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import {
  ACTIONABLE_TYPES,
  BLOCKED_ID_CAP,
  BLOCKED_ID_TTL_MS,
  MAX_CONSECUTIVE_BLOCKS,
  decide,
  filterUnblocked,
  pruneBlockedIds,
  readCounter,
  readState,
  recordBlockedIds,
  statePath,
  writeCounter,
  writeState,
} from "./stop-continue-if-actionable.mjs";

test("an empty (already-filtered) input never blocks", () => {
  assert.deepEqual(decide([], 0), { block: false });
});

test("end-to-end: non-actionable types are filtered out before decide() ever sees them", () => {
  // decide() takes pre-filtered input (see its own doc comment); this
  // exercises the actual main() call path - filter, then decide - rather
  // than asserting decide() itself does filtering it was never given.
  const raw = [{ type: "status" }, { type: "findings" }, { type: "available" }];
  const actionable = raw.filter((m) => ACTIONABLE_TYPES.has(m.type));
  assert.deepEqual(actionable, []);
  assert.deepEqual(decide(actionable, 0), { block: false });
});

test("a single question blocks with a reason, below the cap", () => {
  const verdict = decide([{ sender: "cursor-abc", type: "question", body: "need a decision" }], 0);
  assert.equal(verdict.block, true);
  assert.match(verdict.reason, /1 unacked actionable/);
  assert.match(verdict.reason, /cursor-abc \[question\]/);
});

test("a blocker also counts as actionable", () => {
  const verdict = decide([{ sender: "x", type: "blocker", body: "y" }], 0);
  assert.equal(verdict.block, true);
});

test("hitting the cap allows the stop instead of blocking forever", () => {
  const actionable = [{ sender: "x", type: "question", body: "still there" }];
  // One below the cap: still blocks.
  assert.equal(decide(actionable, MAX_CONSECUTIVE_BLOCKS - 1).block, true);
  // At the cap: fails open rather than looping forever.
  const capped = decide(actionable, MAX_CONSECUTIVE_BLOCKS);
  assert.equal(capped.block, false);
  assert.equal(capped.capHit, true);
});

test("ACTIONABLE_TYPES is exactly question and blocker, not the noisy types", () => {
  assert.equal(ACTIONABLE_TYPES.has("question"), true);
  assert.equal(ACTIONABLE_TYPES.has("blocker"), true);
  assert.equal(ACTIONABLE_TYPES.has("available"), false);
  assert.equal(ACTIONABLE_TYPES.has("status"), false);
  assert.equal(ACTIONABLE_TYPES.has("findings"), false);
  assert.equal(ACTIONABLE_TYPES.has("proposal"), false);
});

test("counter file round-trips through read/write, and a missing file reads as 0", async () => {
  const dir = await mkdtemp(join(tmpdir(), "stop-hook-test-"));
  try {
    const path = join(dir, "nested", "counter.json");
    assert.equal(await readCounter(path), 0, "missing file must read as 0, not throw");
    await writeCounter(path, 2);
    assert.equal(await readCounter(path), 2);
    await writeCounter(path, 0);
    assert.equal(await readCounter(path), 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("a corrupt counter file is treated as 0 rather than fatal", async () => {
  const dir = await mkdtemp(join(tmpdir(), "stop-hook-test-"));
  try {
    const path = join(dir, "counter.json");
    await writeCounter(path, 1);
    const { writeFile } = await import("node:fs/promises");
    await writeFile(path, "not json", "utf8");
    assert.equal(await readCounter(path), 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("statePath honors XDG_STATE_HOME and falls back to $HOME/.local/state", () => {
  assert.equal(
    statePath({ XDG_STATE_HOME: "/custom/state", HOME: "/home/x" }),
    "/custom/state/claude-stop-continue/counter.json",
  );
  assert.equal(
    statePath({ HOME: "/home/x" }),
    "/home/x/.local/state/claude-stop-continue/counter.json",
  );
});

// --- session-keyed state path (concurrent-session isolation) ---------------

test("statePath keys the file by session id when given, so concurrent sessions on one host don't share a block cap", () => {
  assert.equal(
    statePath({ XDG_STATE_HOME: "/custom/state" }, "674f9a3f-eng-swarm-bus"),
    "/custom/state/claude-stop-continue/counter.674f9a3f-eng-swarm-bus.json",
  );
  // Blank/undefined session id falls back to the original shared filename.
  assert.equal(statePath({ XDG_STATE_HOME: "/custom/state" }, ""), "/custom/state/claude-stop-continue/counter.json");
  assert.equal(statePath({ XDG_STATE_HOME: "/custom/state" }, undefined), "/custom/state/claude-stop-continue/counter.json");
});

test("statePath sanitizes a session id containing path separators so it cannot escape the state directory", () => {
  const path = statePath({ XDG_STATE_HOME: "/custom/state" }, "../../etc/passwd");
  // No literal path separator survives sanitization, so the whole session id
  // resolves to a single filename component under claude-stop-continue/ -
  // "../.." with slashes stripped is inert (nothing left to traverse into),
  // not a directory escape.
  assert.equal(dirname(path), "/custom/state/claude-stop-continue");
  assert.ok(!basename(path).includes("/"));
});

// --- multi-bucket broadcast: blocked-id memory ------------------------------
//
// A recipient="all" broadcast can still turn up from a coordination-mailbox
// bucket runSweep didn't poll together with the one that already acked it
// (see coordination-mailbox-sweep.mjs's unreadAllCopies fix and comment).
// This hook's own id memory is the second layer of defense: once an id has
// been surfaced, it must not cost another block.

test("filterUnblocked drops an actionable message whose id was already surfaced", () => {
  const actionable = [
    { id: "bcast-1", sender: "x", type: "blocker", body: "already seen" },
    { id: "bcast-2", sender: "x", type: "blocker", body: "brand new" },
  ];
  const kept = filterUnblocked(actionable, { "bcast-1": Date.now() });
  assert.deepEqual(kept.map((m) => m.id), ["bcast-2"]);
});

test("filterUnblocked never drops a message with no id (cannot safely dedupe an id-less message)", () => {
  const actionable = [{ sender: "x", type: "blocker", body: "no id at all" }];
  assert.equal(filterUnblocked(actionable, { anything: Date.now() }).length, 1);
});

test("end-to-end: an already-blocked id does not trigger a second block, but a genuinely new id still does", () => {
  const now = Date.now();
  const blockedIds = { "bcast-1": now };
  const actionable = [
    { id: "bcast-1", sender: "x", type: "blocker", body: "stale copy from an unpolled bucket" },
  ];
  const newActionable = filterUnblocked(actionable, pruneBlockedIds(blockedIds, now));
  assert.deepEqual(decide(newActionable, 0), { block: false });

  const withNewId = [...actionable, { id: "bcast-2", sender: "x", type: "blocker", body: "genuinely new" }];
  const stillNew = filterUnblocked(withNewId, pruneBlockedIds(blockedIds, now));
  const verdict = decide(stillNew, 0);
  assert.equal(verdict.block, true);
  assert.match(verdict.reason, /genuinely new/);
  assert.doesNotMatch(verdict.reason, /stale copy/);
});

test("pruneBlockedIds drops entries past the TTL and keeps fresh ones", () => {
  const now = Date.now();
  const blockedIds = {
    stale: now - BLOCKED_ID_TTL_MS - 1,
    fresh: now - 1000,
  };
  const pruned = pruneBlockedIds(blockedIds, now);
  assert.deepEqual(Object.keys(pruned), ["fresh"]);
});

test("pruneBlockedIds bounds the map to BLOCKED_ID_CAP, keeping the most recent entries", () => {
  const now = Date.now();
  const blockedIds = {};
  for (let i = 0; i < BLOCKED_ID_CAP + 50; i += 1) {
    blockedIds[`id-${i}`] = now - (BLOCKED_ID_CAP + 50 - i) * 1000; // ascending recency
  }
  const pruned = pruneBlockedIds(blockedIds, now);
  assert.equal(Object.keys(pruned).length, BLOCKED_ID_CAP);
  assert.ok(!("id-0" in pruned), "the oldest entries are dropped first");
  assert.ok(`id-${BLOCKED_ID_CAP + 49}` in pruned, "the most recent entry survives");
});

test("recordBlockedIds adds every id-bearing message and re-bounds the result", () => {
  const now = Date.now();
  const recorded = recordBlockedIds({}, [
    { id: "a", type: "blocker" },
    { id: "b", type: "question" },
    { type: "blocker" }, // no id: not recorded
  ], now);
  assert.deepEqual(Object.keys(recorded).sort(), ["a", "b"]);
});

test("readState/writeState round-trip count and blockedIds together, and a missing file reads as empty", async () => {
  const dir = await mkdtemp(join(tmpdir(), "stop-hook-state-test-"));
  try {
    const path = join(dir, "nested", "state.json");
    assert.deepEqual(await readState(path), { count: 0, blockedIds: {} });
    await writeState(path, { count: 2, blockedIds: { x: 123 } });
    assert.deepEqual(await readState(path), { count: 2, blockedIds: { x: 123 } });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("a corrupt state file is treated as empty rather than fatal", async () => {
  const dir = await mkdtemp(join(tmpdir(), "stop-hook-state-test-"));
  try {
    const path = join(dir, "state.json");
    await writeState(path, { count: 1, blockedIds: { x: 1 } });
    const { writeFile } = await import("node:fs/promises");
    await writeFile(path, "not json", "utf8");
    assert.deepEqual(await readState(path), { count: 0, blockedIds: {} });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("writeCounter preserves blockedIds already in the file (read-merge-write, not a blind overwrite)", async () => {
  const dir = await mkdtemp(join(tmpdir(), "stop-hook-state-test-"));
  try {
    const path = join(dir, "state.json");
    await writeState(path, { count: 3, blockedIds: { "bcast-1": 999 } });
    await writeCounter(path, 0);
    assert.deepEqual(await readState(path), { count: 0, blockedIds: { "bcast-1": 999 } });
    assert.equal(await readCounter(path), 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
