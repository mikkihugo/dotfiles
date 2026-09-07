import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  CAP_BODY_BYTES,
  CAP_MESSAGE_COUNT,
  CoordinationBus,
  RepoMemoryBus,
  buildTrailerLine,
  capMessages,
  clientCanReceive,
  coordinationInboxPathFor,
  createContext,
  cursorPathFor,
  defaultCursorDir,
  dedupeByMessageId,
  deriveIdentity,
  derivePrincipal,
  filterUnread,
  isHeartbeat,
  isOwnMessage,
  partitionMessagesByChannel,
  readCoordinationInbox,
  readCursor,
  renderClientOutput,
  selectBus,
  selectCoordinationChannels,
  extractRejectedMailbox,
  validateIdentity,
  writeCoordinationInbox,
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

test("type available is always suppressed as presence noise, regardless of body", () => {
  assert.equal(isHeartbeat({ type: "available", body: "claude session is available from /home/mhugo. Send orders to claude-abcd1234." }), true);
  assert.equal(isHeartbeat({ type: "available", body: "" }), true, "no body content check needed for available pings");
  assert.equal(isHeartbeat({ type: "available" }), true, "missing body must not bypass suppression");
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

// =============================================================================
// coordination_* migration (feature-flagged, REPO_MEMORY_COORDINATION_BUS=1)
// =============================================================================
//
// These tests cover the new path's pure logic only (channel selection,
// principal derivation, inbox_uri persistence, and CoordinationBus's request
// shaping against a fake client). They do not exercise a live or mocked
// HTTP transport -- see coordination-mailbox-sweep.transport.test.mjs for
// that style of coverage on the swarm_bus_* path. Every finding cited below
// (field names, response shapes, error strings) was verified live against
// the deployed gateway on 2026-09-07 under a disposable principal
// ("probe-01ab", mailbox "dotfiles") -- see CoordinationBus's own header
// comment in coordination-mailbox-sweep.mjs for the full probe transcript.

// --- selectBus: flag gating --------------------------------------------------

test("selectBus returns RepoMemoryBus when the flag is unset, empty, or any value other than the literal string \"1\"", () => {
  const gatewayClient = {};
  for (const value of [undefined, "", "0", "true", "TRUE", "on", "yes"]) {
    const env = value === undefined ? {} : { REPO_MEMORY_COORDINATION_BUS: value };
    const bus = selectBus(env, gatewayClient, "codex");
    assert.ok(bus instanceof RepoMemoryBus, `expected RepoMemoryBus for REPO_MEMORY_COORDINATION_BUS=${JSON.stringify(value)}`);
  }
});

test("selectBus returns CoordinationBus only for the literal string \"1\"", () => {
  const gatewayClient = {};
  const bus = selectBus(
    { REPO_MEMORY_COORDINATION_BUS: "1" },
    gatewayClient,
    "codex",
    { identity: "codex-abcd1234", channels: ["engine", "global"], env: {} },
  );
  assert.ok(bus instanceof CoordinationBus);
});

// --- channel selection --------------------------------------------------------

test("selectCoordinationChannels mirrors pollWorkspaces: workspace + additional + global, deduped", () => {
  assert.deepEqual(selectCoordinationChannels("engine", ["engine-lane"]), ["engine", "engine-lane", "global"]);
  assert.deepEqual(selectCoordinationChannels("engine", []), ["engine", "global"]);
  // "global" as the workspace itself, or as a duplicate lane, still appears once.
  assert.deepEqual(selectCoordinationChannels("global", []), ["global"]);
  assert.deepEqual(selectCoordinationChannels("engine", ["engine"]), ["engine", "global"]);
});

test("selectCoordinationChannels strips a leading dot from a hidden-directory-derived identity", () => {
  // /home/mhugo/.dotfiles -> basename ".dotfiles" is not a valid mailbox
  // name server-side, but the bare "dotfiles" is one of the actually
  // registered mailboxes - verified live 2026-09-07.
  assert.deepEqual(selectCoordinationChannels(".dotfiles", []), ["dotfiles", "global"]);
  // Deduping still applies after normalization, not before: ".dotfiles" and
  // "dotfiles" arriving from different sources collapse to one channel.
  assert.deepEqual(selectCoordinationChannels(".dotfiles", ["dotfiles"]), ["dotfiles", "global"]);
});

test("extractRejectedMailbox matches both observed live rejection wordings", () => {
  assert.equal(extractRejectedMailbox(new Error('mailbox "eng-swarm-bus" is not registered')), "eng-swarm-bus");
  assert.equal(
    extractRejectedMailbox(new Error('mailbox must be a bare registered name (letters, digits, dot, underscore or hyphen), not a path, scheme or label: ".dotfiles"')),
    ".dotfiles",
  );
  assert.equal(extractRejectedMailbox(new Error("some unrelated failure")), null);
});

// --- principal derivation ------------------------------------------------------
//
// LIVE-VERIFIED shape (2026-09-07): coordination_subscribe requires
// "<client>-<token>" with the TOKEN half 4-16 alphanumeric characters --
// not a bare 4-16 alnum string. These tests pin derivePrincipal to that
// verified shape, plus the length edge cases DESIGN's blocking gap named.

test("derivePrincipal keeps an already-conforming identity as-is (token already 4-16 alnum)", () => {
  assert.equal(derivePrincipal("claude-674f9a3f", "claude"), "claude-674f9a3f");
});

test("derivePrincipal truncates a token over the 16-character ceiling (the no-dash verbatim-session-id case)", () => {
  // deriveIdentity's own contract: a session id with no dash is used
  // verbatim and untruncated. A synthetic 24-char no-dash suffix (not a
  // real session id - illustrating the shape, not a live identity).
  const identity = "claude-syntheticTestId24Chars";
  const principal = derivePrincipal(identity, "claude");
  assert.equal(principal, "claude-syntheticTestId2");
  const [, token] = principal.split(/-(.+)/);
  assert.ok(token.length >= 4 && token.length <= 16, `token length ${token.length} must be 4-16`);
});

test("derivePrincipal pads a token under the 4-character floor deterministically", () => {
  // identity "cx-ab" strips to token "ab" (2 chars), under the floor.
  assert.equal(derivePrincipal("cx-ab", "cx"), "cx-ab00");
});

test("derivePrincipal strips non-alphanumeric characters from the token (validateIdentity permits '.' and '_', the coordination schema does not)", () => {
  assert.equal(derivePrincipal("codex-ab.cd_12", "codex"), "codex-abcd12");
});

test("derivePrincipal splits a compound client name (containing its own dash) using the known client label, not the first dash in the identity", () => {
  const identity = "kimi-code-abcd1234";
  assert.equal(derivePrincipal(identity, "kimi-code"), "kimi-code-abcd1234");
});

// --- inbox_uri capability persistence ------------------------------------------

test("coordinationInboxPathFor lands in the same directory as cursorPathFor but under a distinct filename", () => {
  const env = { XDG_STATE_HOME: "/home/mhugo/.local/state", HOME: "/home/mhugo" };
  const cursor = cursorPathFor("claude-abcd1234", env);
  const inbox = coordinationInboxPathFor("claude-abcd1234", env);
  assert.equal(inbox, "/home/mhugo/.local/state/coordination-mailbox/claude-abcd1234.coordination-inbox.json");
  assert.notEqual(inbox, cursor, "must be a distinct file from .cursor.json (see DESIGN's rollback-losslessness rationale)");
});

test("readCoordinationInbox on a missing file returns an empty/absent shape, not an error", () => {
  const state = readCoordinationInbox("/nonexistent/path/does-not-exist.coordination-inbox.json");
  assert.equal(state.schema, "coordination-mailbox-inbox/v1");
  assert.equal(state.inbox_uri, undefined);
  assert.deepEqual(state.channels, []);
});

test("a corrupt coordination-inbox file is treated as absent rather than fatal", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-inbox-"));
  try {
    const path = join(dir, "claude-abcd1234.coordination-inbox.json");
    const { writeFileSync } = await import("node:fs");
    writeFileSync(path, "{not valid json");
    const state = readCoordinationInbox(path);
    assert.equal(state.inbox_uri, undefined);
    assert.deepEqual(state.channels, []);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("a coordination-inbox file with no inbox_uri field is treated as absent (inbox_uri is the field that makes the record valid)", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-inbox-"));
  try {
    const path = join(dir, "claude-abcd1234.coordination-inbox.json");
    const { writeFileSync } = await import("node:fs");
    writeFileSync(path, JSON.stringify({ schema: "coordination-mailbox-inbox/v1", channels: ["global"], sequence: 5 }));
    const state = readCoordinationInbox(path);
    assert.equal(state.inbox_uri, undefined, "a record without inbox_uri is not a usable capability");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("coordination-inbox persistence: write then read round-trips every field", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-inbox-"));
  try {
    const path = join(dir, "claude-abcd1234.coordination-inbox.json");
    const written = {
      schema: "coordination-mailbox-inbox/v1",
      inbox_uri: "coord://fake-signed-capability-token",
      channels: ["engine", "global"],
      principal: "claude-abcd1234",
      session: "claude-abcd1234",
      sequence: 42,
      issued_at: "2026-09-07T00:00:00.000Z",
    };
    writeCoordinationInbox(path, written);
    const read = readCoordinationInbox(path);
    assert.deepEqual(read, written);

    const { statSync } = await import("node:fs");
    // Same persistence hygiene as writeCursor: 0600 file.
    assert.equal(statSync(path).mode & 0o777, 0o600);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("coordination-inbox persistence never appears in .cursor.json's directory listing as the same file (flag toggle stays lossless)", async () => {
  const dir = await mkdtemp(join(tmpdir(), "coordination-inbox-"));
  try {
    const cursorPath = join(dir, "claude-abcd1234.cursor.json");
    const inboxPath = join(dir, "claude-abcd1234.coordination-inbox.json");
    writeCursor(cursorPath, { schema: "coordination-mailbox-cursor/v1", sequences: { engine: 7 } });
    writeCoordinationInbox(inboxPath, {
      schema: "coordination-mailbox-inbox/v1",
      inbox_uri: "coord://fake",
      channels: ["engine"],
      principal: "claude-abcd1234",
      session: "claude-abcd1234",
      sequence: 7,
      issued_at: "2026-09-07T00:00:00.000Z",
    });
    // Writing one must never disturb the other -- this is the whole point
    // of keeping them as separate files.
    assert.deepEqual(readCursor(cursorPath).sequences, { engine: 7 });
    assert.equal(readCoordinationInbox(inboxPath).inbox_uri, "coord://fake");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

// --- message partitioning (direct-mail catch-all bucket) -----------------------

test("partitionMessagesByChannel buckets a message by its channel/mailbox field when it matches an enumerated channel", () => {
  const messages = [
    { id: "a", channel: "engine", body: "on-channel" },
    { id: "b", mailbox: "global", body: "also on-channel (mailbox field)" },
  ];
  const buckets = partitionMessagesByChannel(messages, ["engine", "global"]);
  assert.deepEqual(buckets.get("engine").map((m) => m.id), ["a"]);
  assert.deepEqual(buckets.get("global").map((m) => m.id), ["b"]);
  assert.deepEqual(buckets.get("__inbox__"), []);
});

test("partitionMessagesByChannel falls back to the __inbox__ catch-all for direct mail matching no enumerated channel (the partition-hole fix)", () => {
  const messages = [
    { id: "direct-1", channel: "some-other-session-not-a-mailbox", body: "direct mail" },
    { id: "direct-2", body: "no channel field at all" },
  ];
  const buckets = partitionMessagesByChannel(messages, ["engine", "global"]);
  assert.deepEqual(buckets.get("engine"), []);
  assert.deepEqual(buckets.get("global"), []);
  assert.deepEqual(buckets.get("__inbox__").map((m) => m.id), ["direct-1", "direct-2"]);
});

// --- CoordinationBus request shaping (fake client, no network) -----------------

function fakeCoordinationClient(responses) {
  const calls = [];
  return {
    calls,
    async callRepoMemory(tool, args) {
      calls.push({ tool, args });
      const handler = responses[tool];
      if (!handler) throw new Error(`fakeCoordinationClient: no handler for ${tool}`);
      return typeof handler === "function" ? handler(args) : handler;
    },
    async close() {},
  };
}

test("CoordinationBus.subscribe treats ack_watermark-without-inbox_uri as success (the live-observed shape)", async () => {
  const client = fakeCoordinationClient({
    coordination_subscribe: { ack_watermark: 0, channels: ["engine", "global"], created: true, principal: "codex-abcd1234", session: "codex-abcd1234" },
  });
  const bus = new CoordinationBus(client, { identity: "codex-abcd1234", clientLabel: "codex", channels: ["engine", "global"], env: { XDG_STATE_HOME: "/nonexistent" } });
  const result = await bus.subscribe("engine", "codex-abcd1234");
  assert.deepEqual(result, { ack_watermark: 0 });
  assert.equal(client.calls[0].tool, "coordination_subscribe");
  assert.equal(client.calls[0].args.principal, "codex-abcd1234");
  assert.equal(client.calls[0].args.session, "codex-abcd1234");
  assert.ok(!("inbox_uri" in client.calls[0].args), "no inbox_uri hint on the first call -- none is held yet");
});

test("CoordinationBus.poll partitions the merged inbox and tags the __inbox__ bucket for direct mail, and reuses one cached poll across workspaces in a run", async () => {
  const client = fakeCoordinationClient({
    coordination_subscribe: { ack_watermark: 10 },
    coordination_poll: {
      known_session: true,
      messages: [
        { id: "m1", channel: "engine", body: "on channel" },
        { id: "m2", body: "direct mail, no channel" },
      ],
    },
  });
  const bus = new CoordinationBus(client, { identity: "codex-abcd1234", clientLabel: "codex", channels: ["engine", "global"], env: { XDG_STATE_HOME: "/nonexistent" } });
  const engineBucket = await bus.poll("engine", "codex-abcd1234", {});
  const inboxBucket = await bus.poll("__inbox__", "codex-abcd1234", {});
  assert.deepEqual(engineBucket.map((m) => m.id), ["m1"]);
  assert.deepEqual(inboxBucket.map((m) => m.id), ["m2"]);
  assert.equal(engineBucket.knownConsumer, true);
  const pollCalls = client.calls.filter((c) => c.tool === "coordination_poll");
  assert.equal(pollCalls.length, 1, "the second poll() call in the same run must reuse the cached result, not re-call the network");
});

test("CoordinationBus.poll subscribes even when a capability is already loaded, every run (no silent no-op on a warm state)", async () => {
  const client = fakeCoordinationClient({
    coordination_subscribe: { ack_watermark: 5 },
    coordination_poll: { known_session: true, messages: [] },
  });
  const bus = new CoordinationBus(client, { identity: "codex-abcd1234", clientLabel: "codex", channels: ["global"], env: { XDG_STATE_HOME: "/nonexistent" } });
  await bus.poll("global", "codex-abcd1234", {});
  const subscribeCalls = client.calls.filter((c) => c.tool === "coordination_subscribe");
  assert.equal(subscribeCalls.length, 1, "poll() must call subscribe at least once per run even with no prior bus.subscribe() call");
});

test("CoordinationBus.subscribe drops a rejected (unregistered) mailbox and retries rather than failing the whole call", async () => {
  let attempt = 0;
  const client = fakeCoordinationClient({
    coordination_subscribe: (args) => {
      attempt += 1;
      if (args.channels.includes("eng-swarm-bus")) {
        throw new Error('mailbox "eng-swarm-bus" is not registered; known mailboxes are global, presence, dotfiles, infra, jcode, singularity-engine');
      }
      return { ack_watermark: 0, channels: args.channels };
    },
  });
  const bus = new CoordinationBus(client, {
    identity: "codex-abcd1234",
    clientLabel: "codex",
    channels: ["engine", "eng-swarm-bus", "global"],
    env: { XDG_STATE_HOME: "/nonexistent" },
  });
  const result = await bus.subscribe("engine", "codex-abcd1234");
  assert.deepEqual(result, { ack_watermark: 0 });
  assert.equal(attempt, 2, "one rejected attempt, one retry with the offending channel dropped");
});

test("CoordinationBus.ack and .post include inbox_uri only when one is held, and never otherwise", async () => {
  const client = fakeCoordinationClient({
    coordination_ack: {},
    coordination_post: {},
  });
  const bus = new CoordinationBus(client, { identity: "codex-abcd1234", clientLabel: "codex", channels: ["global"], env: { XDG_STATE_HOME: "/nonexistent" } });
  await bus.ack("global", "codex-abcd1234", "msg-1");
  await bus.post("global", { sender: "codex-abcd1234", recipient: "all", type: "available", body: "hi", idempotency_key: "k" });
  const ackArgs = client.calls.find((c) => c.tool === "coordination_ack").args;
  const postArgs = client.calls.find((c) => c.tool === "coordination_post").args;
  assert.ok(!("inbox_uri" in ackArgs));
  assert.ok(!("inbox_uri" in postArgs));
  assert.equal(postArgs.mailbox, "global");
  assert.deepEqual(postArgs.recipient, { kind: "all" });
  assert.equal(postArgs.sender_principal, "codex-abcd1234");
});
