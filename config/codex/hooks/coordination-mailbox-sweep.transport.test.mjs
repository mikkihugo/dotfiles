import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { CoordinationBus, McpGatewayClient } from "./coordination-mailbox-sweep.mjs";

function execFileWithClosedInput(file, args, options) {
  return new Promise((resolveExec, rejectExec) => {
    const child = execFileCallback(file, args, options, (error, stdout, stderr) => {
      if (error) rejectExec(Object.assign(error, { stdout, stderr }));
      else resolveExec({ stdout, stderr, code: 0 });
    });
    child.stdin.end();
  });
}

// execFile rejects on non-zero exit; every path this hook takes must exit 0,
// so tests call this instead of asserting on rejection.
async function runHookProcess(file, args, options) {
  try {
    return await execFileWithClosedInput(file, args, options);
  } catch (error) {
    return { stdout: error.stdout ?? "", stderr: error.stderr ?? "", code: error.code ?? 1 };
  }
}

async function materializeExecutable(base, name) {
  const target = join(base, name);
  const source = await readFile(new URL("./coordination-mailbox-sweep.mjs", import.meta.url), "utf8");
  await writeFile(target, source.replace("#!@node@", `#!${process.execPath}`));
  await chmod(target, 0o555);
  return target;
}

test("2026-07-28 transport shape: headers and per-call _meta via CoordinationBus.subscribe (stateless, no handshake)", async (t) => {
  const seen = [];
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    seen.push({
      method: rpc.method,
      headers: {
        protocolVersion: request.headers["mcp-protocol-version"],
        method: request.headers["mcp-method"],
        name: request.headers["mcp-name"],
      },
      tool: rpc.params?.arguments?.tool,
      args: rpc.params?.arguments?.arguments,
      meta: rpc.params?._meta,
    });
    // The real gateway has no "initialize" method at all (-32601, HTTP 503)
    // and never returns Mcp-Session-Id; this mock only ever answers
    // tools/call, matching that verified reality.
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({
      jsonrpc: "2.0",
      id: rpc.id,
      result: { content: [{ type: "text", text: JSON.stringify({ ack_watermark: 0, channels: ["engine", "global"] }) }] },
    }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000, globalThis.fetch, "codex");
  const bus = new CoordinationBus(client, {
    identity: "codex-abcd1234",
    clientLabel: "codex",
    channels: ["engine", "global"],
    env: { XDG_STATE_HOME: "/nonexistent" },
  });
  await bus.subscribe("engine", "codex-abcd1234");
  await client.close();

  // Exactly one request was made: no separate initialize/notifications
  // round trip precedes it.
  assert.equal(seen.length, 1);
  const toolCall = seen[0];
  assert.equal(toolCall.method, "tools/call");
  assert.equal(toolCall.headers.protocolVersion, "2026-07-28");
  assert.equal(toolCall.headers.method, "tools/call");
  assert.equal(toolCall.headers.name, "mcp_tool_call");
  assert.equal(toolCall.tool, "coordination_subscribe");
  assert.equal(toolCall.args.principal, "codex-abcd1234");
  assert.equal(toolCall.args.session, "codex-abcd1234-root");
  assert.deepEqual(toolCall.args.channels, ["engine", "global"]);
  assert.equal(toolCall.meta["io.modelcontextprotocol/protocolVersion"], "2026-07-28");
  assert.deepEqual(toolCall.meta["io.modelcontextprotocol/clientCapabilities"], {});
  assert.equal(toolCall.meta["io.modelcontextprotocol/clientInfo"].name, "codex-hook");
});

test("a _meta missing clientCapabilities is rejected by the gateway with -32602 (regression: this exact shape 400'd in live use)", async (t) => {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    const meta = rpc.params?._meta ?? {};
    response.setHeader("Content-Type", "application/json");
    if (!("io.modelcontextprotocol/clientCapabilities" in meta)) {
      response.statusCode = 400;
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        error: { code: -32602, message: 'missing or invalid _meta field "io.modelcontextprotocol/clientCapabilities"' },
      }));
      return;
    }
    response.end(JSON.stringify({
      jsonrpc: "2.0",
      id: rpc.id,
      result: { content: [{ type: "text", text: JSON.stringify({ ack_watermark: 0, channels: ["engine", "global"] }) }] },
    }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000, globalThis.fetch, "codex");
  const bus = new CoordinationBus(client, {
    identity: "codex-abcd1234",
    clientLabel: "codex",
    channels: ["engine", "global"],
    env: { XDG_STATE_HOME: "/nonexistent" },
  });
  // The shipped client always includes clientCapabilities, so this must succeed.
  await assert.doesNotReject(() => bus.subscribe("engine", "codex-abcd1234"));
});

