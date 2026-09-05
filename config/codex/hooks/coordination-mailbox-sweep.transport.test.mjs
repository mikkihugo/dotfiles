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

test("2026-07-28 transport shape: headers and initialize _meta", async (t) => {
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
    if (rpc.method === "notifications/initialized") {
      response.writeHead(202).end();
      return;
    }
    response.setHeader("Content-Type", "application/json");
    response.setHeader("Mcp-Session-Id", "transport-test-session");
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2026-07-28", capabilities: {}, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] };
    response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result }));
  });
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  t.after(() => server.close());
  const address = server.address();

  const client = new McpGatewayClient(`http://127.0.0.1:${address.port}/mcp`, 2_000, globalThis.fetch, "codex");
  const bus = new RepoMemoryBus(client);
  await bus.subscribe("engine", "codex-abcd1234");
  await client.close();

  const initialize = seen.find((entry) => entry.method === "initialize");
  assert.equal(initialize.headers.protocolVersion, "2026-07-28");
  assert.equal(initialize.headers.method, "initialize");
  assert.equal(initialize.meta.protocolVersion, "2026-07-28");
  assert.deepEqual(initialize.meta.clientCapabilities, {});
  assert.equal(initialize.meta.clientInfo.name, "codex-hook");

  const toolCall = seen.find((entry) => entry.method === "tools/call");
  assert.equal(toolCall.headers.protocolVersion, "2026-07-28");
  assert.equal(toolCall.headers.method, "tools/call");
  assert.equal(toolCall.headers.name, "mcp_tool_call");
});

test("SSE responses beginning with an empty prime frame are parsed past it", async (t) => {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    const rpc = body ? JSON.parse(body) : {};
    if (rpc.method === "notifications/initialized") {
      response.writeHead(202).end();
      return;
    }
    response.setHeader("Content-Type", "text/event-stream");
    response.setHeader("Mcp-Session-Id", "prime-test-session");
    const result = rpc.method === "initialize"
      ? { protocolVersion: "2026-07-28", capabilities: {}, serverInfo: { name: "test", version: "1" } }
      : { content: [{ type: "text", text: JSON.stringify({ messages: [], next_cursor: 0 }) }] };
    // A real gateway prime frame carries no data at all -- just the event
    // name -- before the frame that actually answers the request.
    response.end(
      `event: prime\ndata:\n\nevent: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result })}\n\n`,
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
      response.setHeader("Mcp-Session-Id", "deadline-test-session");
      if (rpc.method === "initialize") {
        response.end(JSON.stringify({
          jsonrpc: "2.0",
          id: rpc.id,
          result: { protocolVersion: "2026-07-28", capabilities: {}, serverInfo: { name: "test", version: "1" } },
        }));
        return;
      }
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
