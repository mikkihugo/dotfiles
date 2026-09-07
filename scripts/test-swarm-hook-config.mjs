import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const readJSON = async (path) => JSON.parse(await readFile(path, "utf8"));

test("Home Manager owns schema-valid Codex hooks.json with repo-memory swarm registration", async () => {
  const codex = await readJSON("config/codex/hooks.json");
  assert.equal(codex.version, undefined);
  // Codex SessionStart + UserPromptSubmit point at the coordination-mailbox-sweep
  // successor (the bounded, cursor-based hook). The legacy swarm-messages.mjs
  // path stays installed as a compatibility shim for clients that still name it
  // directly (copilot/cursor/factory below), but the HM-owned codex config no
  // longer references it -- so a codex session must produce a
  // coordination-mailbox-<identity>.cursor.json under
  // /home/mhugo/.local/state/coordination-mailbox/ on its first poll.
  assert.match(JSON.stringify(codex.hooks.SessionStart), /coordination-mailbox-sweep\.mjs codex SessionStart/);
  assert.match(JSON.stringify(codex.hooks.UserPromptSubmit), /coordination-mailbox-sweep\.mjs codex UserPromptSubmit/);
  assert.match(codex.description, /repo-memory/);

  const copilot = await readJSON("config/copilot/hooks/swarm-messages.json");
  assert.equal(copilot.version, 1);
  // Copilot migrated off the legacy swarm-messages.mjs shim onto the
  // HM-rendered coordination-mailbox-sweep.sh shim (mirrors the Claude and
  // Kimi-Code wiring). Factory still keeps the legacy path in its own lane.
  // Copilot CLI uses {type:command, exec, args, timeoutSec} (not codex/claude's
  // {type:command, command, timeout}); wire the assertion accordingly.
  const COPIOT_SHIM = "/home/mhugo/.copilot/hooks/coordination-mailbox-sweep.sh";
  assert.deepEqual(copilot.hooks.sessionStart[0].args, [COPIOT_SHIM, "copilot", "sessionStart"]);
  assert.deepEqual(copilot.hooks.userPromptTransformed[0].args, [COPIOT_SHIM, "copilot", "userPromptTransformed"]);
  assert.doesNotMatch(JSON.stringify(copilot.hooks), /swarm-messages\.mjs copilot/);

  const cursor = await readJSON("config/cursor/hooks.json");
  assert.equal(cursor.version, 1);
  // Cursor migrated off the legacy swarm-messages.mjs shim onto the HM-installed
  // coordination-mailbox-sweep.mjs (same successor codex/claude/kimi/copilot use).
  // Identity is cursor-<short CURSOR_CONVERSATION_ID>, not a sha256 of the full id.
  assert.match(JSON.stringify(cursor.hooks.sessionStart), /coordination-mailbox-sweep\.mjs cursor sessionStart/);
  assert.match(JSON.stringify(cursor.hooks.beforeSubmitPrompt), /coordination-mailbox-sweep\.mjs cursor beforeSubmitPrompt/);
  assert.doesNotMatch(JSON.stringify(cursor.hooks), /swarm-messages\.mjs cursor/);

  const factory = await readJSON("config/factory/settings.json");
  assert.match(JSON.stringify(factory.hooks.SessionStart), /swarm-messages\.mjs factory SessionStart/);
  assert.match(JSON.stringify(factory.hooks.UserPromptSubmit), /swarm-messages\.mjs factory UserPromptSubmit/);
});

