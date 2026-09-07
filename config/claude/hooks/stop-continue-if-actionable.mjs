#!/usr/bin/env node
// Stop hook: keep the session from going idle while a genuinely actionable
// bus message (type "question" or "blocker") is sitting unacked, instead of
// only re-checking the bus on the next human UserPromptSubmit.
//
// Deliberately narrow and fail-open, per the reviewed design:
//   - Reuses the already-debugged coordination-mailbox-sweep transport,
//     identity derivation, and acked-prefix cursor logic verbatim (imported
//     from the canonical rendered path) instead of a second implementation.
//   - Only "question"/"blocker" count as actionable; everything the sweep
//     already treats as noise (available pings, heartbeats, status/findings
//     chatter) is not enough to block a stop on its own.
//   - A consecutive-block counter (state file) caps how many times in a row
//     this can block before it gives up and allows the stop anyway - an
//     unconditional Stop hook that always blocks is a livelock, not a fix.
//   - Every failure path (disabled env var, transport error, bad JSON,
//     counter-file write failure) allows the stop. A malformed hook must
//     never be silently a permanent block; it must be silently a no-op.
import { basename, dirname, join, resolve } from "node:path";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { pathToFileURL } from "node:url";
import {
  McpGatewayClient,
  RepoMemoryBus,
  runSweep,
  selectWorkspace,
} from "/home/mhugo/.codex/hooks/coordination-mailbox-sweep.mjs";

export const MAX_CONSECUTIVE_BLOCKS = 3;
export const ACTIONABLE_TYPES = new Set(["question", "blocker"]);

/**
 * Pure decision: given already-filtered actionable messages and the
 * consecutive-block count so far, decide whether to block the stop.
 * No I/O - the state-file read/write and process.exit stay in main() so this
 * is directly unit-testable.
 */
export function decide(actionable, previousCount, maxBlocks = MAX_CONSECUTIVE_BLOCKS) {
  if (actionable.length === 0) return { block: false };
  if (previousCount >= maxBlocks) return { block: false, capHit: true };
  const summary = actionable
    .slice(0, 5)
    .map((m) => `- ${m.sender} [${m.type}]: ${String(m.body ?? "").slice(0, 200)}`)
    .join("\n");
  return {
    block: true,
    reason: `${actionable.length} unacked actionable bus message(s) before stopping:\n${summary}\n\nAddress or explicitly acknowledge these, then stop again.`,
  };
}

export function statePath(env) {
  const stateHome = env.XDG_STATE_HOME?.trim() || join(env.HOME || homedir(), ".local", "state");
  return join(stateHome, "claude-stop-continue", "counter.json");
}

export async function readCounter(path) {
  try {
    const raw = await readFile(path, "utf8");
    const n = JSON.parse(raw)?.count;
    return Number.isInteger(n) && n >= 0 ? n : 0;
  } catch {
    return 0;
  }
}

export async function writeCounter(path, n) {
  try {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, JSON.stringify({ count: n }), "utf8");
  } catch {
    // Best-effort only. A failed write must never turn into a block.
  }
}

async function readStdin() {
  let raw = "";
  for await (const chunk of process.stdin) raw += chunk;
  try {
    return raw.trim() ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

async function allowStop(path) {
  await writeCounter(path, 0);
  // No stdout at all = allow the stop, per the documented Stop-hook contract.
  process.exit(0);
}

async function main() {
  const env = process.env;
  const path = statePath(env);

  if (env.REPO_MEMORY_SWARM_DISABLE_MCP === "1") return allowStop(path);

  const payload = await readStdin();
  const cwd = resolve(typeof payload.cwd === "string" ? payload.cwd : process.cwd());
  const selected = selectWorkspace(cwd, env) ?? { identity: "global", worktree: null };
  const timeout = Number.parseInt(env.REPO_MEMORY_MCP_TIMEOUT_MS || "4000", 10);
  const debug = env.COORDINATION_MAILBOX_DEBUG === "1";
  const bus = new RepoMemoryBus(new McpGatewayClient(env.MCP_GATEWAY_URL, timeout, globalThis.fetch, "claude", debug));

  let outcome;
  try {
    const lane = selected.worktree ? basename(selected.worktree) : null;
    outcome = await runSweep({
      client: "claude",
      eventName: "Stop",
      payload,
      workspace: selected.identity,
      additionalWorkspaces: lane && lane !== selected.identity ? [lane] : [],
      worktree: selected.worktree,
      env,
      bus,
      // We build our own Stop-hook JSON from outcome.kept below; the sweep's
      // own renderClientOutput() shape (hookSpecificOutput.additionalContext)
      // is for UserPromptSubmit/SessionStart, not Stop, so discard it here.
      emitOutput: async () => {},
      deadlineMs: Number.parseInt(env.COORDINATION_MAILBOX_DEADLINE_MS || "8000", 10),
      debug,
    });
  } catch {
    await bus.close().catch(() => {});
    return allowStop(path); // transport failure: fail open, never block on a broken bus
  }
  await bus.close().catch(() => {});

  const actionable = (outcome?.kept ?? []).filter((m) => ACTIONABLE_TYPES.has(m?.type));
  const count = await readCounter(path);
  const verdict = decide(actionable, count);

  if (!verdict.block) return allowStop(path); // covers: none actionable, and cap hit (fail open either way)

  await writeCounter(path, count + 1);
  process.stdout.write(JSON.stringify({ decision: "block", reason: verdict.reason }));
}

// Guard against running main() when this module is merely *imported* (e.g.
// by its own test file) rather than executed as the hook entrypoint - main()
// reads stdin to EOF, which never comes under `node --test` and hung the
// test run for a full 120s before this guard was added.
let invokedAsMain = false;
try {
  invokedAsMain = Boolean(
    process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href,
  );
} catch {
  // An unresolved argv path is not an executable main-module identity.
}

if (invokedAsMain) {
  main().catch(() => allowStop(statePath(process.env)));
}
