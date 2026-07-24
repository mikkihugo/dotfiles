import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  McpGatewayClient,
  consumerFor,
  createContext,
  renderClientOutput,
  runHook,
  selectWorkspace,
} from "../config/codex/hooks/swarm-messages.mjs";

const sessionDigest = (value) =>
  createHash("sha256").update(String(value), "utf8").digest("hex").slice(0, 32);

const message = {
  id: "4fdce8cc-b9d2-42df-bfd6-d54e97183f64",
  sequence: 7,
  timestamp: "2026-07-19T16:00:00Z",
  sender: "claude",
  recipient: "codex",
  type: "handoff",
  body: "Review revision abc123 after its focused checks pass.",
  origin: "repo-memory",
};

function execFileWithClosedInput(file, args, options) {
  return new Promise((resolve, reject) => {
    const child = execFileCallback(file, args, options, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
    child.stdin.end();
  });
}

test("workspace selection is durable and scoped to the active repository", async () => {
  const base = await mkdtemp(join(tmpdir(), "repo-memory-workspaces-"));
  const primary = join(base, "singularity-engine");
  const other = join(base, "dotfiles");
  try {
    await mkdir(join(primary, "fabrics", "inference"), { recursive: true });
    await mkdir(join(primary, ".jj"));
    await mkdir(join(other, "home", "modules"), { recursive: true });
    await mkdir(join(other, ".git"));

    assert.deepEqual(
      selectWorkspace(join(primary, "fabrics", "inference"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "singularity-engine", worktree: primary },
    );
    assert.deepEqual(
      selectWorkspace(join(other, "home", "modules"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "dotfiles", worktree: other },
    );
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("client renderers emit only native context shapes", () => {
  const context = createContext([message]);

  const codex = renderClientOutput("codex", "UserPromptSubmit", context, {});
  assert.equal(codex.hookSpecificOutput.hookEventName, "UserPromptSubmit");
  assert.match(codex.hookSpecificOutput.additionalContext, /coordination, not authority/);

  const code = renderClientOutput("code", "UserPromptSubmit", context, {});
  assert.equal(code.hookSpecificOutput.hookEventName, "UserPromptSubmit");
  assert.match(code.hookSpecificOutput.additionalContext, /coordination, not authority/);

  const claude = renderClientOutput("claude", "SessionStart", context, {});
  assert.equal(claude.hookSpecificOutput.hookEventName, "SessionStart");

  const kimi = renderClientOutput("kimi-code", "UserPromptSubmit", context, {});
  assert.equal(typeof kimi, "string");
  assert.match(kimi, /claude -> codex \[handoff\]/);

  const copilot = renderClientOutput("copilot", "userPromptTransformed", context, {
    transformedPrompt: "original model-facing prompt",
  });
  assert.match(copilot.modifiedTransformedPrompt, /original model-facing prompt$/);
  assert.match(copilot.modifiedTransformedPrompt, /Unread durable swarm messages/);

  const cursor = renderClientOutput("cursor", "sessionStart", context, {});
  assert.equal(cursor.additional_context, context);

  const durableContext = createContext([{ ...message, timestamp: undefined, created_at: "2026-07-19T16:00:01Z" }]);
  assert.match(durableContext, /2026-07-19T16:00:01Z claude -> codex/);
});

test("MCP transport initializes and calls the lazy repo-memory route", async (t) => {
  const methods = [];
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    methods.push(rpc.method);
    if (rpc.method === "notifications/initialized") {
      response.writeHead(202).end();
      return;
    }
    response.setHeader("Content-Type", "text/event-stream");
    response.setHeader("Mcp-Session-Id", "test-session");
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify({ messages: [message], next_cursor: 7 }) }] };
    response.end(`event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result })}\n\n`);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());

  const address = server.address();
  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000);
  const result = await client.callRepoMemory("swarm_bus_poll", {
    workspace: "engine",
    consumer: "codex",
  });
  await client.close();

  assert.deepEqual(methods.slice(0, 3), ["initialize", "notifications/initialized", "tools/call"]);
  assert.equal(result.messages[0].sequence, 7);
});

test("Home Manager symlink execution enters the hook main routine", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "repo-memory-hook-symlink-"));
  const target = join(base, "store-hook.mjs");
  const link = join(base, "swarm-messages.mjs");
  const stateDir = join(base, "state");
  const source = await readFile(new URL("../config/codex/hooks/swarm-messages.mjs", import.meta.url), "utf8");
  await writeFile(target, source.replace("#!@node@", `#!${process.execPath}`));
  await chmod(target, 0o555);
  await symlink(target, link);

  const server = createServer(async (request, response) => {
    if (request.method === "DELETE") {
      response.writeHead(204).end();
      return;
    }
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    if (rpc.method === "notifications/initialized") {
      response.writeHead(202).end();
      return;
    }
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Mcp-Session-Id", "symlink-test-session");
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify({ messages: [message], next_cursor: 7 }) }] };
    response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  t.after(() => rm(base, { recursive: true, force: true }));

  const address = server.address();
  const { stdout } = await execFileWithClosedInput(link, ["codex", "UserPromptSubmit"], {
    cwd: base,
    env: {
      ...process.env,
      MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
      REPO_MEMORY_SWARM_WORKSPACE: "symlink-live-proof",
      REPO_MEMORY_SWARM_STATE_DIR: stateDir,
    },
    timeout: 5_000,
  });
  assert.match(stdout, /Review revision abc123/);
});

