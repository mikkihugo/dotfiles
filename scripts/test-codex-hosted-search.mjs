import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const readConfig = async (path) => readFile(path, "utf8");
const disabled = /^web_search\s*=\s*"disabled"\s*$/m;
const live = /^web_search\s*=\s*"live"\s*$/m;
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

test("root enables live hosted search while every gateway-backed Codex role disables it", async () => {
  const seed = await readConfig("config/codex/config.toml");
  const shared = await readConfig("config/codex/shared-preferences.toml");
  const activation = await readConfig("home/modules/activation.nix");
  const roleNames = (await readdir("config/codex/agents"))
    .filter((name) => name.endsWith(".toml"))
    .sort();

  assert.match(seed, live);
  assert.match(shared, live);
  for (const roleName of roleNames) {
    const role = await readConfig(`config/codex/agents/${roleName}`);
    if (/^model_provider\s*=\s*"llm-gateway"\s*$/m.test(role)) {
      assert.match(
        role,
        disabled,
        `${roleName} must explicitly disable hosted web search`,
      );
    }
  }
  assert.match(
    seed,
    /\[mcp_servers\.centralcloud-mcp-gateway\][\s\S]*?^required\s*=\s*true\s*$/m,
  );
  assert.match(activation, /cp "\$\{\.\.\/\.\.\/config\/codex\/config\.toml\}"/);
  assert.match(
    activation,
    /--source "\$\{\.\.\/\.\.\/config\/codex\/shared-preferences\.toml\}"/,
  );
});

test("Codex keeps external gateway profiles profile-only and residents OpenAI-only", async () => {
  const seed = await readConfig("config/codex/config.toml");
  const shared = await readConfig("config/codex/shared-preferences.toml");
  const managedFiles = await readConfig("home/modules/files.nix");
  const activation = await readConfig("home/modules/activation.nix");
  const expectedResidentFiles = [
    "default.toml",
    "singularity-engine-harvester.toml",
    "taxonomy-validator.toml",
    "taxonomy-worker.toml",
  ];
  const expectedResidentConfigs = expectedResidentFiles
    .map((file) => `agents/${file}`)
    .sort();
  const expectedProfiles = [
    "external-explorer.config.toml",
    "external-reasoner.config.toml",
    "external-reviewer.config.toml",
    "external-verifier.config.toml",
    "external-worker.config.toml",
  ];
  const registeredFiles = [...seed.matchAll(
    /^\[agents\.[^\]]+\][\s\S]*?^config_file\s*=\s*"([^"]+)"$/gm,
  )]
    .map(([, file]) => file)
    .sort();

  assert.match(seed, /^model\s*=\s*"gpt-5\.6-sol"$/m);
  assert.match(seed, /^model_provider\s*=\s*"openai"$/m);
  assert.match(shared, /^model\s*=\s*"gpt-5\.6-sol"$/m);
  assert.match(shared, /^model_provider\s*=\s*"openai"$/m);
  assert.deepEqual(registeredFiles, expectedResidentConfigs);

  const residentSourceFiles = (await readdir("config/codex/agents"))
    .filter((name) => name.endsWith(".toml"))
    .sort();
  assert.deepEqual(residentSourceFiles, expectedResidentFiles);

  const managedResidentLinks = [...managedFiles.matchAll(
    /"\.codex\/agents\/([^\"]+)"\s*=\s*\{[\s\S]*?source\s*=\s*([^;]+);/g,
  )]
    .map(([, target, source]) => `${target}:${source.trim()}`)
    .sort();
  const expectedResidentLinks = expectedResidentFiles
    .map((file) => `${file}:../../config/codex/agents/${file}`)
    .sort();
  assert.deepEqual(managedResidentLinks, expectedResidentLinks);

  for (const residentFile of expectedResidentFiles) {
    const resident = await readConfig(`config/codex/agents/${residentFile}`);
    assert.match(resident, /^model_provider\s*=\s*"openai"$/m, `${residentFile} must remain OpenAI-resident`);
  }

  for (const profileName of expectedProfiles) {
    const profilePath = `config/codex/external-profiles/${profileName}`;
    const profile = await readConfig(profilePath);
    assert.match(profile, /^model_provider\s*=\s*"llm-gateway"$/m, `${profileName} must target llm-gateway`);
    assert.match(profile, disabled, `${profileName} must disable hosted web search`);
    assert.match(
      managedFiles,
      new RegExp(`"\\.codex/${escapeRegExp(profileName)}"\\s*=\\s*\\{[\\s\\S]*?source\\s*=\\s*\\.\\.\\/\\.\\.\\/config\\/codex\\/external-profiles\\/${escapeRegExp(profileName)};`),
      `${profileName} must be Home Manager-provisioned as a profile-only config`,
    );
    if (profileName === "external-reviewer.config.toml") {
      assert.match(profile, /^model_reasoning_effort\s*=\s*"high"$/m);
    } else {
      assert.doesNotMatch(
        profile,
        /^model_reasoning_effort\s*=/m,
        `${profileName} must not guess a named reasoning effort absent catalog support`,
      );
    }
  }

  assert.match(activation, /for role in coder worker coder-fast coder-smart test-writer debugger reviewer verifier web-researcher explorer/);
});
