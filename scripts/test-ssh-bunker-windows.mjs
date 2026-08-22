import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const sshConfig = readFileSync(
  fileURLToPath(new URL("../config/ssh_config", import.meta.url)),
  "utf8",
);

function hostBlock(host) {
  const blocks = sshConfig.split(/^Host /m).slice(1);
  const block = blocks.find((part) =>
    part.split("\n", 1)[0].split(/\s+/).includes(host),
  );
  assert.ok(block, `missing Host ${host}`);
  return `Host ${block}`;
}

test("mikki-bunker-windows uses the verified Tailscale admin route", () => {
  const block = hostBlock("mikki-bunker-windows");
  assert.match(block, /^\s*HostName 100\.64\.0\.5$/m);
  assert.match(block, /^\s*User admin$/m);
  assert.match(block, /^\s*IdentityFile ~\/\.ssh\/personal_admin_id_ed25519$/m);
  assert.match(
    block,
    /^\s*ProxyCommand tailscale --socket=\/run\/tailscale\/ts\.sock nc %h %p$/m,
  );
  assert.doesNotMatch(block, /^\s*User mikki$/m);
  assert.doesNotMatch(block, /^\s*User mhugo$/m);
  assert.doesNotMatch(block, /^\s*IdentityFile ~\/\.ssh\/id_ed25519$/m);
});