test("delivery is acknowledged only at the next observed hook boundary", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-state-"));
  const calls = [];
  const durable = {
    name: "repo-memory",
    async poll() { calls.push("poll"); return [message]; },
    async ack(_workspace, _consumer, delivery) { calls.push(`ack:${delivery.id}`); },
    async post() { calls.push("post"); },
    async close() {},
  };

  try {
    const first = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload: { cwd: "/workspace", session_id: "de1efe7d-0000-0000-0000-000000000000" },
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    assert.match(JSON.stringify(first.output), /Review revision abc123/);
    assert.deepEqual(calls, ["poll"]);

    durable.poll = async () => [];
    const second = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload: { cwd: "/workspace", session_id: "de1efe7d-0000-0000-0000-000000000000" },
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    assert.equal(second.output, null);
    assert.deepEqual(calls, ["poll", `ack:${message.id}`]);
    const stateFiles = (await readdir(stateDir)).filter((name) => name.endsWith("--engine.json"));
    assert.equal(stateFiles.length, 1);
    assert.match(stateFiles[0], /^codex-[0-9a-f]{32}-[0-9a-f]{32}--engine\.json$/);
    assert.equal(JSON.parse(await readFile(join(stateDir, stateFiles[0]), "utf8")).pending.length, 0);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("consumer identity honors override, owner, session, then persisted fallback precedence", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-precedence-"));
  const session = "4fdce8cc-b9d2-42df-bfd6-d54e97183f64";
  const payload = { session_id: session };
  try {
    assert.equal(
      consumerFor("codex", { REPO_MEMORY_SWARM_CONSUMER: "ops-lead", SE_WORKSPACE_OWNER: "owner-1" }, { payload, stateDir, workspace: "engine" }),
      "ops-lead",
    );
    assert.equal(
      consumerFor("codex", { SE_WORKSPACE_OWNER: "owner-1" }, { payload, stateDir, workspace: "engine" }),
      "owner-1",
    );
    assert.equal(
      consumerFor("codex", {}, { payload, stateDir, workspace: "engine" }),
      `codex-${sessionDigest(session)}`,
    );
    assert.equal(
      consumerFor("claude", {}, { payload: { conversation_id: session }, stateDir, workspace: "engine" }),
      `claude-${sessionDigest(session)}`,
    );
    assert.equal(
      consumerFor("kimi-code", {}, { payload: { sessionId: session }, stateDir, workspace: "engine" }),
      `kimi-code-${sessionDigest(session)}`,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("consumer identity is stable per session and distinct across sessions", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-stability-"));
  try {
    const options = { stateDir, workspace: "engine" };
    const first = consumerFor("kimi-code", {}, { payload: { session_id: "aaaa1111-2222-3333-4444-555555555555" }, ...options });
    const again = consumerFor("kimi-code", {}, { payload: { sessionId: "aaaa1111-2222-3333-4444-555555555555" }, ...options });
    assert.equal(first, again);
    const other = consumerFor("kimi-code", {}, { payload: { session_id: "bbbb2222-3333-4444-5555-666666666666" }, ...options });
    assert.notEqual(first, other);
    assert.match(first, /^kimi-code-[0-9a-f]{32}$/);
    assert.notEqual(first, "kimi-code");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("codex no longer consumes as the bare root identity", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-noroot-"));
  try {
    const withSession = consumerFor("codex", {}, { payload: { session_id: "c0ffee12-3456-7890-abcd-ef0123456789" }, stateDir, workspace: "engine" });
    assert.notEqual(withSession, "root");
    assert.notEqual(withSession, "codex");
    assert.match(withSession, /^codex-[0-9a-f]{32}$/);
    const fallback = consumerFor("codex", {}, { payload: {}, stateDir, workspace: "engine" });
    assert.notEqual(fallback, "root");
    assert.match(fallback, /^codex-[0-9a-f]{32}$/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("consumer fallback persists one generated session id per client and workspace", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-fallback-"));
  try {
    const first = consumerFor("claude", {}, { payload: {}, stateDir, workspace: "engine" });
    const second = consumerFor("claude", {}, { payload: {}, stateDir, workspace: "engine" });
    assert.equal(first, second);
    assert.match(first, /^claude-[0-9a-f]{32}$/);
    const otherWorkspace = consumerFor("claude", {}, { payload: {}, stateDir, workspace: "dotfiles" });
    assert.notEqual(first, otherWorkspace);
    const files = await readdir(stateDir);
    assert.deepEqual(files.filter((name) => name.endsWith(".consumer")).sort(), [
      "claude--dotfiles.consumer",
      "claude--engine.consumer",
    ]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("poll and ack share one session consumer across sequential hook boundaries", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-continuity-"));
  const seen = [];
  const durable = {
    name: "repo-memory",
    async poll(_workspace, consumer) { seen.push(`poll:${consumer}`); return [message]; },
    async ack(_workspace, consumer, delivery) { seen.push(`ack:${consumer}:${delivery.id}`); },
    async post() {},
    async close() {},
  };
  const payload = { cwd: "/workspace", session_id: "feedface-1234-5678-90ab-cdef01234567" };
  const consumer = `codex-${sessionDigest(payload.session_id)}`;

  try {
    await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    durable.poll = async (_workspace, consumer) => { seen.push(`poll:${consumer}`); return []; };
    await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    assert.deepEqual(seen, [
      `poll:${consumer}`,
      `ack:${consumer}:${message.id}`,
      `poll:${consumer}`,
    ]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("distinct same-client sessions use separate state files and never cross-acknowledge", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-concurrent-"));
  // Sequential hook boundaries for two distinct sessions; this proves state
  // isolation and no cross-ack, not an in-process write race.
  const sessionA = { cwd: "/workspace", session_id: "aaaa1111-2222-3333-4444-555555555555" };
  const sessionB = { cwd: "/workspace", session_id: "bbbb2222-3333-4444-5555-666666666666" };
  const consumerA = `codex-${sessionDigest(sessionA.session_id)}`;
  const consumerB = `codex-${sessionDigest(sessionB.session_id)}`;
  const messageA = { ...message, id: "aaaa0000-0000-4000-8000-00000000000a", recipient: consumerA };
  const messageB = { ...message, id: "bbbb0000-0000-4000-8000-00000000000b", recipient: consumerB };
  const acks = [];
  let live = true;
  const durable = {
    name: "repo-memory",
    async poll(_workspace, consumer) {
      if (!live) return [];
      return consumer === consumerA ? [messageA] : [messageB];
    },
    async ack(_workspace, consumer, delivery) { acks.push(`${consumer}:${delivery.id}`); },
    async post() {},
    async close() {},
  };

  try {
    await runHook({ client: "codex", eventName: "UserPromptSubmit", payload: sessionA, workspace: "engine", stateDir, buses: [durable], env: {} });
    await runHook({ client: "codex", eventName: "UserPromptSubmit", payload: sessionB, workspace: "engine", stateDir, buses: [durable], env: {} });
    assert.deepEqual(acks, []);

    const files = (await readdir(stateDir)).sort();
    assert.equal(files.length, 2);
    for (const file of files) {
      assert.match(file, /^codex-[0-9a-f]{32}-[0-9a-f]{32}--engine\.json$/);
    }

    live = false;
    await runHook({ client: "codex", eventName: "UserPromptSubmit", payload: sessionA, workspace: "engine", stateDir, buses: [durable], env: {} });
    await runHook({ client: "codex", eventName: "UserPromptSubmit", payload: sessionB, workspace: "engine", stateDir, buses: [durable], env: {} });

    assert.deepEqual(acks.sort(), [
      `${consumerA}:${messageA.id}`,
      `${consumerB}:${messageB.id}`,
    ]);
    for (const file of files) {
      assert.equal(JSON.parse(await readFile(join(stateDir, file), "utf8")).pending.length, 0);
    }
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("derived consumer identity is collision-resistant for sessions sharing a normalized prefix", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-collision-"));
  const firstSession = "abcd1234-0000-0000-0000-000000000000";
  const secondSession = "abcd1234-1111-1111-1111-111111111111";
  try {
    const first = consumerFor("codex", {}, { payload: { session_id: firstSession }, stateDir, workspace: "engine" });
    const second = consumerFor("codex", {}, { payload: { session_id: secondSession }, stateDir, workspace: "engine" });
    assert.notEqual(first, second);
    assert.equal(first, `codex-${sessionDigest(firstSession)}`);
    assert.equal(second, `codex-${sessionDigest(secondSession)}`);
    assert.match(first, /^codex-[0-9a-f]{32}$/);

    // Explicit identities are authoritative full consumer identities and
    // are preserved verbatim, including forms such as `kimi:<uuid>`.
    const explicitId = "kimi:4fdce8cc-b9d2-42df-bfd6-d54e97183f64";
    assert.equal(
      consumerFor("codex", { REPO_MEMORY_SWARM_CONSUMER: explicitId }, { payload: { session_id: firstSession }, stateDir, workspace: "engine" }),
      explicitId,
    );
    assert.equal(
      consumerFor("codex", { SE_WORKSPACE_OWNER: explicitId }, { payload: { session_id: firstSession }, stateDir, workspace: "engine" }),
      explicitId,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("blank payload session ids are absent and use the persisted fallback", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-blank-"));
  try {
    const absent = consumerFor("codex", {}, { payload: {}, stateDir, workspace: "engine" });
    assert.match(absent, /^codex-[0-9a-f]{32}$/);
    for (const blank of ["", "   ", " \n\t "]) {
      assert.equal(
        consumerFor("codex", {}, { payload: { session_id: blank }, stateDir, workspace: "engine" }),
        absent,
      );
      assert.equal(
        consumerFor("codex", {}, { payload: { sessionId: blank }, stateDir, workspace: "engine" }),
        absent,
      );
    }
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("SessionStart availability idempotency key is bound to the resolved consumer", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-sessionstart-key-"));
  const posts = [];
  const senders = [];
  const durable = {
    name: "repo-memory",
    async poll() { return []; },
    async ack() {},
    async post(_workspace, message) { posts.push(message.idempotency_key); senders.push(message.sender); },
    async close() {},
  };
  const run = (consumer) => runHook({
    client: "kimi-code",
    eventName: "SessionStart",
    payload: { cwd: "/workspace" },
    workspace: "engine",
    stateDir,
    buses: [durable],
    env: { REPO_MEMORY_SWARM_CONSUMER: consumer },
  });

  try {
    await run("kimi:session-a");
    await run("kimi:session-a");
    await run("kimi:session-b");
    assert.deepEqual(senders, ["kimi:session-a", "kimi:session-a", "kimi:session-b"]);
    assert.equal(posts.length, 3);
    // Sequential boundaries for one consumer keep one stable key.
    assert.equal(posts[0], posts[1]);
    // Distinct resolved consumers can never collide on the availability key.
    assert.notEqual(posts[0], posts[2]);
    assert.equal(posts[0], "kimi:session-a:available");
    assert.equal(posts[2], "kimi:session-b:available");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("MCP poll failure does not invent a filesystem bus", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-nofallback-"));
  const durable = {
    name: "repo-memory",
    async poll() { throw new Error("gateway unavailable"); },
    async ack() {},
    async post() {},
    async close() {},
  };

  try {
    const result = await runHook({
      client: "kimi-code",
      eventName: "UserPromptSubmit",
      payload: { cwd: "/workspace" },
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    assert.equal(result.output, null);
    assert.equal(result.deliveries.length, 0);
    assert.match(result.errors[0]?.error ?? "", /gateway unavailable/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("session alias selection uses the first non-blank trimmed alias", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-alias-"));
  try {
    const options = { stateDir, workspace: "engine" };
    // A blank earlier alias must not mask a valid later alias.
    assert.equal(
      consumerFor("codex", {}, { payload: { session_id: "", sessionId: "later-session" }, ...options }),
      `codex-${sessionDigest("later-session")}`,
    );
    assert.equal(
      consumerFor("codex", {}, { payload: { session_id: "   ", conversation_id: "conv-session" }, ...options }),
      `codex-${sessionDigest("conv-session")}`,
    );
    // Surrounding whitespace on the chosen alias is normalized before digesting.
    assert.equal(
      consumerFor("codex", {}, { payload: { session_id: "  padded-session  " }, ...options }),
      `codex-${sessionDigest("padded-session")}`,
    );
    // payload:null is accepted as no payload and falls back without throwing.
    const fallback = consumerFor("codex", {}, { payload: null, ...options });
    assert.match(fallback, /^codex-[0-9a-f]{32}$/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("derived session digest is a 128-bit collision-resistant suffix with a pinned known answer", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-digest128-"));
  try {
    const consumer = consumerFor("codex", {}, { payload: { session_id: "swarm-known-answer-session" }, stateDir, workspace: "engine" });
    // Known-answer vector pins the digest algorithm itself: sha256 of the
    // whole session id, truncated to 32 lowercase hex characters (128 bits).
    assert.equal(consumer, "codex-b9711e8065e5f58368de3234734eda20");
    assert.match(consumer, /^codex-[0-9a-f]{32}$/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("non-string session ids are treated as absent instead of collapsing to one digest", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-objectid-"));
  try {
    const options = { stateDir, workspace: "engine" };
    const fallback = consumerFor("codex", {}, { payload: {}, ...options });
    for (const bogus of [{ nested: 1 }, { other: 2 }, ["array-session"], true]) {
      assert.equal(
        consumerFor("codex", {}, { payload: { session_id: bogus }, ...options }),
        fallback,
      );
    }
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("explicit identity normalizes surrounding whitespace and keeps the internal value opaque", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-whitespace-"));
  try {
    const options = { stateDir, workspace: "engine" };
    assert.equal(
      consumerFor("codex", { REPO_MEMORY_SWARM_CONSUMER: "  ops lead:alpha  " }, options),
      "ops lead:alpha",
    );
    assert.equal(
      consumerFor("codex", { SE_WORKSPACE_OWNER: "\towner:beta\n" }, options),
      "owner:beta",
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("explicit consumers with equal readable prefixes keep distinct state files and independent ack state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-safepart-"));
  const messageA = { ...message, id: "aaaa0000-0000-4000-8000-0000000000a1", recipient: "a:b" };
  const messageB = { ...message, id: "bbbb0000-0000-4000-8000-0000000000b2", recipient: "a-b" };
  const acks = [];
  let live = true;
  const durable = {
    name: "repo-memory",
    async poll(_workspace, consumer) {
      if (!live) return [];
      return consumer === "a:b" ? [messageA] : [messageB];
    },
    async ack(_workspace, consumer, delivery) { acks.push(`${consumer}:${delivery.id}`); },
    async post() {},
    async close() {},
  };
  const run = (consumer) => runHook({
    client: "codex",
    eventName: "UserPromptSubmit",
    payload: { cwd: "/workspace" },
    workspace: "engine",
    stateDir,
    buses: [durable],
    env: { REPO_MEMORY_SWARM_CONSUMER: consumer },
  });

  try {
    await run("a:b");
    await run("a-b");
    assert.deepEqual(acks, []);
    // `a:b` and `a-b` sanitize to the same readable prefix (`a-b`); the
    // 128-bit digest of the full opaque consumer keeps their deferred-ack
    // state in distinct files.
    const files = (await readdir(stateDir)).sort();
    assert.equal(files.length, 2);
    for (const file of files) {
      assert.match(file, /^a-b-[0-9a-f]{32}--engine\.json$/);
    }

    live = false;
    await run("a:b");
    await run("a-b");
    assert.deepEqual(acks.sort(), [`a-b:${messageB.id}`, `a:b:${messageA.id}`]);
    for (const file of files) {
      assert.equal(JSON.parse(await readFile(join(stateDir, file), "utf8")).pending.length, 0);
    }
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("legacy client-keyed state file is left unchanged and not used for ack state", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-legacy-"));
  const legacyPath = join(stateDir, "codex--engine.json");
  const legacyBytes = `${JSON.stringify({ schema: "repo-memory-hook-state/v1", pending: [{ bus: "repo-memory", message_id: message.id }] }, null, 2)}\n`;
  await writeFile(legacyPath, legacyBytes);
  const acks = [];
  const durable = {
    name: "repo-memory",
    async poll() { return []; },
    async ack(_workspace, consumer, delivery) { acks.push(`${consumer}:${delivery.id}`); },
    async post() {},
    async close() {},
  };

  try {
    const payload = { cwd: "/workspace", session_id: "1c1a0e5e-0000-4000-8000-000000000001" };
    const run = () => runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "engine",
      stateDir,
      buses: [durable],
      env: {},
    });
    // Two boundaries: if the legacy client-keyed file were used for ack
    // state, the second boundary would acknowledge its pending entry.
    await run();
    await run();
    assert.deepEqual(acks, []);
    // The legacy file's bytes are untouched.
    assert.equal(await readFile(legacyPath, "utf8"), legacyBytes);
    // The new consumer writes its own digest-keyed state file instead.
    const files = (await readdir(stateDir)).filter((name) => name !== "codex--engine.json");
    assert.equal(files.length, 1);
    assert.match(files[0], /^codex-[0-9a-f]{32}-[0-9a-f]{32}--engine\.json$/);
    assert.deepEqual(JSON.parse(await readFile(join(stateDir, files[0]), "utf8")).pending, []);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("an empty persisted fallback file is healed once instead of replaying fresh identities", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-consumer-heal-"));
  try {
    const fallbackPath = join(stateDir, "codex--engine.consumer");
    // A crashed writer can leave an empty/partial file behind.
    await writeFile(fallbackPath, "");
    const first = consumerFor("codex", {}, { payload: {}, stateDir, workspace: "engine" });
    const second = consumerFor("codex", {}, { payload: {}, stateDir, workspace: "engine" });
    assert.equal(first, second);
    assert.match(first, /^codex-[0-9a-f]{32}$/);
    const healed = (await readFile(fallbackPath, "utf8")).trim();
    assert.notEqual(healed, "");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});
