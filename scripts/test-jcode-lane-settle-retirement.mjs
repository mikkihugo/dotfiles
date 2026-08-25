import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const activationPath = new URL("../home/modules/activation.nix", import.meta.url);

function retirementHook(source) {
  const match = source.match(
    /retireUnsafeJcodeLaneSettle\s*=\s*lib\.hm\.dag\.entryBefore\s+\["reloadSystemd"\]\s+''([\s\S]*?)'';/,
  );
  assert.ok(match, "activation must retire the unsafe legacy JCode lane-settle timer");
  return match[1];
}

test("Home Manager retires only the unsafe JCode lane-settle artifacts", () => {
  const source = readFileSync(activationPath, "utf8");
  const hook = retirementHook(source);

  assert.match(
    hook,
    /systemctl --user show --property=LoadState --value jcode-lane-settle\.timer/,
  );

  assert.match(
    hook,
    /systemctl --user show --property=LoadState --value jcode-lane-settle\.service/,
    "retirement must stop an already-running legacy service",
  );
  assert.doesNotMatch(hook, /jcode-lane-settle\.(?:timer|service).*\|\| true/);

  const exactTargets = [
    "$HOME/.config/systemd/user/jcode-lane-settle.timer",
    "$HOME/.config/systemd/user/jcode-lane-settle.service",
    "$HOME/.local/bin/jcode-lane-settle.sh",
  ];
  const rm = hook.match(
    /\$\{pkgs\.coreutils\}\/bin\/rm -f\s+\\\s*\n((?:\s*"\$HOME\/[^"\n]+"\s*\\?\s*\n?)+)/,
  );
  assert.ok(rm, "retirement hook must use one explicit rm -f target list");
  const rmTargets = [...rm[1].matchAll(/"([^"\n]+)"/g)].map((match) => match[1]);
  assert.deepEqual(rmTargets, exactTargets, "retirement must remove only the three exact legacy paths");
  assert.equal(
    [...hook.matchAll(/\$\{pkgs\.coreutils\}\/bin\/rm\s+-f/g)].length,
    1,
    "retirement must have exactly one rm -f invocation",
  );

  const disablePosition = hook.indexOf("systemctl --user disable --now jcode-lane-settle.timer");
  const stopPosition = hook.indexOf("systemctl --user stop jcode-lane-settle.service");
  const rmPosition = hook.indexOf("${pkgs.coreutils}/bin/rm -f");
  assert.ok(disablePosition < stopPosition, "service stop must follow timer disable");
  assert.ok(stopPosition < rmPosition, "service stop must precede unit-file removal");

  assert.doesNotMatch(
    hook,
    /workspace-(?:recover|close|release|abandon)/,
    "retirement must not mutate an Engine workspace or lease",
  );

  assert.ok(
    source.indexOf("retireUnsafeJcodeLaneSettle") < source.indexOf("resetFailedUserUnits"),
    "the retirement hook must run before the reloadSystemd-bound reset hook",
  );
  assert.ok(repoRoot.endsWith("/"), "test resolves repository-relative paths");
});
