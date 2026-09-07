import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  CAP_BODY_BYTES,
  CAP_MESSAGE_COUNT,
  buildTrailerLine,
  capMessages,
  clientCanReceive,
  createContext,
  cursorPathFor,
  defaultCursorDir,
  dedupeByMessageId,
  deriveIdentity,
  filterUnread,
  isHeartbeat,
  isOwnMessage,
  readCursor,
  renderClientOutput,
  validateIdentity,
  writeCursor,
} from "./coordination-mailbox-sweep.mjs";

// --- Cursor hook output shaping ---------------------------------------------

test("cursor sessionStart and beforeSubmitPrompt both emit additional_context", () => {
  // Cursor hooks.json fires both events; omit beforeSubmitPrompt and the
  // per-turn sweep silently produces no inject (clientCanReceive === false).
  assert.deepEqual(
    renderClientOutput("cursor", "sessionStart", "mailbox note", {}),
    { additional_context: "mailbox note" },
  );
  assert.deepEqual(
    renderClientOutput("cursor", "beforeSubmitPrompt", "mailbox note", {}),
    { additional_context: "mailbox note" },
  );
  assert.equal(clientCanReceive("cursor", "beforeSubmitPrompt", {}), true);
});

// --- identity ---------------------------------------------------------------

test("identity derivation is the literal first dash-segment, matching identity.rs's worked example -- not a hash", () => {
  // Same input identity.rs::derive_from_owner's own doctest uses
  // (via SE_WORKSPACE_OWNER "claude:674f9a3f-eng-swarm-bus" -- the session
  // component here is what's left after selectWorkspace-style owner
  // slicing): must produce exactly "claude-674f9a3f", not a digest of it.
  const identity = deriveIdentity("claude", { session_id: "674f9a3f-eng-swarm-bus" }, {});
  assert.equal(identity, "claude-674f9a3f");
});

test("identity derivation takes a UUID session id's first hex group literally", () => {
  // This is the exact shape a Claude session_id arrives in: a standard UUID.
  // Regression: hashing the whole UUID produced a real but DIFFERENT
  // identity than the one a poster would address (the UUID's own first
  // group), so a message sent to "claude-674f9a3f" was never received.
  const identity = deriveIdentity(
    "claude",
    { session_id: "674f9a3f-fffa-4573-8c52-50cbb1b3b1c7" },
    {},
  );
  assert.equal(identity, "claude-674f9a3f");
});

test("identity derivation uses the whole session id verbatim when it has no dash (matches identity.rs: no forced truncation)", () => {
  const identity = deriveIdentity("codex", { session_id: "abcdef0123456789" }, {});
  assert.equal(identity, "codex-abcdef0123456789");
});

test("identity derivation falls back to the first 8 normalized characters only when the segment before the first dash is itself empty", () => {
  const identity = deriveIdentity("codex", { session_id: "-abcdef0123456789" }, {});
  assert.equal(identity, "codex-abcdef01");
});

test("identity derivation rejects a bare client name", () => {
  // No session id anywhere (payload empty, no env fallback) -- deriveIdentity
  // must fail closed rather than silently falling back to a bare "codex".
  assert.throws(() => deriveIdentity("codex", {}, {}), /missing session-unique coordination-mailbox identity/);
});

test("validateIdentity rejects every bare client name outright", () => {
  for (const bare of ["claude", "codex", "cursor", "kimi", "kimi-code", "jcode", "agent", "copilot", "factory", "code"]) {
    assert.throws(() => validateIdentity(bare), /bare client name/);
  }
});

test("validateIdentity rejects a missing or empty session segment", () => {
  for (const bad of ["", "claude-", "-abcd1234", "claude"]) {
    assert.throws(() => validateIdentity(bad));
  }
  assert.doesNotThrow(() => validateIdentity("claude-674f9a3f"));
});

test("an explicit REPO_MEMORY_SWARM_CONSUMER override is validated the same way", () => {
  assert.throws(() => deriveIdentity("claude", {}, { REPO_MEMORY_SWARM_CONSUMER: "claude" }), /bare client name/);
  assert.equal(
    deriveIdentity("claude", {}, { REPO_MEMORY_SWARM_CONSUMER: "claude-abcd1234" }),
    "claude-abcd1234",
  );
});