test("SSE responses beginning with an empty prime frame are parsed past it", async (t) => {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    const tool = rpc.params?.arguments?.tool;
    response.setHeader("Content-Type", "application/json");
    if (tool === "coordination_subscribe") {
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        result: { content: [{ type: "text", text: JSON.stringify({ ack_watermark: 0, channels: ["engine", "global"] }) }] },
      }));
      return;
    }
    if (tool === "coordination_poll") {
      response.setHeader("Content-Type", "text/event-stream");
      // A real gateway prime frame carries no data at all -- just the event
      // name -- before the frame that actually answers the request.
      response.end(
        `event: prime\ndata:\n\nevent: message\ndata: ${JSON.stringify({
          jsonrpc: "2.0",
          id: rpc.id,
          result: { content: [{ type: "text", text: JSON.stringify({ messages: [], known_session: true }) }] },
        })}\n\n`,
      );
      return;
    }
    response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result: { content: [{ type: "text", text: "{}" }] } }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000);
  const bus = new CoordinationBus(client, {
    identity: "codex-abcd1234",
    clientLabel: "codex",
    channels: ["engine", "global"],
    env: { XDG_STATE_HOME: "/nonexistent" },
  });
  // Would throw ("MCP gateway returned no text result" / JSON parse error on
  // an empty string) if the empty prime frame were mistaken for the answer.
  const polled = await bus.poll("engine", "codex-abcd1234", {});
  assert.deepEqual([...polled], []);
  await client.close();
});

