#!/usr/bin/env node
import { chmod, copyFile, mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
};

// Single-source-of-truth: the engine's purpose-tool package. The mirror
// step below copies scripts from here into the dotfiles tree so home-manager
// can symlink them into $HOME. Editing the engine moves every client; editing
// here (this file) only changes what gets *wired into client configs*.
const engineHostHooks = option(
  "--engine-host-hooks",
  process.env.PURPOSE_TOOL_HOST_HOOKS ??
    "/home/mhugo/code/singularity-engine/fabrics/tools/services/purpose-tool/host-hooks",
);

const home = process.env.HOME;
const claudePath = option("--claude-settings", join(home, ".claude", "settings.json"));
const kimiPath = option("--kimi-config", join(home, ".kimi-code", "config.toml"));
const jcodePath = option("--jcode-config", join(home, ".jcode", "config.toml"));

const dotfilesRoot = option("--dotfiles-root", home);

// Mirror every script in the engine's host-hooks/ dir into the per-client
// dotfiles hook dirs (as vendored mirrors, not symlinks — so the dotfiles
// stays a self-contained source tree for home-manager).
async function mirrorScripts() {
  const entries = await readFile(join(engineHostHooks, "AGENTS.md"), "utf8").catch(() => null);
  if (entries === null) {
    throw new Error(
      `Cannot read engine host-hooks at ${engineHostHooks}/AGENTS.md — ` +
        `pass --engine-host-hooks <path> or set PURPOSE_TOOL_HOST_HOOKS`,
    );
  }
  const clients = ["kimi-code", "codex", "claude", "factory", "copilot"];
  const scripts = [
    "coordination-mailbox-sweep.sh",
    "coordination-mailbox-sweep.mjs",
    "observations-autolog.sh",
    "observations-autolog.mjs",
    "skills-gate-session-start.sh",
    "skills-gate-pretooluse.sh",
    "skills-gate-mark-loaded.sh",
  ];
  for (const client of clients) {
    const targetDir = join(dotfilesRoot, ".dotfiles", "config", client, "hooks");
    await mkdir(targetDir, { recursive: true });
    for (const script of scripts) {
      const src = join(engineHostHooks, script);
      const dst = join(targetDir, script);
      await copyFile(src, dst);
      await chmod(dst, 0o755);
    }
  }
  console.log(`[mirror] copied ${scripts.length} scripts from ${engineHostHooks} -> ${clients.length} client hook dirs`);
}

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
      .filter((item) => !/swarm-messages\.sh|coordination-mailbox-sweep\.sh|stop-continue-if-actionable\.sh|skills-gate-session-start\.sh/.test(JSON.stringify(item)))
      .concat(group);
  };
  install("SessionStart", {
    matcher: "startup|resume|clear|compact",
    hooks: [
      {
        type: "command",
        command: "/home/mhugo/.claude/hooks/coordination-mailbox-sweep.sh claude SessionStart",
        timeout: 30,
      },
      {
        type: "command",
        command: "/home/mhugo/.claude/hooks/skills-gate-session-start.sh",
        timeout: 10,
        statusMessage: "Loading skills gate",
      },
    ],
  });
  install("PreToolUse", {
    matcher: "Bash|Read|Edit|Write|Glob|Grep",
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/skills-gate-pretooluse.sh",
      timeout: 10,
      statusMessage: "Skills gate pretooluse",
    }],
  });
  install("UserPromptSubmit", {
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/coordination-mailbox-sweep.sh claude",
      timeout: 30,
    }],
  });
  install("Stop", {
    hooks: [
      {
        type: "command",
        command: "/home/mhugo/.claude/hooks/stop-continue-if-actionable.sh",
        timeout: 15,
      },
      {
        type: "command",
        command: "/home/mhugo/.claude/hooks/observations-autolog.sh claude Stop",
        timeout: 30,
        statusMessage: "Autolog observations to repo_memory",
      },
    ],
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
    if (!block.join("\n").includes("swarm-messages.sh") && !block.join("\n").includes("observations-autolog.sh")) kept.push(...block);
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
    'command = "/home/mhugo/.kimi-code/hooks/coordination-mailbox-sweep.sh kimi-code UserPromptSubmit"',
    "timeout = 30",
    "",
    "[[hooks]]",
    'event = "SessionStart"',
    'command = "/home/mhugo/.kimi-code/hooks/coordination-mailbox-sweep.sh kimi-code SessionStart"',
    "timeout = 30",
    "",
    "[[hooks]]",
    'event = "SessionStart"',
    'command = "/home/mhugo/.kimi-code/hooks/skills-gate-session-start.sh"',
    "timeout = 10",
    "",
    "[[hooks]]",
    'event = "Stop"',
    'command = "/home/mhugo/.kimi-code/hooks/observations-autolog.sh kimi-code Stop"',
    "timeout = 30",
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

await mirrorScripts();
await installClaude();
await installKimi();
await installJcode();
