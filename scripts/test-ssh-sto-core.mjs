import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const sshConfig = readFileSync(
  fileURLToPath(new URL("../config/ssh_config", import.meta.url)),
  "utf8",
);

test("ssh_config declares cc-se-sto-core-01 so fleet loops can reach it", () => {
  assert.match(
    sshConfig,
    /^Host .*cc-se-sto-core-01(?:\.centralcloud\.com)?\b/m,
  );
  // The ssh config names the inventory host (2026-11-06, 25bbb6f3): the
  // .net and .com aliases are not separate Host entries.
  assert.match(sshConfig, /^Host cc-se-sto-core-01$/m);
  assert.match(sshConfig, /HostName 207\.2\.123\.59/);
});