test("gateway unreachable yields exactly one notice line and exit 0", async () => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-unreachable-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const options = {
      cwd: base,
      env: {
        ...process.env,
        // Nothing listens here -- ECONNREFUSED is the point.
        MCP_GATEWAY_URL: "http://127.0.0.1:1/mcp",
        REPO_MEMORY_MCP_TIMEOUT_MS: "500",
        REPO_MEMORY_SWARM_WORKSPACE: "unreachable-test",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: join(base, "state"),
      },
      timeout: 5_000,
    };
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    assert.match(result.stdout.trim(), /^coordination mailbox: unreachable \(.+\)$/);
    assert.equal(result.stdout.trim().split("\n").length, 1);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("abort at the internal deadline yields exit 0 without blocking the turn", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-deadline-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    let hangingTimer;
    const server = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      // The single atomic sweep call never answers inside the test's deadline.
      // Clear the timer if the client aborts so nothing keeps the process alive.
      request.on("close", () => clearTimeout(hangingTimer));
      hangingTimer = setTimeout(() => {
        try {
          response.end(JSON.stringify({ jsonrpc: "2.0", id: JSON.parse(body).id, result: { content: [{ type: "text", text: "{}" }] } }));
        } catch {
          // Response may already be gone if the client aborted.
        }
      }, 3_000);
    });
    await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
    t.after(() => server.close());
    t.after(() => clearTimeout(hangingTimer));
    const address = server.address();

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
        REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
        REPO_MEMORY_SWARM_WORKSPACE: "deadline-test",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: join(base, "state"),
        // Fires well before the 3s hanging response -- proving the turn is not blocked.
        COORDINATION_MAILBOX_DEADLINE_MS: "800",
      },
      timeout: 5_000,
    };
    const start = Date.now();
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    const elapsed = Date.now() - start;
    assert.equal(result.code, 0);
    assert.ok(elapsed < 2_500, `hook must return before the 3s hanging response; took ${elapsed}ms`);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("a successful sweep writes the cursor file (regression: it was never reached before the transport fix)", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-cursor-write-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const server = await mockGateway(t, [], (tool, args) => {
      if (tool === "coordination_sweep" && args.channels.includes("cursor-write-test")) {
        return {
          messages: [{
            message_id: "cursor-write-1",
            inbox_sequence: 5,
            sender_session: "codex-11112222",
            mailbox: "cursor-write-test",
            type: "status",
            body: "hello",
          }],
          known_session: true,
          ack_watermark: 5,
        };
      }
      return { messages: [], known_session: true, ack_watermark: 0 };
    });
    const port = server.address().port;
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${port}/mcp`,
        REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
        REPO_MEMORY_SWARM_WORKSPACE: "cursor-write-test",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: stateHome,
      },
      timeout: 5_000,
    };
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    assert.match(result.stdout, /hello/);

    const cursorPath = join(stateHome, "coordination-mailbox", "codex-abcd1234.cursor.json");
    const cursor = JSON.parse(await readFile(cursorPath, "utf8"));
    assert.equal(cursor.schema, "coordination-mailbox-cursor/v1");
    assert.equal(cursor.sequences["cursor-write-test"], 5);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("COORDINATION_MAILBOX_DEBUG=1 prints identity, request URL, HTTP status, and cursor path to stderr", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-debug-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const server = await mockGateway(t, [], () => ({ messages: [], known_session: true, ack_watermark: 0 }));
    const port = server.address().port;
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${port}/mcp`,
        REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
        REPO_MEMORY_SWARM_WORKSPACE: "debug-test",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: stateHome,
        COORDINATION_MAILBOX_DEBUG: "1",
      },
      timeout: 5_000,
    };
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    assert.match(result.stderr, /coordination-mailbox debug: identity=codex-abcd1234/);
    assert.match(result.stderr, new RegExp(`cursor=${join(stateHome, "coordination-mailbox", "codex-abcd1234.cursor.json").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    assert.match(result.stderr, new RegExp(`POST http://127\\.0\\.0\\.1:${port}/mcp -> HTTP 200`));
    assert.match(result.stderr, /wrote cursor/);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("a cwd outside any .git/.jj checkout falls back to the global mailbox instead of silently doing nothing (regression: $HOME cwd never wrote a cursor)", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-global-fallback-"));
  // Deliberately no .git/.jj under `base` and no REPO_MEMORY_SWARM_WORKSPACE
  // override -- this is exactly the reported repro shape (cwd=$HOME).
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const seen = [];
    const server = await mockGateway(t, seen, () => ({ messages: [], known_session: true, ack_watermark: 0 }));
    const port = server.address().port;
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${port}/mcp`,
        REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: stateHome,
      },
      timeout: 5_000,
    };
    delete options.env.REPO_MEMORY_SWARM_WORKSPACE;
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    const sweepCalls = seen.filter((call) => call.tool === "coordination_sweep");
    assert.equal(sweepCalls.length, 1, "exactly one atomic sweep per turn");
    assert.deepEqual(sweepCalls[0].args.channels, ["global"], "the only channel polled is global");

    const cursorPath = join(stateHome, "coordination-mailbox", "codex-abcd1234.cursor.json");
    await readFile(cursorPath, "utf8"); // throws if the cursor file was never written
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

// --- subscribe-at-head guard (2026-09-05 from-zero replay incident) ---------
//
// Regression contract for bus seq 25864: the atomic sweep subscribes a fresh
// consumer at the current head and returns only unread messages. The client
// never polls a watermark-less mailbox, and a known_session=false response
// means the server discarded the batch and re-subscribed at head.

function mockGateway(t, seen, handler) {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    const tool = rpc.params?.arguments?.tool;
    const args = rpc.params?.arguments?.arguments ?? {};
    seen.push({ tool, args });
    const payload = handler(tool, args);
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({
      jsonrpc: "2.0",
      id: rpc.id,
      result: { content: [{ type: "text", text: JSON.stringify(payload ?? {}) }] },
    }));
  });
  return new Promise((resolveListen) => {
    server.listen(0, "127.0.0.1", () => {
      t.after(() => server.close());
      resolveListen(server);
    });
  });
}

function hookOptions(base, port, workspace, extra = {}) {
  return {
    cwd: base,
    env: {
      ...process.env,
      MCP_GATEWAY_URL: `http://127.0.0.1:${port}/mcp`,
      REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
      REPO_MEMORY_SWARM_WORKSPACE: workspace,
      REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
      XDG_STATE_HOME: join(base, "state"),
      ...extra,
    },
    timeout: 5_000,
  };
}

