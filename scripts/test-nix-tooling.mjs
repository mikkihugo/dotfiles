import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import test from "node:test";

const contractRoot = resolve(process.env.DOTFILES_CONTRACT_ROOT ?? ".");
const source = async (path) => readFile(join(contractRoot, path), "utf8");

const listBody = (text, pattern, label) => {
  const match = text.match(pattern);
  assert.ok(match, `${label} list was not found`);
  return match[1];
};

const packageEntry = (name) => new RegExp(
  `^\\s*${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:\\s|#|$)`,
  "m",
);

test("Home Manager preserves the requested Forgejo and fast-Nix toolchain without tea", async () => {
  const packages = await source("home/modules/packages.nix");
  const entries = listBody(
    packages,
    /home\.packages\s*=\s*with pkgs;\s*\[([\s\S]*?)\n\s*\];/,
    "home.packages",
  );

  for (const name of [
    "forgejo-cli",
    "nix-fast-build",
    "nh",
    "comma",
    "nix-diff",
    "nix-du",
    "nurl",
    "nix-index",
  ]) {
    assert.match(entries, packageEntry(name), `missing home package ${name}`);
  }

  assert.doesNotMatch(packages, /\bteaLatest\b/);
  assert.doesNotMatch(packages, /gitea\.com\/gitea\/tea\/releases/);
  assert.doesNotMatch(entries, /^\s*tea(?:\s|#|$)/m);
});

test("Home Manager owns nix-index database refresh wiring", async () => {
  const home = await source("home/home.nix");
  assert.match(home, /\.\/modules\/nix-index\.nix/);

  const nixIndex = await source("home/modules/nix-index.nix");
  assert.match(nixIndex, /NH_HOME_FLAKE\s*=\s*"\$HOME\/\.dotfiles"/);
  assert.match(nixIndex, /systemd\.user\.services\.nix-index-update/);
  assert.match(nixIndex, /systemd\.user\.timers\.nix-index-update/);
  assert.match(nixIndex, /OnCalendar\s*=\s*"weekly"/);
  assert.match(nixIndex, /Persistent\s*=\s*true/);

  const dotfilesTimer = await source("home/modules/dotfiles-auto-update.nix");
  assert.match(dotfilesTimer, /OnCalendar\s*=\s*"hourly"/);
  assert.match(dotfilesTimer, /RandomizedDelaySec\s*=\s*"5min"/);
  assert.doesNotMatch(dotfilesTimer, /OnBootSec|OnUnitActiveSec/);
  assert.doesNotMatch(dotfilesTimer, /network-online\.target/);
});

test("shell aliases consume the managed Nix tooling", async () => {
  const shell = await source("home/modules/shell.nix");
  assert.match(shell, /hms\s*=\s*"nh home switch --ask"/);
  assert.match(shell, /nixwhy\s*=\s*"nix-diff /);
  assert.match(shell, /nixdu\s*=\s*"nix-du /);
});

test("the maintenance shell supplies every executable used by the canonical check", async () => {
  const flake = await source("flake.nix");
  const entries = listBody(
    flake,
    /devShells\.default\s*=\s*maintenance-pkgs\.mkShell\s*\{[\s\S]*?packages\s*=\s*with maintenance-pkgs;\s*\[([\s\S]*?)\n\s*\];/,
    "maintenance devShell packages",
  );

  for (const name of ["nodejs", "python3", "nix-fast-build"]) {
    assert.match(entries, packageEntry(name), `maintenance shell is missing ${name}`);
  }
});

test("just check delegates to the single repository check implementation", async () => {
  const justfile = await source("justfile");
  assert.match(justfile, /(?:^|\n)check:\n\s+bash scripts\/repo-check\.sh(?:\n|$)/);

  const check = await source("scripts/repo-check.sh");
  for (const expected of [
    "scripts/test-repo-vcs.sh",
    "scripts/test-codex-preferences.py",
    "scripts/test-codex-hosted-search.mjs",
    "scripts/test-swarm-messages.mjs",
    "scripts/test-swarm-hook-config.mjs",
    "scripts/test-nix-tooling.mjs",
  ]) {
    assert.match(check, new RegExp(expected.replaceAll(".", "\\.")), `repo check omits ${expected}`);
  }
  assert.match(check, /profile="\$\("\$root\/scripts\/current-home-profile"\)"/);
  assert.doesNotMatch(check, /homeConfigurations\.cc-se-sto-devbox-01/);
  assert.match(
    check,
    /nix-fast-build\s+--flake\s+"path:\$root#homeConfigurations\.\$\{profile\}\.activationPackage"\s+--no-link/,
  );
});
