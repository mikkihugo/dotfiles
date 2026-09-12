#!/usr/bin/env node
import { createHash } from "node:crypto";
import { chmod, mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
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
    "/home/mhugo/code/worktrees/jj/singularity-engine/purpose-tool-host-hooks-origin/fabrics/tools/services/purpose-tool/host-hooks",
);

const home = process.env.HOME;
const claudePath = option("--claude-settings", join(home, ".claude", "settings.json"));
const kimiPath = option("--kimi-config", join(home, ".kimi-code", "config.toml"));
const jcodePath = option("--jcode-config", join(home, ".jcode", "config.toml"));

const dotfilesRoot = option("--dotfiles-root", home);

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

async function copyIfHashMismatch(src, dst) {
  const srcBuf = await readFile(src);
  try {
    const dstBuf = await readFile(dst);
    if (sha256(dstBuf) === sha256(srcBuf)) return "unchanged";
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  await mkdir(dirname(dst), { recursive: true });
  await writeFile(dst, srcBuf);
  await chmod(dst, 0o755);
  return "replaced";
}

// Mirror every script in the engine's host-hooks/ dir into the per-client
// dotfiles hook dirs (as vendored mirrors, not symlinks — so the dotfiles
// stays a self-contained source tree for home-manager).
async function mirrorScripts() {
  const entries = await readFile(join(engineHostHooks, "AGENTS.md"), "utf8").catch(() => null);
  if (entries === null) {
    console.warn(
      `[mirror] engine host-hooks not found at ${engineHostHooks} — ` +
        `skipping mirror (existing dotfiles source will be used). ` +
        `pass --engine-host-hooks or set PURPOSE_TOOL_HOST_HOOKS to enable.`,
    );
    return;
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
      await copyIfHashMismatch(src, dst);
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
  // Renamed hooks we no longer install but must still evict from an old
  // settings.json. Everything we DO install is derived from the group below,
  // so this list never has to grow again: a hand-maintained strip list is what
  // let skills-gate-pretooluse.sh and observations-autolog.sh duplicate on
  // every hms, firing Claude's skills gate twice per tool call.
  const legacyHookNames = ["swarm-messages.sh"];
  const install = (event, group) => {
    const managedNames = [
      ...legacyHookNames,
      ...group.hooks.map((hook) => hook.command.split(/\s+/)[0].split("/").pop()),
    ];
    const existing = Array.isArray(settings.hooks[event]) ? settings.hooks[event] : [];
    settings.hooks[event] = existing
      .filter((item) => {
        const serialised = JSON.stringify(item);
        return !managedNames.some((name) => serialised.includes(name));
      })
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
        timeout: 30,
        statusMessage: "Loading skills gate",
      },
    ],
  });
  install("PreToolUse", {
    matcher: "Bash|Read|Edit|Write|Glob|Grep",
    hooks: [{
      type: "command",
      command: "/home/mhugo/.claude/hooks/skills-gate-pretooluse.sh",
      timeout: 30,
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
    // Every managed hook name must be listed here. A name the installer emits
    // but this strip misses survives the rewrite and is then re-appended, so
    // the managed block silently duplicates on the next hms.
    const body = block.join("\n");
    const managedNames = [
      "swarm-messages.sh",
      "observations-autolog.sh",
      "coordination-mailbox-sweep.sh",
      "skills-gate-session-start.sh",
    ];
    if (!managedNames.some((name) => body.includes(name))) kept.push(...block);
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
    "timeout = 30",
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
