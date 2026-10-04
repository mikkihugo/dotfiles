import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const config = readFileSync(`${root}/config/opencode/opencode.json`, "utf8");
const aiTools = readFileSync(`${root}/home/modules/ai-tools.nix`, "utf8");
const secrets = readFileSync(`${root}/secrets/api-keys.yaml`, "utf8");

test("OpenCode Exa auth is runtime-injected from SOPS", () => {
  assert.match(config, /exaApiKey=\{env:EXA_API_KEY\}/);
  assert.doesNotMatch(config, /exaApiKey=[0-9a-f-]{20,}/i);
  assert.match(aiTools, /exa_api_key\s*=\s*\{/);
  assert.match(aiTools, /key\s*=\s*"exa\/api_key"/);
  assert.match(aiTools, /export EXA_API_KEY=/);
  assert.match(secrets, /^exa:\s*$/m);
  assert.match(secrets, /api_key:\s*ENC\[/);
});
