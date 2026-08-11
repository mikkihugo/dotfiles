import assert from "node:assert/strict";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { chmod, lstat, mkdir, mkdtemp, readFile, readdir, rm, stat, symlink, writeFile } from "node:fs/promises";
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

const writeInitializedState = (stateDir, consumer, workspace = "singularity-engine", pending = []) => writeFile(
  join(stateDir, `${consumer}--${workspace}.json`),
  `${JSON.stringify({
    schema: "repo-memory-hook-state/v1",
    initialized: true,
    availability_pending: false,
    pending,
  })}\n`,
);

const messageBus = (counter) => ({
  name: "repo-memory",
  async subscribe() {},
  async poll() {
    counter.count += 1;
    return [message];
  },
  async ack() {},
  async post() {},
  async close() {},
});

function execFileWithClosedInput(file, args, options) {
  return new Promise((resolve, reject) => {
    const child = execFileCallback(file, args, options, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
    child.stdin.end();
  });
}

function holdKernelLock(lockPath) {
  const readyMarker = "repo-memory-hook-lock-acquired";
  const child = spawn(
    process.env.FLOCK_BIN ?? "flock",
    [
      "--exclusive",
      "--nonblock",
      "--conflict-exit-code",
      "75",
      "--no-fork",
      lockPath,
      "bash",
      "-c",
      `printf '${readyMarker}\\n'; IFS= read -r _ || true`,
    ],
    { stdio: ["pipe", "pipe", "pipe"] },
  );
  let stderr = "";
  let output = "";
  let ready = false;
  const closed = new Promise((resolve) => {
    child.once("close", (code, signal) => resolve({ code, signal }));
  });

  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.stdout.on("data", (chunk) => {
      output += chunk;
      if (ready || !output.includes(readyMarker)) return;
      ready = true;
      resolve({
        async release() {
          child.stdin.end();
          const result = await closed;
          assert.equal(result.code, 0, `kernel lock holder failed: ${stderr}`);
        },
      });
    });
    child.once("close", (code, signal) => {
      if (!ready) reject(new Error(`kernel lock holder exited before readiness: code=${code} signal=${signal} ${stderr}`));
    });
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

  const factory = renderClientOutput("factory", "UserPromptSubmit", context, {});
  assert.equal(factory.hookSpecificOutput.hookEventName, "UserPromptSubmit");
  assert.equal(factory.hookSpecificOutput.additionalContext, context);

  const durableContext = createContext([{ ...message, timestamp: undefined, created_at: "2026-07-19T16:00:01Z" }]);
  assert.match(durableContext, /2026-07-19T16:00:01Z claude -> codex/);
});

// jcode announces itself but never subscribes or polls. Its session_start hook
// is an OBSERVER -- "spawned detached, fire-and-forget" per jcode/docs/HOOKS.md
// -- so its stdout is never consumed and it can never receive a bus message.
// Subscribing anyway created a durable cursor that could never advance (only
// acking advances it, and it can never ack), and such a cursor pins the
// workspace-wide delivered-retention floor for as long as it exists.
test("JCode announces availability without creating a consumer cursor it can never advance", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-jcode-session-"));
  const subscribes = [];
  const polls = [];
  const posts = [];
  const durable = {
    name: "repo-memory",
    async subscribe(workspace, consumer) { subscribes.push({ workspace, consumer }); },
    async poll(workspace) { polls.push(workspace); return []; },
    async ack() {},
    async post(workspace, message) { posts.push({ workspace, sender: message.sender }); },
    async close() {},
  };
  try {
    await runHook({
      client: "jcode",
      eventName: "SessionStart",
      payload: {},
      workspace: "singularity-engine",
      stateDir,
      buses: [durable],
      env: { JCODE_HOOK_SESSION_ID: "session-rooster-1234" },
    });
    assert.deepEqual(subscribes, [], "jcode must not create a cursor it can never advance");
    assert.deepEqual(polls, [], "jcode cannot receive, so polling only costs a round trip");
    // The identity is still derived from the native session id, and is still
    // used: availability is posted, which needs no stdout.
    assert.deepEqual(posts, [{
      workspace: "singularity-engine",
      sender: consumerForSession("jcode", "session-rooster-1234"),
    }]);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
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
      // The source fixture deliberately retains `@bash@`. Its fallback must
      // resolve Bash through PATH rather than trusting a non-existent shell
      // path inherited by Nix-aware agent launchers.
      SHELL: "/definitely-missing-shell",
    },
    timeout: 5_000,
  };
  const bootstrap = await execFileWithClosedInput(link, ["codex", "UserPromptSubmit"], options);
  assert.equal(bootstrap.stdout, "");
  const delivered = await execFileWithClosedInput(link, ["codex", "UserPromptSubmit"], options);
  assert.match(delivered.stdout, /New work after bootstrap/);
  assert.equal(subscribeCount, 1);
});

