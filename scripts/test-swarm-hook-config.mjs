import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmod, mkdtemp, readFile, rm, stat, utimes, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const readJSON = async (path) => JSON.parse(await readFile(path, "utf8"));

test("Home Manager owns schema-valid Codex hooks.json with repo-memory swarm registration", async () => {
  const codex = await readJSON("config/codex/hooks.json");
  assert.equal(codex.version, undefined);
  // Codex SessionStart + UserPromptSubmit point at the coordination-mailbox-sweep
  // successor (the bounded, cursor-based hook), reached through the HM-rendered
  // .sh shim -- the shim is what exports REPO_MEMORY_COORDINATION_BUS=1, so
  // naming the .mjs directly would silently drop codex onto the legacy
  // RepoMemoryBus path (see the dedicated shim test below). The legacy swarm-messages.mjs
  // path stays installed as a compatibility shim for clients that still name it
  // directly (copilot/cursor/factory below), but the HM-owned codex config no
  // longer references it -- so a codex session must produce a
  // coordination-mailbox-<identity>.cursor.json under
  // /home/mhugo/.local/state/coordination-mailbox/ on its first poll.
  assert.match(JSON.stringify(codex.hooks.SessionStart), /coordination-mailbox-sweep\.sh codex SessionStart/);
  assert.match(JSON.stringify(codex.hooks.UserPromptSubmit), /coordination-mailbox-sweep\.sh codex UserPromptSubmit/);
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
  assert.match(JSON.stringify(factory.hooks.SessionStart), /coordination-mailbox-sweep\.sh factory SessionStart/);
  assert.match(JSON.stringify(factory.hooks.UserPromptSubmit), /coordination-mailbox-sweep\.sh factory UserPromptSubmit/);
  assert.doesNotMatch(JSON.stringify(factory.hooks), /swarm-messages\.mjs factory/);
});

test("codex hooks.json wires SessionStart + UserPromptSubmit at the HM-rendered coordination-mailbox-sweep.sh shim, not the legacy swarm-messages.mjs shim", async () => {
  // RED-first contract for the codex migration. The HM-rendered codex config
  // must name the new hook for both lifecycle events; the old hook is not a
  // codex invocation target anymore. Factory still names swarm-messages.mjs
  // and is covered by the bundled schema test above.
  //
  // codex invokes the .sh shim rather than the .mjs directly (same shape as
  // copilot and factory) because the shim is the only place
  // REPO_MEMORY_COORDINATION_BUS=1 is exported; that flag is what routes the
  // sweep through CoordinationBus and its atomic server-side multi-ack instead
  // of the legacy per-mailbox RepoMemoryBus path.
  const codex = await readJSON("config/codex/hooks.json");
  const sessionStart = JSON.stringify(codex.hooks.SessionStart);
  const userPromptSubmit = JSON.stringify(codex.hooks.UserPromptSubmit);
  assert.match(sessionStart, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.sh codex SessionStart/);
  assert.match(userPromptSubmit, /\/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.sh codex UserPromptSubmit/);
  assert.doesNotMatch(sessionStart, /swarm-messages\.mjs codex/);
  assert.doesNotMatch(userPromptSubmit, /swarm-messages\.mjs codex/);

  // The shim the config now names must actually be rendered by HM, must export
  // the coordination-bus flag, and must hand off to the .mjs -- otherwise the
  // assertions above pin a path that resolves to nothing at runtime.
  const files = await readFile("home/modules/files.nix", "utf8");
  assert.match(files, /replaceVars[\s\S]*config\/codex\/hooks\/coordination-mailbox-sweep\.sh/);
  const shim = await readFile("config/codex/hooks/coordination-mailbox-sweep.sh", "utf8");
  assert.match(shim, /export REPO_MEMORY_COORDINATION_BUS=1/);
  assert.match(shim, /exec @node@ \/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs/);
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
  assert.match(shim, /exec @node@ \/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs "\$\{1:-kimi-code\}"/);
});

