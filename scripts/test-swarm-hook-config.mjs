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
  assert.match(JSON.stringify(codex.hooks.SessionStart), /swarm-messages\.mjs codex SessionStart/);
  assert.match(JSON.stringify(codex.hooks.UserPromptSubmit), /swarm-messages\.mjs codex UserPromptSubmit/);
  assert.match(codex.description, /repo-memory/);

  const copilot = await readJSON("config/copilot/hooks/swarm-messages.json");
  assert.equal(copilot.version, 1);
  assert.match(copilot.hooks.sessionStart[0].bash, /swarm-messages\.mjs copilot/);
  assert.match(copilot.hooks.userPromptTransformed[0].bash, /swarm-messages\.mjs copilot/);

  const cursor = await readJSON("config/cursor/hooks.json");
  assert.equal(cursor.version, 1);
  assert.match(JSON.stringify(cursor.hooks.sessionStart), /swarm-messages\.mjs cursor/);
  assert.match(JSON.stringify(cursor.hooks.beforeSubmitPrompt), /swarm-messages\.mjs cursor beforeSubmitPrompt/);

  const factory = await readJSON("config/factory/settings.json");
  assert.match(JSON.stringify(factory.hooks.SessionStart), /swarm-messages\.mjs factory SessionStart/);
  assert.match(JSON.stringify(factory.hooks.UserPromptSubmit), /swarm-messages\.mjs factory UserPromptSubmit/);
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