test("separate hook processes serialize one durable delivery", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "repo-memory-hook-processes-"));
  const target = join(base, "swarm-messages.mjs");
  const stateDir = join(base, "state");
  const source = await readFile(new URL("../config/codex/hooks/swarm-messages.mjs", import.meta.url), "utf8");
  await writeFile(target, source.replace("#!@node@", `#!${process.execPath}`));
  await chmod(target, 0o555);

  const later = { ...message, id: "process-later", body: "One process owns this delivery." };
  let pollCalls = 0;
  let ackCalls = 0;
  let releaseFirstPoll;
  const firstPollStarted = new Promise((resolve) => { releaseFirstPoll = resolve; });
  let firstPollReady;
  const firstPollIsReady = new Promise((resolve) => { firstPollReady = resolve; });
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
    response.setHeader("Mcp-Session-Id", "process-lock-test-session");
    const tool = rpc.params?.arguments?.tool;
    let toolResult = {};
    if (tool === "swarm_bus_subscribe") {
      toolResult = { cursor: 7, created: true };
    } else if (tool === "swarm_bus_poll") {
      pollCalls += 1;
      if (pollCalls === 1) {
        firstPollReady();
        await firstPollStarted;
        toolResult = { messages: [later], next_cursor: 1 };
      } else {
        toolResult = { messages: [], next_cursor: pollCalls };
      }
    } else if (tool === "swarm_bus_ack") {
      ackCalls += 1;
    }
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify(toolResult) }] };
    response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result }));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

  let first;
  t.after(async () => {
    releaseFirstPoll();
    if (first) await first.catch(() => {});
    await new Promise((resolve) => server.close(resolve));
    await rm(base, { recursive: true, force: true });
  });

  const address = server.address();
  const options = {
    cwd: base,
    env: {
      ...process.env,
      MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
      REPO_MEMORY_SWARM_WORKSPACE: "process-lock-proof",
      REPO_MEMORY_SWARM_CONSUMER: "codex-process-lock",
      SE_WORKSPACE_OWNER: "codex:process-lock",
      REPO_MEMORY_SWARM_STATE_DIR: stateDir,
    },
    timeout: 5_000,
  };
  const bootstrap = await execFileWithClosedInput(target, ["codex", "UserPromptSubmit"], options);
  assert.equal(bootstrap.stdout, "");
  const stateFiles = (await readdir(stateDir)).filter((file) => file.endsWith(".json"));
  assert.equal(stateFiles.length, 1);
  const stateFile = join(stateDir, stateFiles[0]);
  const initialState = await readFile(stateFile, "utf8");

  first = execFileWithClosedInput(target, ["codex", "UserPromptSubmit"], options);
  await firstPollIsReady;
  const contender = await execFileWithClosedInput(target, ["codex", "UserPromptSubmit"], options);
  assert.equal(await readFile(stateFile, "utf8"), initialState);
  assert.equal(ackCalls, 0);
  releaseFirstPoll();
  const delivered = await first;

  assert.match(delivered.stdout, /One process owns this delivery/);
  assert.equal(contender.stdout, "");
  assert.equal(pollCalls, 1);
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

