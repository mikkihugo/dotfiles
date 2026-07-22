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
    "nixd",
    "alejandra",
    "statix",
    "deadnix",
    "nix-tree",
    "nix-output-monitor",
    "nix-fast-build",
    "nh",
    "comma",
    "nix-diff",
    "nix-du",
    "nurl",
    "nix-index",
    "psmisc",
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

test("Home Manager activation does not launch emergency backup jobs", async () => {
  const backup = await source("home/modules/home-emergency-backup.nix");
  assert.match(backup, /X-SwitchMethod\s*=\s*"keep-old"/);
});

test("Home Manager gives every managed agent client a deterministic UTF-8 locale", async () => {
  const home = await source("home/home.nix");
  const localeEnvironment = listBody(
    home,
    /localeEnvironment\s*=\s*\{([\s\S]*?)\n\s*\};/,
    "localeEnvironment",
  );

  assert.match(localeEnvironment, /^\s*LANG\s*=\s*"C\.UTF-8";/m);
  assert.match(localeEnvironment, /^\s*LC_ALL\s*=\s*"C\.UTF-8";/m);
  assert.match(home, /sessionVariables\s*=\s*localeEnvironment\s*\/\/\s*\{/);
  assert.match(home, /systemd\.user\.sessionVariables\s*=\s*localeEnvironment;/);
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

  assert.doesNotMatch(
    entries,
    packageEntry("mise"),
    "mise is Home Manager-owned and must not trigger a maintenance-shell build",
  );
});

test("Home Manager does not include the retired Hermes agent", async () => {
  const flake = await source("flake.nix");
  const home = await source("home/home.nix");

  assert.doesNotMatch(flake, /\bhermes-agent\b/);
  assert.doesNotMatch(home, /hermes-(?:proxy|tui)\.nix/);
});

test("Home Manager uses the nixpkgs mise package without a private overlay", async () => {
  const flake = await source("flake.nix");
  const home = await source("home/home.nix");
  const packages = await source("home/modules/packages.nix");
  const bootstrap = await source("bootstrap/steps/20-home-manager.sh");
  const updater = await source("home/modules/mise-auto-update.nix");

  assert.doesNotMatch(flake, /overlays\/mise\.nix/);
  assert.match(home, /programs\.mise\s*=\s*\{/);
  assert.match(home, /package\s*=\s*pkgs\.mise;/);
  assert.doesNotMatch(packages, /^\s*mise(?:\s|#|$)/m);
  assert.match(flake, /packages\.home-manager\s*=\s*home-manager\.packages\.\$\{sys\}\.home-manager;/);
  assert.match(bootstrap, /"path:\$ROOT_DIR#home-manager" -- switch/);
  assert.doesNotMatch(bootstrap, /home-manager\/master|nix profile install/);
  assert.match(updater, /"\$mise_bin" install --yes/);
  assert.match(updater, /"\$mise_bin" upgrade --yes/);
  assert.doesNotMatch(updater, /nix develop|just mise-upgrade/);
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
    /nix\s+build\s+--no-link\s+"path:\$root#homeConfigurations\.\$\{profile\}\.activationPackage"/,
  );
  assert.doesNotMatch(check, /nix-fast-build\s+--flake/);
});

test("global Codex instructions keep publication owned until land completes", async () => {
  const agents = await source("config/codex/AGENTS.md");
  assert.match(agents, /Do not launch delegated commit, land, push, or publication work as a background process/);
  assert.match(agents, /complete synchronously within the subagent turn/);
  assert.match(agents, /coordinator must perform and verify it/);
});
