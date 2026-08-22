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
  assert.match(
    sshConfig,
    /^Host cc-se-sto-core-01 cc-se-sto-core-01\.centralcloud\.com$/m,
  );
  assert.match(sshConfig, /HostName 207\.2\.123\.59/);
});
