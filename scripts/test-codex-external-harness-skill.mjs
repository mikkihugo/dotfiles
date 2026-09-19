import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import test from "node:test";

const read = (path) => readFile(path, "utf8");
const absent = async (path) => {
  await assert.rejects(() => access(path, fsConstants.F_OK), { code: "ENOENT" });
};

test("Purpose Tool alone owns the external-harness-orchestration skill source and projection", async () => {
  await absent("config/codex/skills/external-harness-orchestration/SKILL.md");
  await absent("config/codex/skills/external-harness-orchestration/agents/openai.yaml");
  const files = await read("home/modules/files.nix");
  assert.doesNotMatch(files, /"\.codex\/skills\/external-harness-orchestration"\s*=/);
  assert.doesNotMatch(files, /source\s*=\s*\.\.\/\.\.\/config\/codex\/skills\/external-harness-orchestration/);
  assert.match(files, /Agent skills are installed from the Engine-owned Purpose Tool/);
});

test("Codex root orchestrates through the canonical skill and explicit profiles", async () => {
  const agents = await read("config/codex/AGENTS.md");
  const handwritten = agents.split("<!-- BEGIN purpose-tool skills")[0];
  assert.match(handwritten, /Codex root orchestrates external workers/);
  assert.match(handwritten, /external-harness-orchestration/);
  assert.match(handwritten, /codex --profile external-worker/);
  assert.match(handwritten, /codex exec --ephemeral --profile external-worker "inspect this codebase"/);
  assert.doesNotMatch(handwritten, /kimi --model kimi-code\/k3 --output-format stream-json --prompt/);
  assert.match(handwritten, /coordinator must perform and verify it/);
});

test("Home Manager retains all five explicit role profiles and the Codex-only provenance launcher", async () => {
  const files = await read("home/modules/files.nix");
  for (const role of ["explorer", "worker", "reasoner", "reviewer", "verifier"]) {
    const name = `external-${role}.config.toml`;
    await access(`config/codex/external-profiles/${name}`, fsConstants.R_OK);
    assert.match(files, new RegExp(`"\\.codex/${name}"\\s*=\\s*\\{`));
  }
  assert.match(files, /"\.codex\/bin\/codex-external-run"\s*=\s*\{/);
  assert.match(files, /replaceVars\s+\.\.\/\.\.\/config\/codex\/bin\/codex-external-run\.mjs/);
  assert.doesNotMatch(files, /"\.agents\/bin\/codex-external-run"\s*=/);
  const verifier = await read("config/codex/external-profiles/external-verifier.config.toml");
  assert.match(verifier, /^model_reasoning_effort\s*=\s*"none"$/m);
  assert.doesNotMatch(verifier, /^model_reasoning_effort\s*=\s*"low"$/m);
});

test("old general orchestration runbooks remain absent", async () => {
  await absent("config/codex/runbooks/codex-external-harness-orchestration.md");
  await absent("docs/runbooks/codex-external-harness-orchestration.md");
});