test("a fresh identity subscribes at head and never renders the backlog", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-fresh-head-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const seen = [];
    const server = await mockGateway(t, seen, (tool, args) => {
      if (tool === "coordination_sweep" && args.channels.includes("fresh-head-test")) {
        return {
          messages: [{
            message_id: "fresh-1",
            inbox_sequence: 901,
            sender_session: "codex-11112222",
            mailbox: "fresh-head-test",
            type: "status",
            body: "fresh news",
          }],
          known_session: true,
          ack_watermark: 901,
        };
      }
      return { messages: [], known_session: true, ack_watermark: 901 };
    });
    const port = server.address().port;

    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "fresh-head-test"));
    assert.equal(result.code, 0);
    assert.match(result.stdout, /fresh news/);
    assert.doesNotMatch(result.stdout, /ancient backlog/);

    // The turn makes exactly one atomic sweep call; the server-side subscribe
    // and filtering are not visible as separate requests.
    const sweepCalls = seen.filter((call) => call.tool === "coordination_sweep");
    assert.equal(sweepCalls.length, 1, "exactly one atomic sweep per turn");
    assert.ok(sweepCalls[0].args.channels.includes("fresh-head-test"));
    assert.ok(sweepCalls[0].args.channels.includes("global"));

    const cursor = JSON.parse(await readFile(join(base, "state", "coordination-mailbox", "codex-abcd1234.cursor.json"), "utf8"));
    assert.equal(cursor.sequences["fresh-head-test"], 901, "message advanced the cursor past the subscribed head");
    assert.equal(cursor.sequences["global"], 901, "all channels share the inbox watermark returned by the sweep");
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("known_session=false discards the replayed batch and resubscribes at head", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-reaped-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    // A low existing local cursor -- the server then reports our consumer as
    // gone (reaped) and answers from zero server-side.
    const stateDir = join(base, "state", "coordination-mailbox");
    await (await import("node:fs/promises")).mkdir(stateDir, { recursive: true });
    await writeFile(
      join(stateDir, "codex-abcd1234.cursor.json"),
      JSON.stringify({ schema: "coordination-mailbox-cursor/v1", sequences: { "reaped-test": 50, global: 895 } }),
    );
    const seen = [];
    const server = await mockGateway(t, seen, (tool, args) => {
      if (tool === "coordination_sweep" && args.channels.includes("reaped-test")) {
        return {
          messages: [],
          known_session: false,
          ack_watermark: 900,
        };
      }
      return { messages: [], known_session: true, ack_watermark: 900 };
    });
    const port = server.address().port;

    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "reaped-test"));
    assert.equal(result.code, 0);
    assert.doesNotMatch(result.stdout, /from-zero replay/);

    const sweepCalls = seen.filter((call) => call.tool === "coordination_sweep");
    assert.equal(sweepCalls.length, 1);

    const cursor = JSON.parse(await readFile(join(stateDir, "codex-abcd1234.cursor.json"), "utf8"));
    assert.equal(cursor.sequences["reaped-test"], 900, "cursor moved to the resubscribed head");
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("an existing local cursor does not block a sweep; the server watermark is authoritative", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-held-cursor-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const stateDir = join(base, "state", "coordination-mailbox");
    await (await import("node:fs/promises")).mkdir(stateDir, { recursive: true });
    await writeFile(
      join(stateDir, "codex-abcd1234.cursor.json"),
      JSON.stringify({ schema: "coordination-mailbox-cursor/v1", sequences: { "held-test": 800, global: 800 } }),
    );
    const seen = [];
    const server = await mockGateway(t, seen, (tool, args) => {
      if (tool === "coordination_sweep" && args.channels.includes("held-test")) {
        return {
          messages: [{
            message_id: "held-1",
            inbox_sequence: 801,
            sender_session: "codex-11112222",
            mailbox: "held-test",
            type: "status",
            body: "live update",
          }],
          known_session: true,
          ack_watermark: 801,
        };
      }
      return { messages: [], known_session: true, ack_watermark: 801 };
    });
    const port = server.address().port;

    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "held-test"));
    assert.equal(result.code, 0);
    assert.match(result.stdout, /live update/);

    const sweepCalls = seen.filter((call) => call.tool === "coordination_sweep");
    assert.equal(sweepCalls.length, 1, "exactly one atomic sweep per turn");

    const cursor = JSON.parse(await readFile(join(stateDir, "codex-abcd1234.cursor.json"), "utf8"));
    assert.equal(cursor.sequences["held-test"], 801, "cursor follows the server watermark, not the local one");
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("sweep without an ack_watermark fails closed -- messages are not rendered", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-no-watermark-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const seen = [];
    const server = await mockGateway(t, seen, () => ({
      messages: [{
        message_id: "zero-1",
        inbox_sequence: 1,
        sender_session: "codex-11112222",
        mailbox: "no-watermark-test",
        type: "status",
        body: "should never render",
      }],
      known_session: true,
      // contract violation: no ack_watermark
    }));
    const port = server.address().port;

    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "no-watermark-test"));
    assert.equal(result.code, 0);
    assert.doesNotMatch(result.stdout, /should never render/);
    assert.match(result.stdout.trim(), /^coordination mailbox: unreachable \(.+\)$/);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

