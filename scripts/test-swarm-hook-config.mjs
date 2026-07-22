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
  assert.equal(cursor.hooks.beforeSubmitPrompt, undefined);
});

test("Home Manager installs every managed hook surface", async () => {
  const files = await readFile("home/modules/files.nix", "utf8");
  assert.match(files, /\.copilot\/hooks\/swarm-messages\.json/);
  assert.match(files, /\.cursor\/hooks\.json/);
  assert.match(files, /replaceVars[\s\S]*config\/codex\/hooks\/swarm-messages\.mjs/);
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

test("Copilot wrapper exposes the Nix bash runtime required by native hooks", async () => {
  const tools = await readFile("home/modules/ai-tools.nix", "utf8");
  const wrapper = tools.slice(
    tools.indexOf('copilotAllWrapper = pkgs.writeShellScriptBin "copilot-all"'),
    tools.indexOf("in {", tools.indexOf('copilotAllWrapper = pkgs.writeShellScriptBin "copilot-all"')),
  );
  assert.match(wrapper, /export PATH="\$\{pkgs\.bash\}\/bin:/);
});

test("Goose and Copilot wrappers export one inherited session identity", async () => {
  const tools = await readFile("home/modules/ai-tools.nix", "utf8");

  assert.match(tools, /clientSessionIdentity = client:/);
  assert.match(tools, /export SE_WORKSPACE_OWNER="\$\{client\}:\$client_session_id"/);
  assert.match(tools, /agent\.client=\$\{client\},agent\.session\.id=\$client_session_id/);
  assert.match(tools, /clientSessionIdentity "goose"/);
  assert.match(tools, /clientSessionIdentity "copilot"/);
});

test("Home Manager enables the bundled Goose orchestrator", async () => {
  const template = await readFile("config/goose/config.yaml", "utf8");
  assert.match(template, /orchestrator:\n(?:.*\n){0,6}?\s+enabled: true/);

  const activation = await readFile("home/modules/activation.nix", "utf8");
  assert.match(activation, /extensions\["orchestrator"\]\s*=\s*\{[\s\S]*?"enabled": True/);
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
    assert.match(JSON.stringify(claude.hooks.SessionStart), /swarm-messages\.sh SessionStart/);
    assert.match(JSON.stringify(claude.hooks.UserPromptSubmit), /swarm-messages\.sh/);

    const updatedKimi = await readFile(join(home, "kimi.toml"), "utf8");
    assert.match(updatedKimi, /api_key = \"do-not-touch\"/);
    assert.match(updatedKimi, /event = \"Notification\"/);
    assert.equal((updatedKimi.match(/command = ".*swarm-messages\.sh"/g) ?? []).length, 1);
    assert.equal((updatedKimi.match(/command = ".*swarm-messages\.sh SessionStart"/g) ?? []).length, 1);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});