test("codex hooks.json wires SessionStart + UserPromptSubmit at coordination-mailbox-sweep.mjs, not the legacy swarm-messages.mjs shim", async () => {
  // RED-first contract for the codex migration. The HM-rendered codex config
  // must name the new hook for both lifecycle events; the old hook is not a
  // codex invocation target anymore. Factory still names swarm-messages.mjs
  // and is covered by the bundled schema test above.
  const codex = await readJSON("config/codex/hooks.json");
  const sessionStart = JSON.stringify(codex.hooks.SessionStart);
  const userPromptSubmit = JSON.stringify(codex.hooks.UserPromptSubmit);
  assert.match(sessionStart, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs codex SessionStart/);
  assert.match(userPromptSubmit, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs codex UserPromptSubmit/);
  assert.doesNotMatch(sessionStart, /swarm-messages\.mjs codex/);
  assert.doesNotMatch(userPromptSubmit, /swarm-messages\.mjs codex/);
});

test("cursor hooks.json wires sessionStart + beforeSubmitPrompt at coordination-mailbox-sweep.mjs, not the legacy swarm-messages.mjs shim", async () => {
  // Cursor uses the HM-installed ~/.codex/hooks/coordination-mailbox-sweep.mjs
  // (same binary as Codex) with client name `cursor` and Cursor event names.
  const cursor = await readJSON("config/cursor/hooks.json");
  const sessionStart = JSON.stringify(cursor.hooks.sessionStart);
  const beforeSubmitPrompt = JSON.stringify(cursor.hooks.beforeSubmitPrompt);
  assert.match(sessionStart, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs cursor sessionStart/);
  assert.match(beforeSubmitPrompt, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs cursor beforeSubmitPrompt/);
  assert.doesNotMatch(sessionStart, /swarm-messages\.mjs/);
  assert.doesNotMatch(beforeSubmitPrompt, /swarm-messages\.mjs/);
  // Stable-shell + optional purpose-tool session hooks stay on sessionStart.
  assert.match(sessionStart, /fix-stable-shell-chmod\.cjs/);
  assert.match(sessionStart, /purpose-tool\/hooks\/session-start\.mjs/);
});