// --- multi-mailbox recipient='all' broadcast: server acks every copy atomically -
//
// Regression for the multi-bucket re-block symptom (RESEARCH-BRIEF: a
// recipient="all" broadcast lands in every mailbox this identity subscribes
// to; acking only the cross-mailbox-deduped "winning" copy left every other
// mailbox's copy unacked forever, so it resurfaced as "new" the next time
// that other mailbox happened to win the dedupe -- observed ~25 consecutive
// Claude Stop-hook blocks on one broadcast id across a 35-mailbox identity).
// With coordination_sweep the server acks every returned message in the same
// transaction, so the client only has to render the body once and keep all
// mailbox cursors in sync with the returned inbox watermark.

test("a recipient='all' broadcast held in two mailboxes is surfaced once and advances both cursors", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-broadcast-multi-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const stateDir = join(base, "state", "coordination-mailbox");
    await (await import("node:fs/promises")).mkdir(stateDir, { recursive: true });
    await writeFile(
      join(stateDir, "codex-abcd1234.cursor.json"),
      JSON.stringify({ schema: "coordination-mailbox-cursor/v1", sequences: { "broadcast-lane": 0, global: 0 } }),
    );
    const seen = [];
    let sweepCount = 0;
    const server = await mockGateway(t, seen, (tool) => {
      if (tool === "coordination_sweep") {
        sweepCount += 1;
        if (sweepCount === 1) {
          return {
            messages: [
              { message_id: "bcast-1", inbox_sequence: 1, sender_session: "codex-11112222", mailbox: "broadcast-lane", type: "status", body: "broadcast body" },
              { message_id: "bcast-1", inbox_sequence: 1, sender_session: "codex-11112222", mailbox: "global", type: "status", body: "broadcast body" },
            ],
            known_session: true,
            ack_watermark: 1,
          };
        }
        return { messages: [], known_session: true, ack_watermark: 1 };
      }
      return {};
    });
    const port = server.address().port;

    const first = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "broadcast-lane"));
    assert.equal(first.code, 0);
    // Shown exactly once in this sweep's output, despite arriving via two
    // mailboxes.
    assert.equal((first.stdout.match(/broadcast body/g) ?? []).length, 1, "the broadcast body must not be rendered twice in one sweep");

    const cursor = JSON.parse(await readFile(join(stateDir, "codex-abcd1234.cursor.json"), "utf8"));
    assert.equal(cursor.sequences["broadcast-lane"], 1, "the lane mailbox's cursor advanced past the broadcast");
    assert.equal(cursor.sequences.global, 1, "the global mailbox's cursor also advanced past the broadcast");

    // Second sweep: because both mailboxes share the advanced inbox watermark,
    // neither mailbox re-offers the same id.
    const second = await runHookProcess(target, ["codex", "UserPromptSubmit"], hookOptions(base, port, "broadcast-lane"));
    assert.equal(second.code, 0);
    assert.doesNotMatch(second.stdout, /broadcast body/, "an already-acked broadcast must not resurface on the next sweep");
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});