// --- cursor persistence ------------------------------------------------------

test("cursor path lands under XDG_STATE_HOME/coordination-mailbox, never /tmp", () => {
  const env = { XDG_STATE_HOME: "/home/mhugo/.local/state", HOME: "/home/mhugo" };
  assert.equal(defaultCursorDir(env), "/home/mhugo/.local/state/coordination-mailbox");
  const path = cursorPathFor("claude-abcd1234", env);
  assert.equal(path, "/home/mhugo/.local/state/coordination-mailbox/claude-abcd1234.cursor.json");
  assert.doesNotMatch(path, /^\/tmp\//);
});

test("cursor falls back to $HOME/.local/state when XDG_STATE_HOME is unset", () => {
  const dir = defaultCursorDir({ HOME: "/home/someone" });
  assert.equal(dir, "/home/someone/.local/state/coordination-mailbox");
});

test("cursor persistence: write then read round-trips, and advances monotonically", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-mailbox-cursor-"));
  try {
    const path = join(dir, "claude-abcd1234.cursor.json");
    assert.deepEqual(readCursor(path).sequences, {});

    writeCursor(path, { schema: "coordination-mailbox-cursor/v1", sequences: { "singularity-engine": 7 } });
    assert.deepEqual(readCursor(path).sequences, { "singularity-engine": 7 });

    writeCursor(path, { schema: "coordination-mailbox-cursor/v1", sequences: { "singularity-engine": 12 } });
    assert.deepEqual(readCursor(path).sequences, { "singularity-engine": 12 });

    const raw = JSON.parse(await readFile(path, "utf8"));
    assert.equal(raw.schema, "coordination-mailbox-cursor/v1");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("a corrupt cursor file is treated as absent rather than fatal", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-mailbox-cursor-"));
  try {
    const path = join(dir, "claude-abcd1234.cursor.json");
    const { writeFileSync } = await import("node:fs");
    writeFileSync(path, "{not json");
    assert.deepEqual(readCursor(path).sequences, {});
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("filterUnread keeps only messages with sequence greater than the recorded cursor", () => {
  const messages = [
    { sequence: 5, body: "old" },
    { sequence: 8, body: "new" },
    { body: "no-sequence-field" },
  ];
  const unread = filterUnread(messages, 6);
  assert.deepEqual(unread.map((m) => m.body), ["new", "no-sequence-field"]);
  assert.deepEqual(filterUnread(messages, undefined).map((m) => m.body), ["old", "new", "no-sequence-field"]);
});

// --- heartbeat suppression and own-message drop -----------------------------

test("a presence heartbeat is recognized and counted, a coordination message is not", () => {
  assert.equal(isHeartbeat({ type: "presence", body: '{"detail":"heartbeat"}' }), true);
  assert.equal(isHeartbeat({ type: "handoff", body: '{"detail":"heartbeat"}' }), false, "wrong type must not count as heartbeat");
  assert.equal(isHeartbeat({ type: "presence", body: "no detail field here" }), false, "presence alone is not enough");
});

test("a status-type heartbeat (the live jcode coordinator shape) is recognized", () => {
  // coord-dragon/coord-fox post type "status" with "detail":"heartbeat" —
  // observed live 2026-09-05; the presence-only check never matched them.
  assert.equal(isHeartbeat({ type: "status", body: '{"consumer":"coord-dragon-x","detail":"heartbeat","kind":"status"}' }), true);
  assert.equal(isHeartbeat({ type: "status", body: '{"detail":"real status"}' }), false, "a real status is coordination");
});

test("own messages (sender === identity) are recognized for dropping", () => {
  assert.equal(isOwnMessage({ sender: "claude-abcd1234" }, "claude-abcd1234"), true);
  assert.equal(isOwnMessage({ sender: "codex-11112222" }, "claude-abcd1234"), false);
});

// --- caps and trailing summary line -----------------------------------------

test(`capMessages keeps at most ${CAP_MESSAGE_COUNT} messages`, () => {
  const messages = Array.from({ length: 40 }, (_, index) => ({ sequence: index, body: "x" }));
  const { kept, hiddenCount } = capMessages(messages);
  assert.equal(kept.length, CAP_MESSAGE_COUNT);
  assert.equal(hiddenCount, 40 - CAP_MESSAGE_COUNT);
});

test(`capMessages keeps at most ${CAP_BODY_BYTES} bytes of body`, () => {
  const bigBody = "x".repeat(5000);
  const messages = Array.from({ length: 10 }, () => ({ body: bigBody }));
  const { kept, bytes } = capMessages(messages);
  assert.ok(kept.length < 10, "byte cap must stop before the count cap does here");
  assert.ok(bytes <= CAP_BODY_BYTES + 5000, "at least one message is always admitted even if it alone exceeds the byte cap");
  assert.ok(kept.length >= 1, "a single first message is never rejected outright");
});

test("buildTrailerLine reports both hidden count and suppressed heartbeats", () => {
  assert.equal(
    buildTrailerLine(3, 2),
    "… 3 more unread (2 heartbeats suppressed); poll for the rest",
  );
  assert.equal(buildTrailerLine(0, 0), null);
  assert.equal(
    buildTrailerLine(0, 5),
    "… 0 more unread (5 heartbeats suppressed); poll for the rest",
  );
});

test("createContext appends the trailer line when present", () => {
  const context = createContext(
    [{ sequence: 1, sender: "codex-aaaa1111", recipient: "all", type: "status", origin: "repo-memory", body: "hi" }],
    "… 2 more unread (1 heartbeats suppressed); poll for the rest",
  );
  assert.match(context, /codex-aaaa1111 -> all \[status\] \(repo-memory\): hi/);
  assert.match(context, /… 2 more unread \(1 heartbeats suppressed\); poll for the rest/);
  assert.match(context, /poll remains authoritative/);
});

// --- per-message-id dedupe -------------------------------------------------
//
// Same message arriving via two mailboxes (lane bucket + global bucket,
// both with `recipient='all'`) is observed twice with the same `id` but
// different sequence numbers (per-mailbox sequences). Filter by sequence
// alone (current filterUnread contract) keeps both copies; the user then
// sees the same body twice in one prompt. Fix: dedupe by id across all
// polled mailboxes before any subsequent filtering.

test("same message id from two mailboxes is surfaced once (recipient='all' cross-bucket dedupe)", () => {
  const sameMessageId = "evt-deadbeef-0001";
  // The lane bucket (workspace "foo") and the global bucket each returned
  // the same recipient='all' message with their own per-mailbox sequence.
  const polled = [
    { id: sameMessageId, sequence: 42, sender: "claude-aaa", recipient: "all", type: "status", body: "hi", _workspace: "foo" },
    { id: sameMessageId, sequence: 9001, sender: "claude-aaa", recipient: "all", type: "status", body: "hi", _workspace: "global" },
    { id: "evt-other", sequence: 43, sender: "claude-aaa", recipient: "all", type: "status", body: "other", _workspace: "foo" },
  ];
  // Local cursors say we have already seen nothing for either mailbox.
  const deduped = dedupeByMessageId(polled);
  assert.equal(deduped.length, 2, "the duplicate message id is removed; the distinct id is kept");
  const seen = new Set(deduped.map((m) => m.id));
  assert.ok(seen.has(sameMessageId), "the kept copy is the message we expected to keep");
  assert.ok(seen.has("evt-other"), "the unrelated message is kept");
  // The first occurrence wins so the cursor advance stays on the lowest
  // observed sequence per mailbox (matters for ackFloor reasoning).
  const kept = deduped.find((m) => m.id === sameMessageId);
  assert.equal(kept._workspace, "foo", "first occurrence is the kept one");
});

test("dedupeByMessageId is stable for empty input and for already-unique input", () => {
  assert.deepEqual(dedupeByMessageId([]), []);
  const unique = [
    { id: "a", sequence: 1, _workspace: "foo" },
    { id: "b", sequence: 2, _workspace: "global" },
    { id: "c", sequence: 3, _workspace: "foo" },
  ];
  assert.deepEqual(dedupeByMessageId(unique), unique);
});

test("dedupeByMessageId leaves messages with no id untouched (no id is not a duplicate)", () => {
  const polled = [
    { sequence: 1, body: "no id", _workspace: "foo" },
    { sequence: 2, body: "no id", _workspace: "global" },
  ];
  assert.equal(dedupeByMessageId(polled).length, 2, "messages without id stay; the dedupe key requires an id");
});
