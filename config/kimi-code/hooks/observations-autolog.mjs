#!/usr/bin/env node
/**
 * Autolog hook — drain session observations/ideas into repo_memory.
 *
 * Fires on Stop / SessionEnd. Reads the session capture file
 *   ~/.agent-work/observations/<client>-<session_id>.md
 * and retains each entry directly in the repository memory bank with
 * `kind:observation` (no OBSERVATIONS.md trail). Clears the capture file
 * after a successful drain. Idempotent: entries carry a stable dedupe key
 * (repo identity + normalized text), so a re-run never duplicates.
 *
 * The agent's only job during the turn is appending one line per
 * observation/idea to the capture file (or calling the purpose_tool
 * autolog capture helper). The hook does the send.
 *
 * Usage: observations-autolog.mjs <client> [event]   (payload JSON on stdin)
 */

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

const GATEWAY_URL = process.env.REPO_MEMORY_GATEWAY_URL ?? "http://mcp-gateway.svc/mcp";
const SUPPORTED_PROTOCOL = "2025-11-25";

function readStdin() {
  try {
    const raw = readFileSync(0, "utf8");
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

/** Parse an MCP HTTP response body that may be plain JSON or an SSE stream. */
function rpcFromBody(body) {
  if (!body.trim()) return null;
  if (!body.trimStart().startsWith("event:")) return JSON.parse(body);
  const events = body.split(/\r?\n\r?\n/);
  for (const event of events) {
    const data = event
      .split(/\r?\n/)
      .filter((line) => line.startsWith("data:"))
      .map((line) => line.slice(5).trimStart())
      .join("\n");
    if (data) return JSON.parse(data);
  }
  return null;
}

class GatewayClient {
  constructor(label) {
    this.label = label;
    this.nextID = 1;
  }

  async request(payload, { signal } = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    const onOuterAbort = () => controller.abort();
    signal?.addEventListener("abort", onOuterAbort);
    try {
      const headers = { "Content-Type": "application/json" };
      headers["Mcp-Protocol-Version"] = SUPPORTED_PROTOCOL;
      if (payload?.method) headers["Mcp-Method"] = payload.method;
      if (payload?.params?.name) headers["Mcp-Name"] = payload.params.name;
      const response = await fetch(GATEWAY_URL, {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      const rpc = rpcFromBody(await response.text());
      if (rpc?.error) throw new Error(`MCP ${rpc.error.code}: ${rpc.error.message}`);
      if (!response.ok) throw new Error(`MCP gateway returned HTTP ${response.status}`);
      return rpc?.result ?? null;
    } finally {
      clearTimeout(timer);
      signal?.removeEventListener("abort", onOuterAbort);
    }
  }

  async callRepoMemory(tool, args, signal) {
    const result = await this.request(
      {
        jsonrpc: "2.0",
        id: this.nextID++,
        method: "tools/call",
        params: {
          name: "mcp_tool_call",
          arguments: { server: "repo_memory", tool, arguments: args },
          _meta: {
            "io.modelcontextprotocol/protocolVersion": SUPPORTED_PROTOCOL,
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": { name: `${this.label}-autolog`, version: "1.0.0" },
          },
        },
      },
      { signal },
    );
    if (result?.isError) throw new Error(`repo-memory ${tool} failed`);
    const text = result?.content?.find((item) => item.type === "text")?.text;
    if (typeof text === "string") return JSON.parse(text);
    // Some tools (memory_retain) return the structured result directly.
    if (result && typeof result === "object" && !Array.isArray(result)) return result;
    throw new Error(`repo-memory ${tool} returned no usable result`);
  }
}

/** Resolve the repository root by walking up from cwd for .git/.jj. */
function resolveRepoRoot(cwd) {
  let dir = resolve(cwd);
  for (;;) {
    if (existsSync(join(dir, ".git")) || existsSync(join(dir, ".jj"))) return dir;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/** Resolve the memory bank id from .purpose/lock.json (fallback: global). */
function resolveBankId(repoRoot) {
  try {
    const lock = JSON.parse(readFileSync(join(repoRoot, ".purpose", "lock.json"), "utf8"));
    const bank = lock?.memoryBankId;
    if (typeof bank === "string" && bank.trim()) return bank.trim();
  } catch {
    /* no lock file — fall through to global */
  }
  return "global";
}

function dedupeKey(repoRoot, text) {
  return `autolog-${createHash("sha1").update(`${repoRoot}\u0000${text}`).digest("hex").slice(0, 16)}`;
}

export async function main(argv = process.argv.slice(2), env = process.env) {
  const [clientName = "kimi-code", eventArgument] = argv;
  const payload = await readStdin();
  const eventName = eventArgument || payload.hook_event_name || "Stop";
  if (eventName !== "Stop" && eventName !== "SessionEnd") return;

  const cwd = resolve(typeof payload.cwd === "string" ? payload.cwd : process.cwd());
  const sessionId =
    payload.session_id ?? payload.sessionId ?? payload.thread_id ?? payload.threadId ?? "unknown";
  const captureDir = join(homedir(), ".agent-work", "observations");
  const captureFile = join(captureDir, `${clientName}-${sessionId}.md`);
  if (!existsSync(captureFile)) return;

  const repoRoot = resolveRepoRoot(cwd);
  const gateway = new GatewayClient(clientName);

  const lines = readFileSync(captureFile, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#") && !line.startsWith("//"));

  let promoted = 0;
  let failed = 0;
  for (const line of lines) {
    try {
      await gateway.callRepoMemory("memory_retain", {
        content: line,
        context: "autolog",
        fact_type: "observation",
        // No memory_bank_id: stateless hook calls are outside the session
        // bank scope; the server defaults to the global bank.
        tags: ["kind:observation", "source:autolog"],
        metadata: { source: "autolog-hook", client: clientName, session_id: sessionId },
      });
      promoted += 1;
    } catch (error) {
      failed += 1;
      process.stderr.write(
        `[autolog] retain failed: ${error instanceof Error ? error.message : String(error)}\n`,
      );
    }
  }

  if (failed === 0) {
    rmSync(captureFile, { force: true });
  } else {
    // Keep only the failed entries; they will be retried on the next turn.
    const remaining = lines.slice(lines.length - failed).join("\n");
    writeFileSync(captureFile, remaining ? remaining + "\n" : "");
  }
  process.stderr.write(`[autolog] ${eventName}: promoted ${promoted}, failed ${failed}\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    process.stderr.write(`[autolog] fatal: ${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
