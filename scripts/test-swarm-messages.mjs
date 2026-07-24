import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import test from "node:test";

import {
  McpGatewayClient,
  RepoMemoryBus,
  createContext,
  renderClientOutput,
  runHook,
  selectWorkspace,
} from "../config/codex/hooks/swarm-messages.mjs";

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

const consumerForSession = (client, sessionID, prefix = client) => {
  const normalized = sessionID.replace(/[^A-Za-z0-9]+/g, "");
  const digest = createHash("sha256").update(normalized).digest("hex").slice(0, 16);
  return `${prefix}-${digest}`;
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
  const primaryLane = join(base, "worktrees", "singularity-engine", "executor-kernel");
  const other = join(base, "dotfiles");
  const otherLane = join(base, "worktrees", "dotfiles", "swarm-hook");
  try {
    await mkdir(join(primary, "fabrics", "inference"), { recursive: true });
    await mkdir(join(primary, ".jj", "repo"), { recursive: true });
    await mkdir(join(primaryLane, ".jj"), { recursive: true });
    await mkdir(join(primaryLane, "engine", "workflow"), { recursive: true });
    await writeFile(
      join(primaryLane, ".jj", "repo"),
      `${relative(join(primaryLane, ".jj"), join(primary, ".jj", "repo"))}\n`,
    );
    await mkdir(join(other, "home", "modules"), { recursive: true });
    await mkdir(join(other, ".git", "worktrees", "swarm-hook"), { recursive: true });
    await mkdir(join(otherLane, "config", "codex"), { recursive: true });
    await writeFile(
      join(otherLane, ".git"),
      `gitdir: ${join(other, ".git", "worktrees", "swarm-hook")}\n`,
    );
    await writeFile(join(other, ".git", "worktrees", "swarm-hook", "commondir"), "../..\n");

    assert.deepEqual(
      selectWorkspace(join(primary, "fabrics", "inference"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "singularity-engine", worktree: primary },
    );
    assert.deepEqual(
      selectWorkspace(join(primaryLane, "engine", "workflow"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "singularity-engine", worktree: primaryLane },
    );
    assert.deepEqual(
      selectWorkspace(join(other, "home", "modules"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "dotfiles", worktree: other },
    );
    assert.deepEqual(
      selectWorkspace(join(otherLane, "config", "codex"), { SWARM_PRIMARY_WORKSPACE: primary }),
      { identity: "dotfiles", worktree: otherLane },
    );
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("session start uses a unique consumer and records the active worktree", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-session-"));
  const calls = [];
  const durable = {
    name: "repo-memory",
    async subscribe(workspace, consumer) { calls.push({ operation: "subscribe", workspace, consumer }); },
    async poll() { return []; },
    async ack() {},
    async post(workspace, posted) {
      calls.push({ operation: "post", workspace, posted });
    },
    async close() {},
  };

  try {
    await runHook({
      client: "codex",
      eventName: "SessionStart",
      payload: {
        cwd: "/home/mhugo/code/worktrees/jj/singularity-engine/executor-kernel",
        session_id: "019f91dd-3c90-7be0-ab98-63ef80c9a803",
      },
      workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"],
      worktree: "/home/mhugo/code/worktrees/jj/singularity-engine/executor-kernel",
      stateDir,
      buses: [durable],
      env: { REPO_MEMORY_SWARM_CONSUMER: "shared-prefix" },
    });
    await runHook({
      client: "codex",
      eventName: "SessionStart",
      payload: {
        cwd: "/home/mhugo/code/worktrees/jj/singularity-engine/c21-review",
        thread_id: "019f91dd-a12b-4470-b433-17ea04a6b211",
      },
      workspace: "singularity-engine",
      additionalWorkspaces: ["c21-review"],
      worktree: "/home/mhugo/code/worktrees/jj/singularity-engine/c21-review",
      stateDir,
      buses: [durable],
      env: { REPO_MEMORY_SWARM_CONSUMER: "shared-prefix" },
    });

    const firstConsumer = consumerForSession(
      "codex",
      "019f91dd-3c90-7be0-ab98-63ef80c9a803",
      "shared-prefix",
    );
    const secondConsumer = consumerForSession(
      "codex",
      "019f91dd-a12b-4470-b433-17ea04a6b211",
      "shared-prefix",
    );
    const subscriptions = calls.filter(({ operation }) => operation === "subscribe");
    assert.deepEqual(subscriptions.map(({ workspace }) => workspace), [
      "singularity-engine",
      "executor-kernel",
      "singularity-engine",
      "c21-review",
    ]);
    assert.deepEqual(subscriptions.map(({ consumer }) => consumer), [
      firstConsumer,
      firstConsumer,
      secondConsumer,
      secondConsumer,
    ]);
    assert.equal(new Set(subscriptions.map(({ consumer }) => consumer)).size, 2);
    const posts = calls.filter(({ operation }) => operation === "post");
    assert.deepEqual(posts.map(({ workspace }) => workspace), ["singularity-engine", "singularity-engine"]);
    assert.equal(posts[0].posted.sender, firstConsumer);
    assert.equal(posts[0].posted.idempotency_key, `${firstConsumer}:available`);
    assert.equal(posts[1].posted.idempotency_key, `${secondConsumer}:available`);
    assert.deepEqual(posts[0].posted.metadata, {
      worktree: "/home/mhugo/code/worktrees/jj/singularity-engine/executor-kernel",
      lane: "executor-kernel",
    });
  } finally {
    await rm(stateDir, { recursive: true, force: true });
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

test("MCP transport initializes and calls the lazy repo-memory subscription route", async (t) => {
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
  const bus = new RepoMemoryBus(client);
  await Promise.all([
    bus.subscribe("engine", "codex"),
    bus.subscribe("executor-kernel", "codex"),
  ]);
  await client.close();

  assert.equal(methods.filter((method) => method === "initialize").length, 1);
  assert.equal(methods.filter((method) => method === "notifications/initialized").length, 1);
  assert.equal(methods.filter((method) => method === "tools/call").length, 2);
  assert.deepEqual(methods.slice(0, 2), ["initialize", "notifications/initialized"]);
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

  const later = { ...message, id: "symlink-later", body: "New work after bootstrap." };
  let pollCount = 0;
  let subscribeCount = 0;
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
    const tool = rpc.params?.arguments?.tool;
    let toolResult = {};
    if (tool === "swarm_bus_subscribe") {
      subscribeCount += 1;
      toolResult = { cursor: 7, created: subscribeCount === 1 };
    } else if (tool === "swarm_bus_poll") {
      pollCount += 1;
      toolResult = { messages: pollCount === 1 ? [later] : [], next_cursor: pollCount };
    }
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify(toolResult) }] };
    response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => server.close());
  t.after(() => rm(base, { recursive: true, force: true }));

  const address = server.address();
  const options = {
    cwd: base,
    env: {
      ...process.env,
      MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
      REPO_MEMORY_SWARM_WORKSPACE: "symlink-live-proof",
      REPO_MEMORY_SWARM_CONSUMER: "codex-symlink1",
      SE_WORKSPACE_OWNER: "codex:symlink1",
      REPO_MEMORY_SWARM_STATE_DIR: stateDir,
    },
    timeout: 5_000,
  };
  const bootstrap = await execFileWithClosedInput(link, ["codex", "UserPromptSubmit"], options);
  assert.equal(bootstrap.stdout, "");
  const delivered = await execFileWithClosedInput(link, ["codex", "UserPromptSubmit"], options);
  assert.match(delivered.stdout, /New work after bootstrap/);
  assert.equal(subscribeCount, 1);
});

test("delivery is acknowledged only at the next observed hook boundary", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-state-"));
  const calls = [];
  let phase = "bootstrap";
  const durable = {
    name: "repo-memory",
    async subscribe(workspace) { calls.push(`subscribe:${workspace}`); },
    async poll(workspace) {
      calls.push(`poll:${workspace}`);
      return phase === "deliver" && workspace === "executor-kernel" ? [message] : [];
    },
    async ack(workspace, _consumer, delivery) {
      calls.push(`ack:${workspace}:${delivery.id}`);
    },
    async post() { calls.push("post"); },
    async close() {},
  };

  try {
    const payload = { cwd: "/workspace", session_id: "019f91dd-3c90-7be0-ab98-63ef80c9a803" };
    const bootstrap = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"],
      stateDir,
      buses: [durable],
    });
    assert.equal(bootstrap.output, null);
    assert.deepEqual(calls, ["subscribe:singularity-engine", "subscribe:executor-kernel"]);

    calls.length = 0;
    phase = "deliver";
    const first = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"],
      stateDir,
      buses: [durable],
    });
    assert.match(JSON.stringify(first.output), /Review revision abc123/);
    assert.deepEqual(calls, ["poll:singularity-engine", "poll:executor-kernel"]);

    phase = "empty";
    const second = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"],
      stateDir,
      buses: [durable],
    });
    assert.equal(second.output, null);
    assert.deepEqual(calls, [
      "poll:singularity-engine",
      "poll:executor-kernel",
      `ack:executor-kernel:${message.id}`,
      "poll:singularity-engine",
      "poll:executor-kernel",
    ]);
    const consumer = consumerForSession("codex", "019f91dd-3c90-7be0-ab98-63ef80c9a803");
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).pending.length,
      0,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("an acknowledgement failure blocks later acknowledgements on the same cursor", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-ack-order-"));
  const payload = { cwd: "/workspace", session_id: "ack-order-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const stateFile = join(stateDir, `${consumer}--singularity-engine.json`);
  const calls = [];
  let failFirst = true;
  const durable = {
    name: "repo-memory",
    async poll(workspace) { calls.push(`poll:${workspace}`); return []; },
    async ack(workspace, _consumer, delivery) {
      calls.push(`ack:${workspace}:${delivery.id}`);
      if (failFirst && delivery.id === "first") throw new Error("first ack unavailable");
    },
    async post() {},
    async close() {},
  };

  try {
    await writeFile(stateFile, `${JSON.stringify({
      schema: "repo-memory-hook-state/v1",
      initialized: true,
      availability_pending: false,
      pending: [
        { bus: "repo-memory", workspace: "executor-kernel", message_id: "first" },
        { bus: "repo-memory", workspace: "executor-kernel", message_id: "second" },
      ],
    })}\n`);

    const failed = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(failed.errors[0]?.operation, "ack");
    assert.deepEqual(calls, [
      "ack:executor-kernel:first",
      "poll:singularity-engine",
      "poll:executor-kernel",
    ]);
    assert.deepEqual(JSON.parse(await readFile(stateFile, "utf8")).pending.map(
      ({ message_id: messageID }) => messageID,
    ), ["first", "second"]);

    failFirst = false;
    calls.length = 0;
    await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.deepEqual(calls, [
      "ack:executor-kernel:first",
      "ack:executor-kernel:second",
      "poll:singularity-engine",
      "poll:executor-kernel",
    ]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("first-run subscribes canonical and lane scopes before announcing availability", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-bootstrap-"));
  const calls = [];
  const durable = {
    name: "repo-memory",
    async subscribe(workspace, consumer) { calls.push({ operation: "subscribe", workspace, consumer }); },
    async poll() { throw new Error("first run must not poll history"); },
    async ack() { throw new Error("first run must not acknowledge history"); },
    async post(workspace, posted) {
      calls.push({ operation: "post", workspace, posted });
    },
    async close() {},
  };
  const payload = { cwd: "/workspace", session_id: "bootstrap-session" };
  const consumer = consumerForSession("codex", payload.session_id);

  try {
    const boot = await runHook({
      client: "codex", eventName: "SessionStart", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(boot.output, null);
    assert.deepEqual(calls.map(({ operation, workspace, consumer: calledConsumer }) => (
      { operation, workspace, consumer: calledConsumer }
    )), [
      { operation: "subscribe", workspace: "singularity-engine", consumer },
      { operation: "subscribe", workspace: "executor-kernel", consumer },
      { operation: "post", workspace: "singularity-engine", consumer: undefined },
    ]);
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).initialized,
      true,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("corrupt local state safely re-subscribes without advancing a server cursor", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-subscribe-"));
  const later = { ...message, id: "post-subscription", body: "Posted after the subscription cutoff." };
  const calls = [];
  let phase = "bootstrap";
  const cursors = new Map();
  const durable = {
    name: "repo-memory",
    async subscribe(workspace, consumer) {
      const key = `${workspace}:${consumer}`;
      const created = !cursors.has(key);
      const cursor = cursors.get(key) ?? 41;
      cursors.set(key, cursor);
      calls.push(`subscribe:${key}:${cursor}`);
      return { workspace, consumer, cursor, created };
    },
    async poll(workspace) {
      calls.push(`poll:${workspace}`);
      return phase === "later" && workspace === "executor-kernel" ? [later] : [];
    },
    async ack() {},
    async post() {},
    async close() {},
  };
  const payload = { cwd: "/workspace", session_id: "subscribe-session" };
  const consumer = consumerForSession("codex", payload.session_id);

  try {
    const bootstrap = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(bootstrap.output, null);
    assert.deepEqual(calls, [
      `subscribe:singularity-engine:${consumer}:41`,
      `subscribe:executor-kernel:${consumer}:41`,
    ]);
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).initialized,
      true,
    );

    await writeFile(join(stateDir, `${consumer}--singularity-engine.json`), "{}\n");
    calls.length = 0;
    const retried = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(retried.output, null);
    assert.deepEqual(calls, [
      `subscribe:singularity-engine:${consumer}:41`,
      `subscribe:executor-kernel:${consumer}:41`,
    ]);
    assert.deepEqual([...cursors.values()], [41, 41]);

    await writeFile(
      join(stateDir, `${consumer}--singularity-engine.json`),
      `${JSON.stringify({ schema: "repo-memory-hook-state/v1", pending: {} })}\n`,
    );
    calls.length = 0;
    const invalidPending = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(invalidPending.output, null);
    assert.deepEqual(calls, [
      `subscribe:singularity-engine:${consumer}:41`,
      `subscribe:executor-kernel:${consumer}:41`,
    ]);

    phase = "later";
    calls.length = 0;
    const delivered = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.match(JSON.stringify(delivered.output), /Posted after the subscription cutoff/);
    assert.deepEqual(calls, ["poll:singularity-engine", "poll:executor-kernel"]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("subscription failure keeps state uninitialized, silent, and retryable", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-bootstrap-failure-"));
  const calls = [];
  let failSubscribe = true;
  const durable = {
    name: "repo-memory",
    async subscribe(workspace) {
      calls.push({ operation: "subscribe", workspace });
      if (failSubscribe && workspace === "executor-kernel") throw new Error("subscribe unavailable");
    },
    async poll() { throw new Error("subscription failure must not poll"); },
    async ack() {},
    async post(workspace, posted) { calls.push({ operation: "post", workspace, key: posted.idempotency_key }); },
    async close() {},
  };
  const payload = { cwd: "/workspace", session_id: "bootstrap-failure-session" };
  const consumer = consumerForSession("codex", payload.session_id);

  try {
    const result = await runHook({
      client: "codex", eventName: "SessionStart", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(result.output, null);
    assert.deepEqual(calls, [
      { operation: "subscribe", workspace: "singularity-engine" },
      { operation: "subscribe", workspace: "executor-kernel" },
    ]);
    assert.equal(result.errors[0]?.operation, "subscribe");
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).initialized,
      false,
    );

    failSubscribe = false;
    calls.length = 0;
    const retried = await runHook({
      client: "codex", eventName: "SessionStart", payload, workspace: "singularity-engine",
      additionalWorkspaces: ["executor-kernel"], stateDir, buses: [durable],
    });
    assert.equal(retried.output, null);
    assert.deepEqual(calls, [
      { operation: "subscribe", workspace: "singularity-engine" },
      { operation: "subscribe", workspace: "executor-kernel" },
      { operation: "post", workspace: "singularity-engine", key: `${consumer}:available` },
    ]);
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).initialized,
      true,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("availability failure remains retryable with the same idempotency key", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-availability-failure-"));
  const payload = { cwd: "/workspace", session_id: "availability-failure-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const calls = [];
  let failPost = true;
  const durable = {
    name: "repo-memory",
    async subscribe(workspace) { calls.push(`subscribe:${workspace}`); },
    async poll() { return []; },
    async ack() {},
    async post(_workspace, posted) {
      calls.push(`post:${posted.idempotency_key}`);
      if (failPost) throw new Error("availability unavailable");
    },
    async close() {},
  };

  try {
    const first = await runHook({
      client: "codex", eventName: "SessionStart", payload, workspace: "singularity-engine", stateDir, buses: [durable],
    });
    assert.equal(first.output, null);
    assert.equal(first.errors[0]?.operation, "post");
    assert.equal(JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).initialized, false);

    failPost = false;
    const second = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine", stateDir, buses: [durable],
    });
    assert.equal(second.output, null);
    assert.deepEqual(calls, [
      "subscribe:singularity-engine",
      `post:${consumer}:available`,
      "subscribe:singularity-engine",
      `post:${consumer}:available`,
    ]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("pre-bootstrap state files remain initialized during upgrade", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-bootstrap-migration-"));
  const payload = { cwd: "/workspace", session_id: "bootstrap-migration-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const stateFile = join(stateDir, `${consumer}--singularity-engine.json`);
  const later = { ...message, id: "migration-later", body: "Message after hook upgrade." };
  const calls = [];
  const durable = {
    name: "repo-memory",
    async poll() { calls.push("poll"); return [later]; },
    async ack(_workspace, _consumer, delivery) { calls.push(`ack:${delivery.id}`); },
    async post() {},
    async close() {},
  };

  try {
    await writeFile(stateFile, `${JSON.stringify({ schema: "repo-memory-hook-state/v1", pending: [] })}\n`);
    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      stateDir, buses: [durable],
    });
    assert.match(JSON.stringify(result.output), /Message after hook upgrade/);
    assert.deepEqual(calls, ["poll"]);
    assert.equal(JSON.parse(await readFile(stateFile, "utf8")).initialized, true);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("MCP subscription failure does not invent a filesystem bus", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-nofallback-"));
  const payload = { cwd: "/workspace", session_id: "d3904cf4-f31a-47cd-b60b-0dbc2b5a8a77" };
  const consumer = consumerForSession("kimi-code", payload.session_id);
  const durable = {
    name: "repo-memory",
    async subscribe() { throw new Error("gateway unavailable"); },
    async poll() { throw new Error("poll must not run before subscription"); },
    async ack() {},
    async post() {},
    async close() {},
  };

  try {
    const result = await runHook({
      client: "kimi-code",
      eventName: "UserPromptSubmit",
      payload,
      workspace: "engine",
      stateDir,
      buses: [durable],
    });
    assert.equal(result.output, null);
    assert.equal(result.deliveries.length, 0);
    assert.match(result.errors[0]?.error ?? "", /gateway unavailable/);
    assert.equal(
      JSON.parse(await readFile(join(stateDir, `${consumer}--engine.json`), "utf8")).initialized,
      false,
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});
