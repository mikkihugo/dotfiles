import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  ACTIONABLE_TYPES,
  MAX_CONSECUTIVE_BLOCKS,
  decide,
  readCounter,
  statePath,
  writeCounter,
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
