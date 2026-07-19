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
      .filter((item) => !JSON.stringify(item).includes("swarm-messages.sh"))
      .concat(group);
  };
  install("SessionStart", {
    matcher: "startup|resume|clear|compact",
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/swarm-messages.sh SessionStart",
      timeout: 10,
    }],
  });
  install("UserPromptSubmit", {
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/swarm-messages.sh",
      timeout: 10,
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

await installClaude();
await installKimi();