test("overlapping hook invocations emit one durable delivery once", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-overlap-"));
  const payload = { cwd: "/workspace", session_id: "overlap-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  let markPollStarted;
  let releasePoll;
  const pollStarted = new Promise((resolve) => { markPollStarted = resolve; });
  const pollReleased = new Promise((resolve) => { releasePoll = resolve; });
  let pollCalls = 0;
  let emitted = 0;
  const durable = {
    name: "repo-memory",
    async subscribe() {},
    async poll() {
      pollCalls += 1;
      markPollStarted();
      await pollReleased;
      return [message];
    },
    async ack() {},
    async post() {},
    async close() {},
  };

  try {
    await writeInitializedState(stateDir, consumer);
    const first = runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [durable],
      emitOutput: async () => { emitted += 1; },
    });
    await pollStarted;
    const contender = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [durable],
      emitOutput: async () => { emitted += 1; },
    });
    releasePoll();
    const delivered = await first;

    assert.match(JSON.stringify(delivered.output), /Review revision abc123/);
    assert.equal(contender.output, null);
    assert.equal(pollCalls, 1);
    assert.equal(emitted, 1);
    assert.deepEqual(
      JSON.parse(await readFile(join(stateDir, `${consumer}--singularity-engine.json`), "utf8")).pending,
      [{ bus: "repo-memory", workspace: "singularity-engine", message_id: message.id }],
    );
    assert.equal(existsSync(join(stateDir, `${consumer}--singularity-engine.json.lock`)), true);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a contending hook does not repeat the active acknowledgement", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-overlap-ack-"));
  const payload = { cwd: "/workspace", session_id: "overlap-ack-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  let markAckStarted;
  let releaseAck;
  const ackStarted = new Promise((resolve) => { markAckStarted = resolve; });
  const ackReleased = new Promise((resolve) => { releaseAck = resolve; });
  let ackCalls = 0;
  let pollCalls = 0;
  const durable = {
    name: "repo-memory",
    async subscribe() {},
    async poll() { pollCalls += 1; return []; },
    async ack() {
      ackCalls += 1;
      markAckStarted();
      await ackReleased;
    },
    async post() {},
    async close() {},
  };

  try {
    await writeInitializedState(stateDir, consumer, "singularity-engine", [{
      bus: "repo-memory", workspace: "singularity-engine", message_id: "prior-delivery",
    }]);
    const first = runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [durable],
    });
    await ackStarted;
    const contender = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [durable],
    });
    releaseAck();
    await first;

    assert.equal(contender.output, null);
    assert.equal(ackCalls, 1);
    assert.equal(pollCalls, 1);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a kernel-held stable state lock yields then allows delivery after owner exit", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-kernel-lock-"));
  const payload = { cwd: "/workspace", session_id: "kernel-lock-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const lockPath = join(stateDir, `${consumer}--singularity-engine.json.lock`);
  const counter = { count: 0 };
  let holder;

  try {
    await writeInitializedState(stateDir, consumer);
    holder = await holdKernelLock(lockPath);
    const inode = (await stat(lockPath)).ino;
    const contended = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
    });

    assert.equal(contended.output, null);
    assert.equal(counter.count, 0);
    assert.equal(existsSync(lockPath), true);

    await holder.release();
    holder = null;
    const delivered = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
    });

    assert.match(JSON.stringify(delivered.output), /Review revision abc123/);
    assert.equal(counter.count, 1);
    assert.equal(existsSync(lockPath), true);
    assert.equal((await stat(lockPath)).ino, inode);
  } finally {
    if (holder) await holder.release().catch(() => {});
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("killing a hook process releases its kernel lease for a replacement delivery", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-killed-owner-"));
  const payload = { cwd: "/workspace", session_id: "killed-owner-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const lockPath = join(stateDir, `${consumer}--singularity-engine.json.lock`);
  const runner = join(stateDir, "blocked-hook.mjs");
  const hookURL = new URL("../config/codex/hooks/swarm-messages.mjs", import.meta.url).href;
  let outer;
  let outerExited;

  try {
    await writeInitializedState(stateDir, consumer);
    await writeFile(runner, [
      `import { runHook } from ${JSON.stringify(hookURL)};`,
      "await runHook({",
      '  client: "codex", eventName: "UserPromptSubmit",',
      `  payload: ${JSON.stringify(payload)}, workspace: "singularity-engine",`,
      `  stateDir: ${JSON.stringify(stateDir)},`,
      "  buses: [{",
      '    name: "repo-memory", async subscribe() {},',
      '    async poll() { process.stdout.write("poll-started\\n"); await new Promise(() => {}); },',
      "    async ack() {}, async post() {}, async close() {},",
      "  }],",
      "});",
    ].join("\n"));
    outer = spawn(process.execPath, [runner], { stdio: ["ignore", "pipe", "pipe"] });
    outerExited = new Promise((resolve) => {
      outer.once("close", (code, signal) => resolve({ code, signal }));
    });
    let started = "";
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("outer hook did not reach poll")), 2_000);
      outer.once("error", reject);
      outer.stdout.on("data", (chunk) => {
        started += chunk;
        if (!started.includes("poll-started")) return;
        clearTimeout(timeout);
        resolve();
      });
    });
    const inode = (await stat(lockPath)).ino;
    outer.kill("SIGKILL");
    assert.equal((await outerExited).signal, "SIGKILL");

    const counter = { count: 0 };
    let delivered = { output: null };
    for (let attempt = 0; attempt < 20 && delivered.output === null; attempt += 1) {
      delivered = await runHook({
        client: "codex", eventName: "UserPromptSubmit", payload,
        workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
      });
      if (delivered.output === null) await new Promise((resolve) => setTimeout(resolve, 25));
    }

    assert.match(JSON.stringify(delivered.output), /Review revision abc123/);
    assert.equal(counter.count, 1);
    assert.equal((await stat(lockPath)).ino, inode);
  } finally {
    if (outer && outer.exitCode === null && outer.signalCode === null) {
      outer.kill("SIGKILL");
      await outerExited;
    }
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a legacy state-lock directory fails closed without being moved", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-legacy-lock-"));
  const payload = { cwd: "/workspace", session_id: "legacy-lock-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const lockPath = join(stateDir, `${consumer}--singularity-engine.json.lock`);
  const counter = { count: 0 };

  try {
    await writeInitializedState(stateDir, consumer);
    await mkdir(lockPath);
    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
    });

    assert.equal(result.output, null);
    assert.equal(counter.count, 0);
    assert.equal(existsSync(lockPath), true);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a symlinked state lock fails closed without following it", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-symlink-lock-"));
  const payload = { cwd: "/workspace", session_id: "symlink-lock-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const lockPath = join(stateDir, `${consumer}--singularity-engine.json.lock`);
  const target = join(stateDir, "legacy-lock-target");
  const counter = { count: 0 };

  try {
    await writeInitializedState(stateDir, consumer);
    await writeFile(target, "legacy lock target\n");
    await symlink(target, lockPath);
    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
    });

    assert.equal(result.output, null);
    assert.equal(counter.count, 0);
    assert.equal((await lstat(lockPath)).isSymbolicLink(), true);
    assert.equal(await readFile(target, "utf8"), "legacy lock target\n");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a flock helper that never becomes ready times out without polling", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-acquire-timeout-"));
  const fakeBin = join(stateDir, "bin");
  const payload = { cwd: "/workspace", session_id: "acquire-timeout-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const counter = { count: 0 };
  const originalPath = process.env.PATH;
  const maxWaitMs = 1_500;

  try {
    await writeInitializedState(stateDir, consumer);
    await mkdir(fakeBin);
    const fakeFlock = join(fakeBin, "flock");
    await writeFile(fakeFlock, "#!/bin/sh\nexec sleep 10\n");
    await chmod(fakeFlock, 0o755);
    process.env.PATH = `${fakeBin}:${originalPath}`;
    const startedAt = Date.now();
    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload,
      workspace: "singularity-engine", stateDir, buses: [messageBus(counter)],
    });

    assert.equal(result.output, null);
    assert.equal(counter.count, 0);
    assert.ok(Date.now() - startedAt < maxWaitMs, "lock acquisition must not consume the native hook timeout");
  } finally {
    if (originalPath === undefined) delete process.env.PATH;
    else process.env.PATH = originalPath;
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

test("a purged message is settled, not retried, and does not block later acknowledgements", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-ack-purged-"));
  const payload = { cwd: "/workspace", session_id: "ack-purged-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const stateFile = join(stateDir, `${consumer}--singularity-engine.json`);
  const calls = [];
  const durable = {
    name: "repo-memory",
    async poll(workspace) { calls.push(`poll:${workspace}`); return []; },
    async ack(workspace, _consumer, delivery) {
      calls.push(`ack:${workspace}:${delivery.id}`);
      // Exactly what repo-memory returns once retention has deleted the message.
      if (delivery.id === "purged") {
        throw new Error("message_id not found in workspace or is not addressed to consumer");
      }
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
        { bus: "repo-memory", workspace: "executor-kernel", message_id: "purged" },
        { bus: "repo-memory", workspace: "executor-kernel", message_id: "later" },
      ],
    })}\n`);

    await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      stateDir, buses: [durable],
    });

    assert.ok(
      calls.includes("ack:executor-kernel:later"),
      "a purged message must not head-of-line-block the acknowledgement behind it",
    );
    const state = JSON.parse(await readFile(stateFile, "utf8"));
    assert.deepEqual(
      state.pending, [],
      "a purged message has nothing left to acknowledge and must be dropped, not retried forever",
    );
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a pending entry for a bus this build no longer registers is dropped", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-ack-unknownbus-"));
  const payload = { cwd: "/workspace", session_id: "ack-unknown-bus-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const stateFile = join(stateDir, `${consumer}--singularity-engine.json`);
  const durable = {
    name: "repo-memory",
    async poll() { return []; },
    async ack() {},
    async post() {},
    async close() {},
  };

  try {
    await writeFile(stateFile, `${JSON.stringify({
      schema: "repo-memory-hook-state/v1",
      initialized: true,
      availability_pending: false,
      // "filesystem" was retired; 20 such entries exist on this host and could
      // never be acknowledged, so they leaked on every run forever.
      pending: [{ bus: "filesystem", workspace: "singularity-engine", message_id: "orphan" }],
    })}\n`);

    await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      stateDir, buses: [durable],
    });

    const state = JSON.parse(await readFile(stateFile, "utf8"));
    assert.deepEqual(state.pending, [], "an unackable entry for an unregistered bus must be dropped");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

// Retention can reap an idle consumer's cursor. The server then reports
// known_consumer:false and returns everything it still holds from sequence 0,
// which is mostly history this identity already processed.
test("a reaped cursor re-subscribes at head instead of replaying the bus into the model", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-reaped-"));
  const payload = { cwd: "/workspace", session_id: "reaped-session" };
  const consumer = consumerForSession("codex", payload.session_id);
  const stateFile = join(stateDir, `${consumer}--singularity-engine.json`);
  const subscribes = [];
  const acks = [];
  const durable = {
    name: "repo-memory",
    async poll() {
      // Shape the real RepoMemoryBus.poll returns for an unknown identity.
      const messages = [{ id: "old-1", body: "ancient coordination", origin: "repo-memory" }];
      messages.knownConsumer = false;
      return messages;
    },
    async subscribe(workspace, who) { subscribes.push({ workspace, consumer: who }); },
    async ack(_w, _c, delivery) { acks.push(delivery.id); },
    async post() {},
    async close() {},
  };

  try {
    await writeFile(stateFile, `${JSON.stringify({
      schema: "repo-memory-hook-state/v1",
      initialized: true,
      availability_pending: false,
      pending: [],
    })}\n`);

    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      stateDir, buses: [durable],
    });

    assert.equal(result.output, null, "a replayed batch must not be rendered into the model as fresh context");
    assert.deepEqual(result.deliveries, [], "nothing from an unknown-consumer poll counts as delivered");
    assert.deepEqual(subscribes, [{ workspace: "singularity-engine", consumer }],
      "the identity must be re-registered at the current head");
    assert.deepEqual(acks, [], "there is nothing to acknowledge for a batch that was never delivered");
    assert.ok(
      result.errors.some((e) => e.operation === "resubscribe"),
      "a reap must leave an operator-visible trace, not pass silently",
    );
    const state = JSON.parse(await readFile(stateFile, "utf8"));
    assert.deepEqual(state.pending, [], "a discarded batch must not be queued for acknowledgement");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("a re-subscribe that itself fails is reported and does not wedge the run", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-reaped-fail-"));
  const payload = { cwd: "/workspace", session_id: "reaped-fail-session" };
  const durable = {
    name: "repo-memory",
    async poll() {
      const messages = [];
      messages.knownConsumer = false;
      return messages;
    },
    async subscribe() { throw new Error("bus unavailable"); },
    async ack() {},
    async post() {},
    async close() {},
  };

  try {
    const result = await runHook({
      client: "codex", eventName: "UserPromptSubmit", payload, workspace: "singularity-engine",
      stateDir, buses: [durable],
    });
    assert.ok(
      result.errors.some((e) => e.operation === "subscribe" && /bus unavailable/.test(e.error)),
      "a failed re-subscribe must surface, so a permanently broken consumer is noticeable",
    );
    assert.deepEqual(result.deliveries, [], "a failed re-subscribe delivers nothing");
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});
