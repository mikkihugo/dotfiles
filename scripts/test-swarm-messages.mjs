import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  McpGatewayClient,
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
      payload: { cwd: "/workspace" },
      workspace: "engine",
      stateDir,
      buses: [durable],
    });
    assert.match(JSON.stringify(first.output), /Review revision abc123/);
    assert.deepEqual(calls, ["poll"]);

    durable.poll = async () => [];
    const second = await runHook({
      client: "codex",
      eventName: "UserPromptSubmit",
      payload: { cwd: "/workspace" },
      workspace: "engine",
      stateDir,
      buses: [durable],
    });
    assert.equal(second.output, null);
    assert.deepEqual(calls, ["poll", `ack:${message.id}`]);
    assert.equal(JSON.parse(await readFile(join(stateDir, "codex--engine.json"), "utf8")).pending.length, 0);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});

test("MCP failure preserves filesystem fallback delivery", async () => {
  const stateDir = await mkdtemp(join(tmpdir(), "repo-memory-hook-fallback-"));
  const durable = {
    name: "repo-memory",
    async poll() { throw new Error("gateway unavailable"); },
    async ack() {},
    async post() {},
    async close() {},
  };
  const local = {
    name: "filesystem",
    async poll() { return [{ ...message, id: "local-1", origin: "filesystem" }]; },
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
      buses: [durable, local],
    });
    assert.match(result.output, /filesystem/);
  } finally {
    await rm(stateDir, { recursive: true, force: true });
  }
});