test("factory settings.json wires SessionStart + UserPromptSubmit at the HM-rendered coordination-mailbox-sweep.sh shim", async () => {
  // RED-first contract for the factory migration. Factory's hook schema mirrors
  // codex (PascalCase SessionStart / UserPromptSubmit events, `command` + `timeout`
  // fields) but routes through the HM-rendered coordination-mailbox-sweep.sh shim.
  // The wiring must therefore (a) render ~/.factory/hooks/coordination-mailbox-sweep.sh
  // from config/factory/hooks/coordination-mailbox-sweep.sh, and (b) make
  // config/factory/settings.json invoke that shim with `factory` as the client name.
  const factory = await readJSON("config/factory/settings.json");
  const sessionStart = JSON.stringify(factory.hooks.SessionStart);
  const userPromptSubmit = JSON.stringify(factory.hooks.UserPromptSubmit);
  assert.match(sessionStart, /\/home\/mhugo\/\.factory\/hooks\/coordination-mailbox-sweep\.sh factory SessionStart/);
  assert.match(userPromptSubmit, /\/home\/mhugo\/\.factory\/hooks\/coordination-mailbox-sweep\.sh factory UserPromptSubmit/);
  assert.doesNotMatch(sessionStart, /swarm-messages\.mjs factory/);
  assert.doesNotMatch(userPromptSubmit, /swarm-messages\.mjs factory/);

  const files = await readFile("home/modules/files.nix", "utf8");
  assert.match(files, /replaceVars[\s\S]*config\/factory\/hooks\/coordination-mailbox-sweep\.sh/);
  const shim = await readFile("config/factory/hooks/coordination-mailbox-sweep.sh", "utf8");
  assert.match(shim, /^#!@bash@/);
  assert.match(shim, /exec @node@ \/home\/mhugo\/\.codex\/hooks\/coordination-mailbox-sweep\.mjs "\$\{1:-kimi-code\}"/);
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
    assert.match(JSON.stringify(claude.hooks.SessionStart), /coordination-mailbox-sweep\.sh claude SessionStart/);
    assert.match(JSON.stringify(claude.hooks.UserPromptSubmit), /coordination-mailbox-sweep\.sh/);
    assert.match(JSON.stringify(claude.hooks.SessionStart), /"timeout":30/);
    assert.match(JSON.stringify(claude.hooks.UserPromptSubmit), /"timeout":30/);

    // The skills gate must be installed BY THIS SCRIPT, not by hand-editing
    // settings.json. install() drops every group matching its filter regex and
    // re-adds its own, so an entry added directly to the live file is deleted
    // on the next activation -- which is exactly what happened: the gate was
    // registered by hand, `hms` ran, and it vanished with no error anywhere.
    assert.match(
      JSON.stringify(claude.hooks.SessionStart),
      /skills-gate-session-start\.sh/,
      "skills gate missing from SessionStart -- it would be deployed but never fire",
    );

    // Idempotent across activations: a second run must not duplicate it.
    //
    // The second run deliberately targets a THROWAWAY kimi config rather than
    // reusing kimi.toml above. Reusing it makes this test fail on a genuine,
    // separate, PRE-EXISTING bug: a second installer run drops the user's own
    // unmanaged [[hooks]] block from kimi.toml (reproduced -- Notification hook
    // present after run 1, gone after run 2, still gone after run 3). Since
    // activation runs on every `hms`, the second switch destroys it. That bug
    // is real and reported, but it is not this change's to fix, and coupling
    // the Claude idempotency assertion to it would leave a permanently red
    // test that says nothing about the skills gate.
    const second = spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi-second-run.toml"),
    ], { encoding: "utf8" });
    assert.equal(second.status, 0, second.stderr);
    const reran = await readJSON(join(home, "claude.json"));
    assert.equal(
      (JSON.stringify(reran.hooks.SessionStart).match(/skills-gate-session-start\.sh/g) ?? []).length,
      1,
    );
    assert.equal(reran.hooks.PreToolUse[0].matcher, "Bash");

    const updatedKimi = await readFile(join(home, "kimi.toml"), "utf8");
    assert.match(updatedKimi, /api_key = \"do-not-touch\"/);
    assert.match(updatedKimi, /event = \"Notification\"/);
    assert.equal((updatedKimi.match(/command = ".*coordination-mailbox-sweep\.sh/g) ?? []).length, 2);
    assert.equal((updatedKimi.match(/command = ".*coordination-mailbox-sweep\.sh kimi-code SessionStart"/g) ?? []).length, 1);
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

test("repo-memory hook timeouts match the 30s fleet standard (dotfiles #28)", async () => {
  // Codex's Stop hook runs observations-autolog.mjs, whose memory_retain
  // round trip routinely exceeds 20s server-side; 10s killed it mid-flight.
  // Claude, copilot, and kimi already budget 30s for the same hook.
  const codexHooks = await readJSON("config/codex/hooks.json");
  const stopHook = codexHooks.hooks.Stop[0].hooks.find(
    (hook) => /observations-autolog/.test(hook.command),
  );
  assert.ok(stopHook, "codex Stop hook must run observations-autolog");
  assert.equal(stopHook.timeout, 30);

  const home = await mkdtemp(join(tmpdir(), "repo-memory-hook-home-"));
  try {
    await writeFile(join(home, "claude.json"), "{}");
    await writeFile(join(home, "kimi.toml"), "");
    const result = spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi.toml"),
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);

    const kimi = await readFile(join(home, "kimi.toml"), "utf8");
    assert.doesNotMatch(kimi, /timeout = 10/, "kimi managed hooks must not sit at the 10s budget that times out on cold gateway starts");
    const thirtySecondBudgets = (kimi.match(/timeout = 30/g) ?? []).length;
    assert.ok(
      thirtySecondBudgets >= 3,
      `expected the kimi sweep (x2) and autolog hooks at 30s, found ${thirtySecondBudgets}`,
    );

    // The kimi assertion above left Claude unguarded, so the skills-gate hooks
    // sat at 10s and timed out on cold gateway starts exactly like codex's did.
    const claudeSettings = JSON.parse(await readFile(join(home, "claude.json"), "utf8"));
    const claudeHooks = Object.values(claudeSettings.hooks)
      .flat()
      .flatMap((group) => group.hooks ?? []);
    const tenSecondClaudeHooks = claudeHooks.filter((hook) => hook.timeout === 10);
    assert.deepEqual(
      tenSecondClaudeHooks.map((hook) => hook.command),
      [],
      "claude managed hooks must not sit at the 10s budget that times out on cold gateway starts",
    );
    for (const name of ["skills-gate-session-start.sh", "skills-gate-pretooluse.sh"]) {
      const hook = claudeHooks.find((entry) => entry.command.includes(name));
      assert.ok(hook, `claude must register ${name}`);
      assert.equal(hook.timeout, 30, `${name} must budget 30s`);
    }
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("a second install does not duplicate managed hook blocks (dotfiles #28)", async () => {
  // withoutManagedKimiHooks strips by hook name, so a name the installer emits
  // but the strip list misses survives the rewrite and is re-appended: the
  // managed block grows by one copy per hms. coordination-mailbox-sweep.sh was
  // missing from that list.
  const home = await mkdtemp(join(tmpdir(), "repo-memory-hook-dup-"));
  try {
    await writeFile(join(home, "claude.json"), "{}");
    await writeFile(join(home, "kimi.toml"), "");
    const run = () => spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi.toml"),
    ], { encoding: "utf8" });

    assert.equal(run().status, 0);
    const afterFirst = await readFile(join(home, "kimi.toml"), "utf8");
    assert.equal(run().status, 0);
    const afterSecond = await readFile(join(home, "kimi.toml"), "utf8");

    assert.equal(
      afterSecond,
      afterFirst,
      "installing twice must be a no-op; a surviving managed block means the strip list is missing a hook name",
    );
    const sweepBlocks = (afterSecond.match(/coordination-mailbox-sweep\.sh/g) ?? []).length;
    assert.equal(sweepBlocks, 2, `expected exactly the UserPromptSubmit + SessionStart sweep entries, found ${sweepBlocks}`);

    const claudeSettings = JSON.parse(await readFile(join(home, "claude.json"), "utf8"));
    for (const [event, groups] of Object.entries(claudeSettings.hooks)) {
      const commands = groups.flatMap((group) => (group.hooks ?? []).map((hook) => hook.command));
      assert.equal(
        new Set(commands).size,
        commands.length,
        `claude ${event} has duplicate hook commands after a second install: ${commands.join(", ")}`,
      );
    }
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("the installer evicts the renamed legacy hook from an existing config (dotfiles #28)", async () => {
  // swarm-messages.sh was renamed to coordination-mailbox-sweep.sh. The strip
  // must still evict the OLD name from a config written before the rename, or
  // the legacy hook stays registered alongside its replacement and every
  // lifecycle event sweeps twice. Nothing covered this: the other tests seed an
  // empty or unrelated config, so deleting the legacy-name list broke nothing.
  const home = await mkdtemp(join(tmpdir(), "repo-memory-hook-legacy-"));
  try {
    await writeFile(join(home, "claude.json"), JSON.stringify({
      language: "English",
      hooks: {
        SessionStart: [{
          matcher: "startup",
          hooks: [{ type: "command", command: "/home/mhugo/.claude/hooks/swarm-messages.sh claude SessionStart", timeout: 10 }],
        }],
      },
    }));
    await writeFile(
      join(home, "kimi.toml"),
      '[providers.keep_me]\napi_key = "do-not-touch"\n\n'
        + '[[hooks]]\nevent = "SessionStart"\ncommand = "/home/mhugo/.kimi-code/hooks/swarm-messages.sh kimi-code SessionStart"\ntimeout = 10\n',
    );
    const result = spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--claude-settings", join(home, "claude.json"),
      "--kimi-config", join(home, "kimi.toml"),
    ], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);

    const claude = await readFile(join(home, "claude.json"), "utf8");
    assert.doesNotMatch(claude, /swarm-messages\.sh/, "the renamed legacy Claude hook must be evicted, not left beside its replacement");
    assert.match(claude, /coordination-mailbox-sweep\.sh claude SessionStart/);
    assert.match(claude, /"language": "English"/, "unrelated settings must survive the strip");

    const kimi = await readFile(join(home, "kimi.toml"), "utf8");
    assert.doesNotMatch(kimi, /swarm-messages\.sh/, "the renamed legacy Kimi hook must be evicted, not left beside its replacement");
    assert.match(kimi, /coordination-mailbox-sweep\.sh kimi-code SessionStart/);
    assert.match(kimi, /api_key = "do-not-touch"/, "unrelated provider content must survive the strip");
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("files.nix declares every hook path the installer registers (dotfiles #28)", async () => {
  // The installer pointed Claude's settings at
  // ~/.claude/hooks/coordination-mailbox-sweep.sh while files.nix never
  // installed it, so the hook ENOENT'd after a wipe and Claude alone kept
  // sweeping the legacy swarm_bus tier.
  const filesNix = await readFile("home/modules/files.nix", "utf8");
  const installer = await readFile("config/agent-hooks/install-swarm-hooks.mjs", "utf8");
  const registered = new Set(
    [...installer.matchAll(/\/home\/mhugo\/\.([\w.-]+)\/hooks\/([\w.-]+\.(?:sh|mjs))/g)]
      .map((match) => `.${match[1]}/hooks/${match[2]}`),
  );
  const missing = [...registered].filter((path) => !filesNix.includes(`"${path}"`));
  assert.deepEqual(missing, [], `installer registers hook paths that files.nix never installs: ${missing.join(", ")}`);
});

test("host-hook mirror no-ops on hash match and replaces on mismatch", async () => {
  const engine = await mkdtemp(join(tmpdir(), "host-hooks-src-"));
  const destHome = await mkdtemp(join(tmpdir(), "host-hooks-dst-"));
  try {
    await writeFile(join(engine, "AGENTS.md"), "# host-hooks\n");
    const body = "#!/bin/sh\necho canonical-hook\n";
    await writeFile(join(engine, "skills-gate-session-start.sh"), body);
    await chmod(join(engine, "skills-gate-session-start.sh"), 0o755);
    for (const name of [
      "coordination-mailbox-sweep.sh",
      "coordination-mailbox-sweep.mjs",
      "observations-autolog.sh",
      "observations-autolog.mjs",
      "skills-gate-pretooluse.sh",
      "skills-gate-mark-loaded.sh",
    ]) {
      await writeFile(join(engine, name), `placeholder ${name}\n`);
    }

    const run = () => spawnSync(process.execPath, [
      "config/agent-hooks/install-swarm-hooks.mjs",
      "--engine-host-hooks", engine,
      "--dotfiles-root", destHome,
      "--claude-settings", join(destHome, "claude.json"),
      "--kimi-config", join(destHome, "kimi.toml"),
    ], { encoding: "utf8" });

    assert.equal(run().status, 0, "first mirror must copy");
    const dest = join(destHome, ".dotfiles/config/claude/hooks/skills-gate-session-start.sh");
    const first = await stat(dest);
    await utimes(dest, first.atime, first.mtime);
    const frozen = await stat(dest);
    assert.equal(run().status, 0, "second mirror must no-op on hash match");
    const second = await stat(dest);
    assert.equal(
      second.mtimeMs,
      frozen.mtimeMs,
      "matching content hash must not rewrite the dest hook",
    );

    await writeFile(join(engine, "skills-gate-session-start.sh"), "#!/bin/sh\necho upgraded-hook\n");
    assert.equal(run().status, 0, "mismatch must replace");
    const upgraded = await readFile(dest, "utf8");
    assert.match(upgraded, /upgraded-hook/);
    const expected = createHash("sha256").update(await readFile(join(engine, "skills-gate-session-start.sh"))).digest("hex");
    const lock = JSON.parse(await readFile("config/agent-hooks/hooks.lock.json", "utf8"));
    assert.equal(
      lock.hooks["skills-gate-session-start.sh"].uri,
      "skill://purpose_tool/host-hooks/skills-gate-session-start.sh",
    );
    const sourceHash = createHash("sha256")
      .update(await readFile("config/claude/hooks/skills-gate-session-start.sh"))
      .digest("hex");
    assert.equal(lock.hooks["skills-gate-session-start.sh"].sha256, sourceHash);
    assert.equal(expected.length, 64);
  } finally {
    await rm(engine, { recursive: true, force: true });
    await rm(destHome, { recursive: true, force: true });
  }
});
