#!/usr/bin/env node
// Unload completed Codex Companion threads without touching active work.
// The app-server exposes unloading as thread/unsubscribe; it is idempotent
// for threads that are already notLoaded.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// The Codex plugin lives in a version-keyed cache directory
// (~/.claude/plugins/cache/openai-codex/codex/<version>) that disappears when
// the plugin is updated, so the module path is resolved from the installed
// plugin manifest instead of being pinned to one version.
function resolveAppServerModule() {
  const manifestPath = path.join(os.homedir(), ".claude", "plugins", "installed_plugins.json");
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  } catch (error) {
    console.error(`codex-thread-gc: cannot read plugin manifest ${manifestPath}: ${error.message}`);
    process.exit(2);
  }
  const installs = manifest?.plugins?.["codex@openai-codex"];
  const entries = Array.isArray(installs) ? installs : installs ? [installs] : [];
  const install = entries.find((entry) => entry?.scope === "user") ?? entries[0];
  if (!install?.installPath) {
    console.error(`codex-thread-gc: codex@openai-codex is not installed for this user (manifest ${manifestPath})`);
    process.exit(2);
  }
  const modulePath = path.join(install.installPath, "scripts", "lib", "app-server.mjs");
  if (!fs.existsSync(modulePath)) {
    console.error(`codex-thread-gc: app-server module missing: ${modulePath}`);
    process.exit(2);
  }
  return modulePath;
}

const { CodexAppServerClient } = await import(resolveAppServerModule());

const args = new Set(process.argv.slice(2));
const ageArg = process.argv.find((arg) => arg.startsWith("--age-hours="));
const ageHours = Number(ageArg?.slice("--age-hours=".length) ?? process.env.CODEX_THREAD_GC_AGE_HOURS ?? 24);
if (!Number.isInteger(ageHours) || ageHours < 1 || ageHours > 24 * 365) {
  console.error("codex-thread-gc: --age-hours must be an integer from 1 to 8760");
  process.exit(2);
}
const apply = args.has("--apply");
const cutoff = Date.now() / 1000 - ageHours * 3600;

const client = await CodexAppServerClient.connect(process.cwd(), { disableBroker: true });
// The daemon's first page is the active/recent window. Do not walk historical
// pages: that can make a cleanup job contend with a large persisted history,
// while the retention contract only concerns currently loaded threads.
const page = await client.request("thread/list", { limit: 100 });
const threads = page.data ?? [];

const candidates = threads.filter((thread) =>
  thread.originator === "Codex Desktop" &&
  String(thread.name ?? "").startsWith("Codex Companion Task:") &&
  thread.status?.type === "idle" &&
  Number(thread.updatedAt ?? 0) < cutoff
);
console.log(JSON.stringify({
  scanned: threads.length,
  age_hours: ageHours,
  apply,
  candidates: candidates.length,
  ids: candidates.map((thread) => thread.id),
}));

let unloaded = 0;
if (apply) {
  for (const thread of candidates) {
    const result = await client.request("thread/unsubscribe", { threadId: thread.id });
    if (result.status === "unsubscribed") unloaded += 1;
  }
  console.log(JSON.stringify({ unloaded }));
}
await client.close();
