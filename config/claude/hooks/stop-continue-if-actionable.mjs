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
//   - A recipient="all" broadcast lands in every coordination-mailbox bucket
//     this identity subscribes to (see coordination-mailbox-sweep.mjs's
//     dedupeByMessageId and the unreadAllCopies fix next to it). runSweep
//     now acks every bucket copy it polls in one call, but a long session
//     accumulates many buckets over time (one per lane/workspace visited)
//     and any single call only polls the 2-3 buckets for the CURRENT cwd -
//     so a bucket not polled together with the "winning" one can still hold
//     an unacked copy and re-surface it later as if new (observed: ~25
//     consecutive Stop blocks on one broadcast id across a 35-bucket
//     identity). This hook additionally remembers, per session, every
//     actionable message id it has already surfaced once and does not
//     block again for that same id - see blockedIds below.
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

/**
 * `sessionId`, when given, keys the state file so the consecutive-block cap
 * (and the blocked-id memory below) is scoped to one Claude session instead
 * of shared by every concurrent session on the host. Omitted (or blank),
 * this returns exactly the pre-existing single shared path - callers and
 * tests that never had a session id keep today's behavior byte-for-byte.
 */
export function statePath(env, sessionId) {
  const stateHome = env.XDG_STATE_HOME?.trim() || join(env.HOME || homedir(), ".local", "state");
  const dir = join(stateHome, "claude-stop-continue");
  const safeSession = typeof sessionId === "string" ? sessionId.trim().replace(/[^A-Za-z0-9._-]/g, "_").slice(0, 128) : "";
  return safeSession ? join(dir, `counter.${safeSession}.json`) : join(dir, "counter.json");
}

// A pruned id can never legitimately return from the bus and look "new":
// swarm-messaging's SKILL.md documents delivered messages purged after ~1
// day and everything after ~1 week, so 24h of local memory is comfortably
// inside that window without growing forever.
export const BLOCKED_ID_TTL_MS = 24 * 60 * 60 * 1000;
export const BLOCKED_ID_CAP = 200;

/** Drop stale entries and cap the map to the most recent BLOCKED_ID_CAP ids. */
export function pruneBlockedIds(blockedIds, now = Date.now()) {
  const entries = Object.entries(blockedIds ?? {}).filter(
    ([, ts]) => Number.isFinite(ts) && now - ts < BLOCKED_ID_TTL_MS,
  );
  entries.sort((a, b) => a[1] - b[1]); // oldest first
  const bounded = entries.length > BLOCKED_ID_CAP ? entries.slice(entries.length - BLOCKED_ID_CAP) : entries;
  return Object.fromEntries(bounded);
}

/**
 * Drop messages whose id we have already surfaced (and let the sweep ack)
 * before. Messages without a string id are never filtered here - a missing
 * id cannot be safely deduped without risking a genuinely new message being
 * silently swallowed, so those always reach decide() unfiltered.
 */
export function filterUnblocked(actionable, blockedIds) {
  return actionable.filter((m) => typeof m?.id !== "string" || m.id.length === 0 || !(m.id in (blockedIds ?? {})));
}

/** Record every id-bearing message as blocked-as-of `now`, then re-bound. */
export function recordBlockedIds(blockedIds, messages, now = Date.now()) {
  const next = { ...(blockedIds ?? {}) };
  for (const m of messages) {
    if (typeof m?.id === "string" && m.id.length > 0) next[m.id] = now;
  }
  return pruneBlockedIds(next, now);
}

export async function readState(path) {
  try {
    const raw = await readFile(path, "utf8");
    const parsed = JSON.parse(raw);
    const count = Number.isInteger(parsed?.count) && parsed.count >= 0 ? parsed.count : 0;
    const blockedIdsRaw = parsed?.blockedIds;
    const blockedIds = blockedIdsRaw && typeof blockedIdsRaw === "object" && !Array.isArray(blockedIdsRaw) ? blockedIdsRaw : {};
    return { count, blockedIds };
  } catch {
    return { count: 0, blockedIds: {} };
  }
}

export async function writeState(path, state) {
  try {
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, JSON.stringify(state), "utf8");
  } catch {
    // Best-effort only. A failed write must never turn into a block.
  }
}

export async function readCounter(path) {
  return (await readState(path)).count;
}

export async function writeCounter(path, n) {
  // Read-merge-write so resetting the counter (e.g. on every allowed stop)
  // never wipes the blocked-id memory living in the same file.
  const state = await readState(path);
  await writeState(path, { ...state, count: n });
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

/**
 * `blockedIds`, when given, is written alongside the reset counter (e.g.
 * after a non-blocking decision that still saw - and should remember - some
 * actionable ids). Omitted, this preserves whatever blockedIds the state
 * file already had, matching the pre-existing reset-to-0 behavior exactly.
 */
async function allowStop(path, blockedIds) {
  if (blockedIds === undefined) {
    await writeCounter(path, 0);
  } else {
    await writeState(path, { count: 0, blockedIds });
  }
  // No stdout at all = allow the stop, per the documented Stop-hook contract.
  process.exit(0);
}

// Set as soon as main() resolves the (possibly session-keyed) state path, so
// the top-level catch-all below can reuse the SAME file a mid-run exception
// interrupted, instead of falling back to the pre-session-keying shared
// path and resetting a counter main() no longer touches.
let lastResolvedPath = null;

async function main() {
  const env = process.env;
  const payload = await readStdin();
  const sessionId = typeof payload.session_id === "string" && payload.session_id.trim() ? payload.session_id.trim() : undefined;
  const path = statePath(env, sessionId);
  lastResolvedPath = path;

  if (env.REPO_MEMORY_SWARM_DISABLE_MCP === "1") return allowStop(path);

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
  const state = await readState(path);
  const prunedBlockedIds = pruneBlockedIds(state.blockedIds);
  // Drop ids this hook has already surfaced once - a broadcast still unacked
  // in some other, not-yet-polled bucket must not re-block on the same id.
  // See the file header and coordination-mailbox-sweep.mjs's unreadAllCopies
  // fix for why a bucket can still hold a stale unacked copy.
  const newActionable = filterUnblocked(actionable, prunedBlockedIds);
  const verdict = decide(newActionable, state.count);

  if (!verdict.block) {
    // covers: nothing actionable, everything actionable was already-blocked
    // ids, and cap hit (fail open in all three cases). Still remember any
    // newly-seen ids so they don't cost a future block either.
    return allowStop(path, recordBlockedIds(prunedBlockedIds, newActionable));
  }

  await writeState(path, { count: state.count + 1, blockedIds: recordBlockedIds(prunedBlockedIds, newActionable) });
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
  main().catch(() => allowStop(lastResolvedPath ?? statePath(process.env)));
}
