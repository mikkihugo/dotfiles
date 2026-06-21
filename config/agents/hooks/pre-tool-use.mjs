#!/usr/bin/env node
// PreToolUse hook shim — delegates to dispatch.mjs
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const dispatch = join(__dirname, "dispatch.mjs");

try {
  execFileSync("node", [dispatch, "PreToolUse"], {
    stdio: ["inherit", "inherit", "inherit"],
    timeout: 10_000,
  });
} catch {
  // Fail open
  process.exit(0);
}
