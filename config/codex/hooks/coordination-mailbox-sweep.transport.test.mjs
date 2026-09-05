import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { McpGatewayClient, RepoMemoryBus } from "./coordination-mailbox-sweep.mjs";

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

test("2026-07-28 transport shape: headers and per-call _meta (stateless, no handshake)", async (t) => {
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
      meta: rpc.params?._meta,
    });
    // The real gateway has no "initialize" method at all (-32601, HTTP 503)
    // and never returns Mcp-Session-Id; this mock only ever answers
    // tools/call, matching that verified reality.
    response.setHeader("Content-Type", "application/json");
    response.end(JSON.stringify({
      jsonrpc: "2.0",
      id: rpc.id,
      result: { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] },
    }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000, globalThis.fetch, "codex");
  const bus = new RepoMemoryBus(client);
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
      result: { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] },
    }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000, globalThis.fetch, "codex");
  const bus = new RepoMemoryBus(client);
  // The shipped client always includes clientCapabilities, so this must succeed.
  await assert.doesNotReject(() => bus.subscribe("engine", "codex-abcd1234"));
});

test("SSE responses beginning with an empty prime frame are parsed past it", async (t) => {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    response.setHeader("Content-Type", "text/event-stream");
    // A real gateway prime frame carries no data at all -- just the event
    // name -- before the frame that actually answers the request.
    response.end(
      `event: prime\ndata:\n\nevent: message\ndata: ${JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        result: { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] },
      })}\n\n`,
    );
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000);
  const bus = new RepoMemoryBus(client);
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

test("abort at the internal deadline yields partial output and exit 0", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-deadline-"));
  const laneDir = join(base, "engine-lane");
  await (await import("node:fs/promises")).mkdir(laneDir, { recursive: true });
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    let hangingTimer;
    const server = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      const rpc = body ? JSON.parse(body) : {};
      response.setHeader("Content-Type", "application/json");
      const args = rpc.params?.arguments?.arguments ?? {};
      const tool = rpc.params?.arguments?.tool;
      if (tool === "swarm_bus_poll" && args.workspace === "engine-primary") {
        response.end(JSON.stringify({
          jsonrpc: "2.0",
          id: rpc.id,
          result: {
            content: [{
              type: "text",
              text: JSON.stringify({
                messages: [{
                  id: "partial-1",
                  sequence: 1,
                  sender: "codex-11112222",
                  recipient: "all",
                  type: "status",
                  body: "delivered before the deadline",
                }],
                next_cursor: 1,
              }),
            }],
          },
        }));
        return;
      }
      // The second mailbox never answers inside the test's deadline. Clear
      // the timer if the client aborts so nothing keeps the process alive.
      request.on("close", () => clearTimeout(hangingTimer));
      hangingTimer = setTimeout(() => {
        try {
          response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result: { content: [{ type: "text", text: "{}" }] } }));
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
        REPO_MEMORY_SWARM_WORKSPACE: "engine-primary",
        SWARM_WORKTREE: laneDir,
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: join(base, "state"),
        // Fires well before the second mailbox's 3s hang, but after the
        // first mailbox's immediate response -- proving partial output.
        COORDINATION_MAILBOX_DEADLINE_MS: "800",
      },
      timeout: 5_000,
    };
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    assert.match(result.stdout, /delivered before the deadline/);
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});

test("a successful sweep writes the cursor file (regression: it was never reached before the transport fix)", async (t) => {
  const base = await mkdtemp(join(tmpdir(), "coordination-mailbox-cursor-write-"));
  try {
    const target = await materializeExecutable(base, "coordination-mailbox-sweep.mjs");
    const server = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      const rpc = body ? JSON.parse(body) : {};
      const args = rpc.params?.arguments?.arguments ?? {};
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        result: {
          content: [{
            type: "text",
            text: JSON.stringify({
              messages: args.workspace === "cursor-write-test" ? [{
                id: "cursor-write-1",
                sequence: 5,
                sender: "codex-11112222",
                recipient: "all",
                type: "status",
                body: "hello",
              }] : [],
              next_cursor: 5,
            }),
          }],
        },
      }));
    });
    await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
    t.after(() => server.close());
    const address = server.address();
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
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
    const server = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      const rpc = body ? JSON.parse(body) : {};
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        result: { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] },
      }));
    });
    await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
    t.after(() => server.close());
    const address = server.address();
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
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
    assert.match(result.stderr, new RegExp(`POST http://127\\.0\\.0\\.1:${address.port}/mcp -> HTTP 200`));
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
    const seenWorkspaces = [];
    const server = createServer(async (request, response) => {
      let body = "";
      for await (const chunk of request) body += chunk;
      const rpc = body ? JSON.parse(body) : {};
      const args = rpc.params?.arguments?.arguments ?? {};
      if (args.workspace) seenWorkspaces.push(args.workspace);
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({
        jsonrpc: "2.0",
        id: rpc.id,
        result: { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] },
      }));
    });
    await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
    t.after(() => server.close());
    const address = server.address();
    const stateHome = join(base, "state");

    const options = {
      cwd: base,
      env: {
        ...process.env,
        MCP_GATEWAY_URL: `http://127.0.0.1:${address.port}/mcp`,
        REPO_MEMORY_MCP_TIMEOUT_MS: "4000",
        REPO_MEMORY_SWARM_CONSUMER: "codex-abcd1234",
        XDG_STATE_HOME: stateHome,
      },
      timeout: 5_000,
    };
    delete options.env.REPO_MEMORY_SWARM_WORKSPACE;
    const result = await runHookProcess(target, ["codex", "UserPromptSubmit"], options);
    assert.equal(result.code, 0);
    assert.ok(seenWorkspaces.includes("global"), `expected a poll of the global mailbox; saw ${JSON.stringify(seenWorkspaces)}`);

    const cursorPath = join(stateHome, "coordination-mailbox", "codex-abcd1234.cursor.json");
    await readFile(cursorPath, "utf8"); // throws if the cursor file was never written
  } finally {
    await rm(base, { recursive: true, force: true });
  }
});
