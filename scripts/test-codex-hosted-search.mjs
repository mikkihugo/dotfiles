import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const readConfig = async (path) => readFile(path, "utf8");
const disabled = /^web_search\s*=\s*"disabled"\s*$/m;

test("root and every gateway-backed Codex role disable hosted search", async () => {
  const seed = await readConfig("config/codex/config.toml");
  const shared = await readConfig("config/codex/shared-preferences.toml");
  const activation = await readConfig("home/modules/activation.nix");
  const roleNames = (await readdir("config/codex/agents"))
    .filter((name) => name.endsWith(".toml"))
    .sort();

  assert.match(seed, disabled);
  assert.match(shared, disabled);
  for (const roleName of roleNames) {
    const role = await readConfig("config/codex/agents/" + roleName);
    if (/^model_provider\s*=\s*"llm-gateway"\s*$/m.test(role)) {
      assert.match(role, disabled, roleName + " must explicitly disable hosted web search");
    }
  }
  assert.match(seed, /\[mcp_servers\.ccgw\][\s\S]*?^required\s*=\s*true\s*$/m);
  assert.match(activation, /cp "\$\{\.\.\/\.\.\/config\/codex\/config\.toml\}"/);
  assert.match(
    activation,
    /--source "\$\{\.\.\/\.\.\/config\/codex\/shared-preferences\.toml\}"/,
  );
});

test("Codex exposes no alternate gateway profiles and keeps residents OpenAI-only", async () => {
  const seed = await readConfig("config/codex/config.toml");
  const shared = await readConfig("config/codex/shared-preferences.toml");
  const instructions = await readConfig("config/codex/AGENTS.md");
  const managedFiles = await readConfig("home/modules/files.nix");
  const activation = await readConfig("home/modules/activation.nix");
  const expectedResidentFiles = [
    "default.toml",
    "implementer.toml",
    "reviewer.toml",
    "scout.toml",
    "singularity-engine-harvester.toml",
    "taxonomy-validator.toml",
    "taxonomy-worker.toml",
  ];
  const expectedResidentConfigs = expectedResidentFiles
    .map((file) => "agents/" + file)
    .sort();
  const registeredFiles = [...seed.matchAll(
    /^\[agents\.[^\]]+\][\s\S]*?^config_file\s*=\s*"([^"]+)"$/gm,
  )]
    .map(([, file]) => file)
    .sort();

  assert.match(seed, /^model\s*=\s*"gpt-reserve"$/m);
  assert.match(seed, /^model_provider\s*=\s*"openai"$/m);
  assert.match(
    seed,
    /\[model_providers\.llm-gateway\][\s\S]*?^wire_api\s*=\s*"responses"$/m,
    "the dormant gateway provider declaration remains explicit",
  );
  assert.match(shared, /^model\s*=\s*"gpt-reserve"$/m);
  assert.match(shared, /^model_provider\s*=\s*"openai"$/m);
  assert.deepEqual(registeredFiles, expectedResidentConfigs);

  const residentSourceFiles = (await readdir("config/codex/agents"))
    .filter((name) => name.endsWith(".toml"))
    .sort();
  assert.deepEqual(residentSourceFiles, expectedResidentFiles);

  const managedResidentLinks = [...managedFiles.matchAll(
    /"\.codex\/agents\/([^\"]+)"\s*=\s*\{[\s\S]*?source\s*=\s*([^;]+);/g,
  )]
    .map(([, target, source]) => target + ":" + source.trim())
    .sort();
  const expectedResidentLinks = expectedResidentFiles
    .map((file) => file + ":../../config/codex/agents/" + file)
    .sort();
  assert.deepEqual(managedResidentLinks, expectedResidentLinks);

  for (const residentFile of expectedResidentFiles) {
    const resident = await readConfig("config/codex/agents/" + residentFile);
    assert.match(
      resident,
      /^model_provider\s*=\s*"openai"$/m,
      residentFile + " must remain OpenAI-resident",
    );
  }

  const externalProfiles = await readdir("config/codex/external-profiles").catch((error) => {
    if (error.code === "ENOENT") return [];
    throw error;
  });
  assert.deepEqual(externalProfiles, [], "alternate Codex profile sources must be removed");
  assert.doesNotMatch(
    managedFiles,
    /\.codex\/external-(explorer|reasoner|reviewer|verifier|worker)\.config\.toml/,
    "Home Manager must not provision alternate Codex profiles",
  );
  assert.doesNotMatch(
    instructions,
    /external-(explorer|reasoner|reviewer|verifier|worker)/,
    "Codex instructions must not advertise removed profiles",
  );
  assert.match(managedFiles, /"\.codex\/bin\/codex-external-run"\s*=\s*\{/);

  assert.match(
    activation,
    /agents_dir="\$HOME\/\.codex\/agents"/,
    "activation must inspect the whole auto-loaded agent directory rather than only historical role names",
  );
  assert.match(
    activation,
    /for target in "\$agents_dir"\/\*\.toml/,
    "activation must inspect every standalone custom agent TOML",
  );
  assert.match(
    activation,
    /if \[ -L "\$target" \]; then[\s\S]*?rm -f "\$target"/,
    "activation must retire stale managed resident-role symlinks",
  );
  assert.match(
    activation,
    /gnugrep[\s\S]*?model_provider[\s\S]*?llm-gateway/,
    "activation must detect a stale plain gateway agent file",
  );
  assert.match(
    activation,
    /\['\\"]llm-gateway\['\\"]/,
    "activation must recognize both legal TOML string delimiters for llm-gateway",
  );
  assert.match(
    activation,
    /retired-agent-roles/,
    "activation must quarantine stale plain gateway role files because ~/.codex/agents is auto-loaded",
  );
  assert.match(
    activation,
    /backup="\$\(mktemp "\$retired_dir\/gateway-agent\.XXXXXX"\)"[\s\S]*?mv "\$target" "\$backup"/,
    "activation must use the mktemp reservation itself as the quarantine target",
  );
  assert.doesNotMatch(activation, /"\$backup\.toml"/);
});
