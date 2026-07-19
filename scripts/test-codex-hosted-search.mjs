import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";

const readConfig = async (path) => readFile(path, "utf8");
const disabled = /^web_search\s*=\s*"disabled"\s*$/m;

test("root and every gateway-backed Codex role disable hosted web search but retain MCP search", async () => {
  const seed = await readConfig("config/codex/config.toml");
  const shared = await readConfig("config/codex/shared-preferences.toml");
  const activation = await readConfig("home/modules/activation.nix");
  const roleNames = (await readdir("config/codex/agents"))
    .filter((name) => name.endsWith(".toml"))
    .sort();

  assert.match(seed, disabled);
  assert.match(shared, disabled);
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