test("copilot hooks wire sessionStart + userPromptTransformed at the HM-rendered coordination-mailbox-sweep.sh shim", async () => {
  // RED-first contract for the copilot migration. Copilot's hook schema uses
  // lowercase event names (sessionStart / userPromptTransformed) and
  // `exec` + `args` + `timeoutSec`, distinct from codex/claude/factory.
  // NOTE: these were a flat `bash` command string until 8888fe79. That field is
  // passed to the runtime's DEFAULT bash (/run/current-system/sw/bin/bash),
  // which does not exist on non-NixOS hosts -- every prompt failed with
  // `spawn ... ENOENT`. Hence the explicit interpreter + argv, and hence these
  // assertions check the argv array rather than a flattened command string. The HM
  // wiring must therefore (a) render ~/.copilot/hooks/coordination-mailbox-sweep.sh
  // from config/copilot/hooks/coordination-mailbox-sweep.sh, and (b) make
  // config/copilot/hooks/swarm-messages.json invoke that shim with `copilot`
  // as the client name. A copilot session under the new wiring must produce
  // a coordination-mailbox-copilot-*.cursor.json under
  // /home/mhugo/.local/state/coordination-mailbox/ on its first poll.
  const copilot = await readJSON("config/copilot/hooks/swarm-messages.json");
  const sessionStart = JSON.stringify(copilot.hooks.sessionStart);
  const userPromptTransformed = JSON.stringify(copilot.hooks.userPromptTransformed);
  const SHIM = "/home/mhugo/.copilot/hooks/coordination-mailbox-sweep.sh";
  assert.deepEqual(copilot.hooks.sessionStart[0].args, [SHIM, "copilot", "sessionStart"]);
  assert.deepEqual(copilot.hooks.userPromptTransformed[0].args, [SHIM, "copilot", "userPromptTransformed"]);
  assert.doesNotMatch(sessionStart, /swarm-messages\.mjs copilot/);
  assert.doesNotMatch(userPromptTransformed, /swarm-messages\.mjs copilot/);

  const files = await readFile("home/modules/files.nix", "utf8");
  assert.match(files, /replaceVars[\s\S]*config\/copilot\/hooks\/coordination-mailbox-sweep\.sh/);
  const shim = await readFile("config/copilot/hooks/coordination-mailbox-sweep.sh", "utf8");
  assert.match(shim, /^#!@bash@/);
  assert.match(shim, /exec @node@ \/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs copilot/);
});

test("Home Manager installs every managed hook surface", async () => {
  const files = await readFile("home/modules/files.nix", "utf8");
  assert.match(files, /\.copilot\/hooks\/swarm-messages\.json/);
  assert.match(files, /\.cursor\/hooks\.json/);
  assert.match(files, /replaceVars[\s\S]*config\/codex\/hooks\/swarm-messages\.mjs/);
  const codexHook = files.slice(
    files.indexOf('".codex/hooks/swarm-messages.mjs"'),
    files.indexOf('".claude/hooks/swarm-messages.sh"'),
  );
  assert.match(codexHook, /flock = "\$\{pkgs\.util-linux\}\/bin\/flock"/);
  assert.match(codexHook, /bash = "\$\{pkgs\.bash\}\/bin\/bash"/);
  assert.match(files, /replaceVars[\s\S]*config\/claude\/hooks\/swarm-messages\.sh/);
  assert.match(files, /replaceVars[\s\S]*config\/kimi-code\/hooks\/swarm-messages\.sh/);
  const activation = await readFile("home/modules/activation.nix", "utf8");
  assert.match(activation, /install-swarm-hooks\.mjs/);

  assert.match(await readFile("config/codex/hooks/swarm-messages.mjs", "utf8"), /^#!@node@/);
  for (const path of ["config/claude/hooks/swarm-messages.sh", "config/kimi-code/hooks/swarm-messages.sh"]) {
    const wrapper = await readFile(path, "utf8");
    assert.match(wrapper, /^#!@bash@/);
    assert.match(wrapper, /exec @node@/);
  }
});

test("Goose and JCode wrappers export one inherited session identity", async () => {
  const tools = await readFile("home/modules/ai-tools.nix", "utf8");

  assert.match(tools, /clientSessionIdentity = client:/);
  assert.match(tools, /export SE_WORKSPACE_OWNER="\$\{client\}:\$client_session_id"/);
  assert.match(tools, /agent\.client=\$\{client\},agent\.session\.id=\$client_session_id/);
  assert.match(tools, /clientSessionIdentity "goose"/);
  assert.match(tools, /clientSessionIdentity "jcode"/);
});

test("Home Manager enables only Summon delegation with ten background tasks", async () => {
  const template = await readFile("config/goose/config.yaml", "utf8");
  assert.match(template, /summon:\n(?:.*\n){0,6}?\s+enabled: true/);
  assert.doesNotMatch(template, /^\s+orchestrator:$/m);
  assert.match(template, /^GOOSE_MAX_BACKGROUND_TASKS: 10(?:\s+#.*)?$/m);

  const activation = await readFile("home/modules/activation.nix", "utf8");
  assert.match(activation, /extensions\["summon"\]\s*=\s*\{[\s\S]*?"enabled": True/);
  assert.match(activation, /extensions\.pop\("orchestrator", None\)/);
  assert.match(activation, /goose_config\["GOOSE_MAX_BACKGROUND_TASKS"\] = 10/);

  const wrapper = await readFile("home/modules/ai-tools.nix", "utf8");
  assert.match(wrapper, /GOOSE_MAX_BACKGROUND_TASKS:-10/);
});

test("Goose uses Kimi K3 as main and MiniMax M3 as planner", async () => {
  const template = await readFile("config/goose/config.yaml", "utf8");
  assert.match(template, /^GOOSE_MODEL: kimi-code\/k3$/m);
  assert.match(template, /^GOOSE_PLANNER_MODEL: minimax-coding-plan\/MiniMax-M3$/m);
  assert.match(template, /^GOOSE_FAST_MODEL: auto-flash$/m);

  const activation = await readFile("home/modules/activation.nix", "utf8");
  assert.match(activation, /goose_config\["GOOSE_MODEL"\] = "kimi-code\/k3"/);
  assert.match(activation, /goose_config\["GOOSE_PLANNER_MODEL"\] = "minimax-coding-plan\/MiniMax-M3"/);
  assert.match(activation, /goose_config\["GOOSE_FAST_MODEL"\] = "auto-flash"/);

  const wrapper = await readFile("home/modules/ai-tools.nix", "utf8");
  assert.match(wrapper, /GOOSE_MODEL:-kimi-code\/k3/);
  assert.match(wrapper, /GOOSE_PLANNER_MODEL:-minimax-coding-plan\/MiniMax-M3/);
  assert.match(wrapper, /GOOSE_FAST_MODEL:-auto-flash/);
  assert.ok(
    wrapper.indexOf("mise/installs/github-aaif-goose-goose") < wrapper.indexOf("mise/shims/goose"),
    "Goose wrapper must prefer the installed binary over the registry-dependent mise shim",
  );

  const mise = await readFile("config/mise/config.toml", "utf8");
  assert.match(mise, /^"github:aaif-goose\/goose" = "latest"$/m);
  assert.doesNotMatch(mise, /aqua:aaif-goose\/goose/);
  assert.doesNotMatch(mise, /^"npm:@openai\/codex"/m);
});

test("activation merge preserves unrelated Claude settings and Kimi provider content", async () => {
  const home = await mkdtemp(join(tmpdir(), "repo-memory-hook-home-"));
  try {
    await writeFile(join(home, "claude.json"), JSON.stringify({ language: "English", hooks: { PreToolUse: [{ matcher: "Bash", hooks: [] }] } }));
    const kimi = "[providers.keep_me]\napi_key = \"do-not-touch\"\n\n[[hooks]]\nevent = \"Notification\"\ncommand = \"notify\"\n";
    await writeFile(join(home, "kimi.toml"), kimi);
    const result = spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi.toml"),
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);

    const claude = await readJSON(join(home, "claude.json"));
    assert.equal(claude.language, "English");
    assert.equal(claude.hooks.PreToolUse[0].matcher, "Bash");
    assert.match(JSON.stringify(claude.hooks.SessionStart), /coordination-mailbox-sweep\.sh SessionStart/);
    assert.match(JSON.stringify(claude.hooks.UserPromptSubmit), /coordination-mailbox-sweep\.sh/);
    assert.match(JSON.stringify(claude.hooks.SessionStart), /"timeout":30/);
    assert.match(JSON.stringify(claude.hooks.UserPromptSubmit), /"timeout":30/);

    const updatedKimi = await readFile(join(home, "kimi.toml"), "utf8");
    assert.match(updatedKimi, /api_key = \"do-not-touch\"/);
    assert.match(updatedKimi, /event = \"Notification\"/);
    assert.equal((updatedKimi.match(/command = ".*swarm-messages\.sh"/g) ?? []).length, 1);
    assert.equal((updatedKimi.match(/command = ".*swarm-messages\.sh SessionStart"/g) ?? []).length, 1);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("activation merge installs JCode session bootstrap without replacing unrelated hooks", async () => {
  const home = await mkdtemp(join(tmpdir(), "repo-memory-jcode-hook-home-"));
  try {
    const jcodePath = join(home, "jcode.toml");
    await writeFile(jcodePath, '[hooks]\nturn_end = "notify-finished"\npre_tool_timeout_ms = 1500\n');
    const result = spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi.toml"),
      "--jcode-config", jcodePath,
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);

    const updated = await readFile(jcodePath, "utf8");
    assert.match(updated, /turn_end = "notify-finished"/);
    assert.match(updated, /pre_tool_timeout_ms = 1500/);
    assert.match(updated, /session_start = ".*swarm-messages\.mjs jcode SessionStart"/);
    assert.equal((updated.match(/^session_start = /gm) ?? []).length, 1);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});
