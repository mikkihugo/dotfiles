#!/usr/bin/env node
/**
 * Hook dispatcher — shared logic for all lifecycle hook events.
 *
 * Purpose: centralize hook event handling so each event shim is a one-liner.
 * Consumer: the 8 event-specific shims (session-start.mjs, stop.mjs, etc.)
 * called by Claude Code / Codex / Copilot / Kimi hook engines.
 * Failure consequence: hooks silently fail-open (exit 0) — no blocking.
 * Falsifier: a hook event that receives a non-zero exit code when it should block.
 *
 * Usage: node dispatch.mjs <EventName>
 * Reads JSON event data from stdin. Exits 0 (allow) or 2 (block).
 */
import { readFileSync } from "node:fs";

const BLOCK_EXIT_CODE = 2;
const ALLOW_EXIT_CODE = 0;

const BLOCKABLE_EVENTS = new Set(["PreToolUse", "UserPromptSubmit", "Stop"]);

function main() {
  const eventName = process.argv[2] || "Unknown";

  let input = {};
  try {
    const raw = readFileSync("/dev/stdin", "utf8");
    if (raw.trim()) input = JSON.parse(raw);
  } catch {
    // Invalid stdin — fail open
    process.exit(ALLOW_EXIT_CODE);
  }

  // Currently all hooks are observation-only (fail-open).
  // To add blocking logic, check input for specific patterns
  // and exit with BLOCK_EXIT_CODE for blockable events.
  //
  // Example: block dangerous bash commands in PreToolUse
  // if (eventName === "PreToolUse" && input.tool_name === "Bash") {
  //   const cmd = input.tool_input?.command || "";
  //   if (/rm\s+-rf\s+\//.test(cmd)) {
  //     process.stderr.write("Blocked: destructive rm -rf on root\n");
  //     process.exit(BLOCK_EXIT_CODE);
  //   }
  // }

  process.exit(ALLOW_EXIT_CODE);
}

main();
