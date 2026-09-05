#!/usr/bin/env node
import { chmod, mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
};
const home = process.env.HOME;
const claudePath = option("--claude-settings", join(home, ".claude", "settings.json"));
const kimiPath = option("--kimi-config", join(home, ".kimi-code", "config.toml"));
const jcodePath = option("--jcode-config", join(home, ".jcode", "config.toml"));

async function existingMode(path) {
  try { return (await stat(path)).mode & 0o777; }
  catch { return 0o600; }
}

async function atomicWrite(path, content) {
  await mkdir(dirname(path), { recursive: true });
  const mode = await existingMode(path);
  const temporary = `${path}.repo-memory-hooks.${process.pid}`;
  await writeFile(temporary, content, { mode });
  await chmod(temporary, mode);
  await rename(temporary, path);
}

async function installClaude() {
  let settings = {};
  try { settings = JSON.parse(await readFile(claudePath, "utf8")); }
  catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  settings.hooks ??= {};
  const install = (event, group) => {
    const existing = Array.isArray(settings.hooks[event]) ? settings.hooks[event] : [];
    settings.hooks[event] = existing
      .filter((item) => !/swarm-messages\.sh|coordination-mailbox-sweep\.sh/.test(JSON.stringify(item)))
      .concat(group);
  };
  install("SessionStart", {
    matcher: "startup|resume|clear|compact",
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/coordination-mailbox-sweep.sh SessionStart",
      timeout: 30,
    }],
  });
  install("UserPromptSubmit", {
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/coordination-mailbox-sweep.sh",
      timeout: 30,
    }],
  });
  await atomicWrite(claudePath, `${JSON.stringify(settings, null, 2)}\n`);
}

function withoutManagedKimiHooks(content) {
  const lines = content.split("\n");
  const kept = [];
  for (let index = 0; index < lines.length;) {
    const line = lines[index];
    if (line === "# BEGIN repo-memory swarm hooks" || line === "# END repo-memory swarm hooks") {
      index += 1;
      continue;
    }
    if (line.trim() !== "[[hooks]]") {
      kept.push(line);
      index += 1;
      continue;
    }
    const block = [line];
    index += 1;
    while (index < lines.length && !/^\s*\[\[?[^]]+\]\]?\s*$/.test(lines[index])) {
      block.push(lines[index]);
      index += 1;
    }
    if (!block.join("\n").includes("swarm-messages.sh")) kept.push(...block);
  }
  return kept.join("\n").trimEnd();
}

async function installKimi() {
  let content = "";
  try { content = await readFile(kimiPath, "utf8"); }
  catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const base = withoutManagedKimiHooks(content);
  const managed = [
    "# BEGIN repo-memory swarm hooks",
    "[[hooks]]",
    'event = "UserPromptSubmit"',
    'command = "/home/mhugo/.kimi-code/hooks/swarm-messages.sh"',
    "timeout = 10",
    "",
    "[[hooks]]",
    'event = "SessionStart"',
    'command = "/home/mhugo/.kimi-code/hooks/swarm-messages.sh SessionStart"',
    "timeout = 10",
    "# END repo-memory swarm hooks",
    "",
  ].join("\n");
  await atomicWrite(kimiPath, `${base}${base ? "\n\n" : ""}${managed}`);
}

async function installJcode() {
  let content = "";
  try { content = await readFile(jcodePath, "utf8"); }
  catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const command = 'session_start = "/home/mhugo/.codex/hooks/swarm-messages.mjs jcode SessionStart"';
  const lines = content.split("\n");
  const hooksIndex = lines.findIndex((line) => line.trim() === "[hooks]");
  if (hooksIndex < 0) {
    const base = content.trimEnd();
    await atomicWrite(jcodePath, `${base}${base ? "\n\n" : ""}[hooks]\n${command}\n`);
    return;
  }
  let end = hooksIndex + 1;
  while (end < lines.length && !/^\s*\[[^]]+\]\s*$/.test(lines[end])) end += 1;
  const hookLines = lines.slice(hooksIndex + 1, end)
    .filter((line) => !/^\s*session_start\s*=/.test(line));
  lines.splice(hooksIndex + 1, end - hooksIndex - 1, command, ...hookLines);
  await atomicWrite(jcodePath, lines.join("\n"));
}

await installClaude();
await installKimi();
await installJcode();
