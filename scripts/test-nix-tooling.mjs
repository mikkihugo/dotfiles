import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
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

  const gitBackup = await source("home/modules/git-auto-backup.nix");
  assert.match(gitBackup, /X-SwitchMethod\s*=\s*"keep-old"/);
});

test("mutable home sweeps serialize and report bounded lock failures", async () => {
  const gitBackup = await source("home/modules/git-auto-backup.nix");
  const emergencyBackup = await source("home/modules/home-emergency-backup.nix");
  for (const module of [gitBackup, emergencyBackup]) {
    assert.match(module, /home-mutable-workspace-sweep\.lock/);
    assert.match(module, /flock --exclusive --wait/);
    assert.match(module, /mutable sweep lock unavailable/);
  }
  assert.match(gitBackup, /timeout --kill-after=10s 45m/);
  assert.match(gitBackup, /TimeoutStartSec\s*=\s*"7h"/);
});

test("borgmatic hot-source backup replaces mutating git snapshots safely", async () => {
  const backup = await source("home/modules/home-emergency-backup.nix");
  const home = await source("home/home.nix");

  assert.match(home, /\.\/modules\/home-emergency-backup\.nix/);
  assert.doesNotMatch(
    home,
    /\.\/modules\/git-auto-backup\.nix/,
    "legacy mutating git snapshots must be retired when Borgmatic is enabled",
  );
  for (const root of [".dotfiles", ".dotfiles-worktrees", "code", "workspaces", "backups"]) {
    assert.match(backup, new RegExp(`\\$\\{homeDir\\}\\/${root.replaceAll(".", "\\.")}`));
  }
  assert.match(backup, /"\/srv\/infra"/);
  assert.match(backup, /hot-source-hel1/);
  assert.match(backup, /hot-source-fsn1/);
  assert.match(backup, /OnCalendar\s*=\s*"\*-\*-\* \*:00\/30:00"/);
  assert.match(backup, /OnCalendar\s*=\s*"\*-\*-\* \*:15\/30:00"/);
  assert.match(backup, /RandomizedDelaySec\s*=\s*"2min"/);
  assert.match(backup, /RuntimeMaxSec\s*=\s*"25min"/);
  assert.match(backup, /Nice\s*=\s*19/);
  assert.match(backup, /IOSchedulingClass\s*=\s*"idle"/);
  assert.match(backup, /lock="\$XDG_RUNTIME_DIR\/borgmatic-hot-source\.lock"/);
  assert.match(backup, /flock -n -E 75 "\$lock"/);
  assert.match(backup, /borgmatic[^\n]*create/);
  assert.match(backup, /repo-info[\s\S]*repo-create --encryption none/);
  assert.match(backup, /create prune compact/);
  assert.match(backup, /make_parent_directories\s*=\s*true/);
  assert.match(
    backup,
    /hot-source-(?:hel1|fsn1)[\s\S]*?Install\.WantedBy\s*=\s*\["timers\.target"\]/,
    "hot-source timers must activate through timers.target",
  );
  assert.doesNotMatch(backup, /GIT_INDEX_FILE|git\s+add|update-ref|refs\/backup/);
  for (const excluded of ["**/target", "**/node_modules", "**/.direnv", "**/.cache"]) {
    assert.match(backup, new RegExp(excluded.replaceAll("*", "\\*").replaceAll("/", "\\/")));
  }
});

test("git auto-backup yields host resources and waits after completion", async () => {
  const backup = await source("home/modules/git-auto-backup.nix");
  const backupService = backup.slice(
    backup.indexOf("services.git-auto-backup"),
    backup.indexOf("timers.git-auto-backup"),
  );

  assert.match(backup, /jobs=2/);
  assert.match(backupService, /Nice\s*=\s*19/);
  assert.match(backupService, /IOSchedulingClass\s*=\s*"idle"/);
  assert.match(backupService, /CPUWeight\s*=\s*10/);
  assert.match(backupService, /IOWeight\s*=\s*10/);
  assert.match(backupService, /MemoryHigh\s*=\s*"8G"/);
  assert.match(backupService, /MemoryMax\s*=\s*"12G"/);
  assert.match(backup, /OnActiveSec\s*=\s*"5m"/);
  assert.doesNotMatch(backup, /OnBootSec\s*=/);
  assert.match(backup, /OnUnitInactiveSec\s*=\s*"15m"/);
  assert.doesNotMatch(backup, /OnCalendar\s*=\s*"\*:0\/15"/);
  const hotPath = backup.slice(0, backup.indexOf("workspaceLedgerScript ="));
  assert.doesNotMatch(hotPath, /workspace-debt|workspace-ledger-snapshot|rsync -a/);
  const pushCommands = backup
    .split("\n")
    .filter((line) => /git_net .*\spush\s/.test(line));
  assert.equal(pushCommands.length, 9, "enumerate every backup network push path");
  for (const command of pushCommands) assert.match(command, /--no-verify/);
  for (const command of pushCommands) {
    assert.match(command, /\$(?:snapshot_ref|ref|backup_ref)|\\$/);
  }
  assert.match(backup, /ref="refs\/backup\/\$host\/\$slug\/\$branch\/wip"/);
  assert.match(backup, /snapshot_ref="refs\/backup\/\$host\/\$slug\/\$branch\/wip-\$stamp"/);
  assert.match(backup, /backup_ref="refs\/backup\/\$host\/\$slug\/\$branch\/head"/);
  assert.match(backup, /\$commit:refs\/backup\/\$host\/\$slug\/workspace-\$wsname\/wip/);
  assert.doesNotMatch(backup, /"HEAD:\$branch"/);
  assert.match(backup, /refs\/backup\/\$host\/\$slug\/\$branch\/head/);
});

test("workspace ledger preservation is a separate low-priority hourly service", async () => {
  const backup = await source("home/modules/git-auto-backup.nix");
  assert.match(backup, /services\.workspace-ledger-snapshot/);
  assert.match(backup, /timers\.workspace-ledger-snapshot/);
  const ledgerService = backup.slice(
    backup.indexOf("services.workspace-ledger-snapshot"),
    backup.indexOf("timers.workspace-ledger-snapshot"),
  );
  const ledgerTimer = backup.slice(backup.indexOf("timers.workspace-ledger-snapshot"));
  assert.match(ledgerTimer, /OnActiveSec\s*=\s*"10m"/);
  assert.match(ledgerTimer, /OnUnitInactiveSec\s*=\s*"1h"/);
  assert.doesNotMatch(ledgerTimer, /OnCalendar|Persistent/);
  assert.match(ledgerService, /ExecStart\s*=\s*"\$\{workspaceLedgerScript\}"/);
  assert.match(ledgerService, /Nice\s*=\s*19/);
  assert.match(ledgerService, /IOSchedulingClass\s*=\s*"idle"/);
  const ledgerScript = backup.slice(
    backup.indexOf("workspaceLedgerScript ="),
    backup.indexOf("in {"),
  );
  assert.match(ledgerScript, /rsync -a/);
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
  assert.match(home, /systemd\.user\.sessionVariables\s*=\s*localeEnvironment\s*\/\/\s*\{/);
  assert.match(
    home,
    /BASH_ENV\s*=\s*"\$HOME\/\.dotfiles\/shell\/bash\/noninteractive-path\.sh"/,
  );
});

test("NixOS owns the JCode units; Home Manager must not shadow them", async () => {
  const home = await source("home/home.nix");
  assert.match(home, /\.\/modules\/jcode-server\.nix/);

  const service = await source("home/modules/jcode-server.nix");
  assert.match(service, /lib\.toLower hostname == "cc-se-sto-devbox-01"/);

  // jcode-server and jcode-webtty are systemd *user* services declared by NixOS
  // in /srv/infra/.../swarm-runtime.nix. Home Manager writes
  // ~/.config/systemd/user, which takes precedence over /etc/systemd/user, so
  // redeclaring either name here silently shadows the system unit. That is how
  // jcode-webtty ended up piping jcode-tui straight into ttyd with no socket,
  // losing the 7681 bind to a hand-started webtty-manual.service and restarting
  // 38 times in 5 minutes (2026-08-08).
  assert.doesNotMatch(
    service,
    /systemd\.user\.services\.jcode-server\b/,
    "jcode-server is owned by NixOS; declaring it here shadows the system unit",
  );
  assert.doesNotMatch(
    service,
    /systemd\.user\.services\.jcode-webtty\b/,
    "jcode-webtty is owned by NixOS; declaring it here shadows the system unit",
  );

  // The jcode-tui launcher stays Home Manager's, and keeps its tmux persistence.
  assert.match(service, /name\s*=\s*"jcode-tui"/);
  assert.match(
    service,
    /runtimeDir="\/run\/user\/\$\(\$\{pkgs\.coreutils\}\/bin\/id -u\)"/,
  );
  assert.doesNotMatch(service, /runtimeDir="\/tmp/);
  assert.match(service, /tmuxSocket="\$runtimeDir\/jcode-ui\.tmux\.sock"/);
  assert.match(
    service,
    /tmux}\/bin\/tmux -S "\$tmuxSocket" new-session -A -s jcode-ui "\$\{jcodeLauncher\}\/bin\/jcode"/,
  );

  assert.doesNotMatch(
    service,
    /ExecStartPre|rm\s+-f.*jcode(?:-daemon\.lock|\.sock)/,
    "must not delete another daemon's live lock or socket",
  );
  assert.doesNotMatch(
    service,
    /ttyd[^"\n]*(?:0\.0\.0\.0|\[::\]|--credential|jcode connect)/,
    "WebTTY must remain loopback-only and credential-free behind SSH",
  );
});

test("JCode keeps one runtime with direct-preferred K3 and M3 plus explicit gateway fallbacks", async () => {
  const home = await source("home/home.nix");
  const service = await source("home/modules/jcode-server.nix");
  const aiTools = await source("home/modules/ai-tools.nix");
  const providers = await source("home/modules/jcode-providers.nix");
  const preferences = await source("config/jcode/shared-preferences.toml");
  const prompt = await source("config/jcode/swarm-prompt.md");

  assert.match(home, /\.\/modules\/jcode-providers\.nix/);

  assert.match(service, /jcodeLauncher\s*=\s*pkgs\.writeShellApplication/);
  assert.match(service, /name\s*=\s*"jcode"/);
  // jcodeLauncher must stay OUT of home.packages: it is a writeShellApplication
  // named "jcode", so listing it collides in pkgs.buildEnv with ai-tools.nix's
  // jcodeGatewayWrapper on non-swarm hosts. The swarm CLI launcher is jcode's
  // install_release wrapper; the watchdog reaches castle via store-path PATH.
  assert.match(service, /packages\s*=\s*\[jcodeTui\]/);
  assert.doesNotMatch(service, /packages\s*=\s*\[[^\]]*jcodeLauncher/);
  assert.doesNotMatch(service, /file\."\.local\/bin\/jcode"/);
  assert.match(service, /jcode-swarm-fleet-watchdog\.service\.d\/50-server-jcode/);
  assert.match(service, /jcode-swarm-fleet-watchdog\.timer\.d\/10-calendar/);
  assert.match(service, /OnCalendar=\*:0\/5/);
  assert.match(
    aiTools,
    /isSwarmDevbox\s*=\s*lib\.toLower hostname == "cc-se-sto-devbox-01"/,
  );
  assert.match(aiTools, /mkIf\s*\(!isSwarmDevbox\)/);
  assert.match(aiTools, /install_release/);
  assert.match(
    service,
    /unset[\s\S]*JCODE_PROVIDER_LLM_GATEWAY_API_KEY[\s\S]*KIMI_API_KEY/,
  );
  // The jcode-server ExecStart (and therefore its --model routing) moved to the
  // NixOS unit in /srv/infra/.../swarm-runtime.nix. Home Manager must not
  // redeclare it, or it shadows the system unit — see the anti-shadowing test
  // above. Only the launcher's provider hygiene is Home Manager's contract here.
  assert.doesNotMatch(service, /--provider-profile llm-gateway/);
  assert.match(
    service,
    /tmux}\/bin\/tmux -S "\$tmuxSocket" new-session -A -s jcode-ui "\$\{jcodeLauncher\}\/bin\/jcode"/,
  );
  assert.match(
    service,
    /paneStartCommand=.*pane_start_command[\s\S]*\$\{jcodeLauncher\}\/bin\/jcode[\s\S]*kill-session -t jcode-ui/,
  );
  assert.doesNotMatch(service, /JCODE_RUNTIME_DIR|runtime-allowlisted/);

  assert.match(
    providers,
    /kimi_api_key\s*=\s*\{[\s\S]*?key\s*=\s*"sf\/env\/KIMI_API_KEY";[\s\S]*?mode\s*=\s*"0600";/,
  );
  assert.match(providers, /config\.sops\.secrets\.kimi_api_key\.path/);
  assert.match(providers, /config\.sops\.secrets\.minimax_api_key\.path/);
  assert.match(providers, /config\.sops\.secrets\.llm_gateway_api_key\.path/);
  assert.match(providers, /kimi\.env/);
  assert.match(providers, /KIMI_API_KEY/);
  assert.match(providers, /minimax-direct\.env/);
  assert.match(providers, /MINIMAX_API_KEY/);
  assert.match(providers, /provider-llm-gateway\.env/);
  assert.match(providers, /JCODE_PROVIDER_LLM_GATEWAY_API_KEY/);
  assert.match(providers, /chmod 600/);
  assert.match(providers, /jcode-preferences/);
  assert.match(providers, /shared-preferences\.toml/);
  assert.match(providers, /swarm-prompt\.md/);
  assert.match(providers, /systemd\.user\.services\.jcode-provider-config/);
  assert.match(providers, /Requires\s*=\s*\["sops-nix\.service"\]/);
  assert.match(providers, /After\s*=\s*\["sops-nix\.service"\]/);
  assert.match(providers, /Before\s*=\s*\["jcode-server\.service"\]/);
  assert.doesNotMatch(providers, /home\.activation\.configureJcodeProviders/);
  // jcode-server itself is a NixOS unit now. Home Manager keeps the ordering
  // against its own jcode-provider-config through a systemd drop-in, which adds
  // the dependency without redefining (and therefore shadowing) the unit.
  assert.match(
    service,
    /jcode-server\.service\.d\/10-provider-config\.conf/,
  );
  assert.match(service, /Requires=jcode-provider-config\.service/);
  assert.match(service, /After=jcode-provider-config\.service/);
  assert.doesNotMatch(
    providers,
    /(?:KIMI_API_KEY|MINIMAX_API_KEY|JCODE_PROVIDER_LLM_GATEWAY_API_KEY)\s*=\s*"[A-Za-z0-9_-]{16,}"/,
  );

  // Assert MEMBERSHIP, not the literal array. Pinning the exact order broke the
  // moment a provider was added (ollama-cloud) and reordered (minimax-direct
  // first), which is a config decision this test has no opinion about. What it
  // must protect is that every provider the managed profiles depend on is
  // offered in the picker.
  for (const provider of ["llm-gateway", "kimi", "minimax-direct", "openai-oauth", "ollama-cloud"]) {
    assert.match(
      preferences,
      new RegExp(`model_picker_providers\\s*=\\s*\\[[^\\]]*"${provider}"`),
      `model_picker_providers must offer ${provider}`,
    );
  }
  assert.match(preferences, /cross_provider_failover\s*=\s*"(manual|countdown)"/);
  assert.match(preferences, /trusted_external_sources\s*=\s*\[\]/);
  assert.match(preferences, /trusted_external_source_paths\s*=\s*\[\]/);
  assert.match(preferences, /\[providers\.llm-gateway\]/);
  assert.match(preferences, /base_url\s*=\s*"https:\/\/llm-gateway\.centralcloud\.com\/v1"/);
  assert.match(preferences, /\[providers\.minimax-direct\]/);
  assert.match(preferences, /base_url\s*=\s*"https:\/\/api\.minimax\.io\/v1"/);
  assert.match(preferences, /api_key_env\s*=\s*"MINIMAX_API_KEY"/);
  assert.match(preferences, /default_model\s*=\s*"MiniMax-M3"/);
  assert.doesNotMatch(preferences, /api\.minimaxi\.com/);

  assert.match(prompt, /direct `kimi:k3`/);
  assert.match(prompt, /direct `minimax-direct:MiniMax-M3`/);
  assert.match(prompt, /`llm-gateway:kimi-for-coding\/k3`/);
  assert.match(prompt, /`llm-gateway:minimax-coding-plan\/MiniMax-M3`/);
  assert.doesNotMatch(prompt, /`llm-gateway:opencode-go\/kimi-k3`/);
  assert.doesNotMatch(prompt, /`llm-gateway:minimax\/MiniMax-M3`/);
  assert.doesNotMatch(prompt, /Never route (?:MiniMax M3|K3) through `llm-gateway`/);
});

test("shell aliases consume the managed Nix tooling", async () => {
  const shell = await source("home/modules/shell.nix");
  // Keep automation non-interactive (no --ask), and require an explicit
  // profile selection. Without -c, nh matches homeConfigurations on $USER and
  // picks the generic "mhugo" fallback, which is built with hostname = "" —
  // every host-gated module then evaluates false and activation silently
  // removes those services. current-home-profile is the same resolver the
  // .local/bin/home-manager wrapper uses.
  const hmsAlias = /^\s*hms\s*=\s*''nh home switch "\$HOME\/\.dotfiles" -c "\$\("\$HOME\/\.dotfiles\/scripts\/current-home-profile"\)"'';/m;
  assert.match(shell, hmsAlias);
  assert.doesNotMatch(shell, /hms\s*=\s*\S*nh home switch[^;]*--ask/);
  // hms must never activate without naming the configuration.
  const hmsLine = shell.match(/^\s*hms\s*=.*$/m)[0];
  assert.match(hmsLine, /-c /);
  assert.match(hmsLine, /current-home-profile/);
  assert.match(shell, /nixwhy\s*=\s*"nix-diff /);
  assert.match(shell, /nixdu\s*=\s*"nix-du /);
});

test("the Home Manager wrapper preserves an explicitly requested flake", async () => {
  const shell = await source("home/modules/shell.nix");
  const wrapper = listBody(
    shell,
    /"\.local\/bin\/home-manager"\s*=\s*\{[\s\S]*?text\s*=\s*''([\s\S]*?)\n\s*'';/,
    "home-manager wrapper",
  );

  assert.match(wrapper, /has_explicit_flake=0/);
  assert.match(wrapper, /--flake\|--flake=\*\|-f\|-f\?\*\)/);
  assert.match(
    wrapper,
    /if \[\[ "\$has_explicit_flake" -eq 0 \]\]; then[\s\S]*?set -- --flake "\$HOME\/\.dotfiles#\$\("\$HOME\/\.dotfiles\/scripts\/current-home-profile"\)" "\$@"/,
  );
  assert.match(
    wrapper,
    /exec "\$real_home_manager" switch[\s\S]*?--extra-experimental-features 'nix-command flakes'[\s\S]*?"\$@"/,
  );
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
  assert.match(packages, /^\s*gnumake\b/m);
  assert.match(packages, /^\s*pkg-config\b/m);
  assert.match(updater, /NIX_CFLAGS_COMPILE/);
  assert.match(updater, /NIX_LDFLAGS/);
  assert.match(updater, /-Wl,-rpath,/);
  assert.match(updater, /PKG_CONFIG_PATH/);
  assert.match(updater, /share\/pkgconfig/);
  assert.match(updater, /^\s*tcl\b/m);
  assert.doesNotMatch(updater, /nix develop|just mise-upgrade/);
});

test("Home Manager activation uses the non-deprecated nix profile command", async () => {
  const flake = await source("flake.nix");
  assert.match(flake, /activationPackage = home\.activationPackage\.overrideAttrs/);
  assert.match(flake, /substituteInPlace \$out\/activate/);
  assert.match(flake, /--replace-fail "profile install" "profile add"/);
  assert.match(flake, /nix-index = prev\.nix-index\.overrideAttrs/);
  assert.match(flake, /command-not-found\.sh/);
});

test("just check delegates to the single repository check implementation", async () => {
  const justfile = await source("justfile");
  assert.match(justfile, /(?:^|\n)check:\n\s+bash scripts\/repo-check\.sh(?:\n|$)/);

  const check = await source("scripts/repo-check.sh");
  for (const expected of [
    "scripts/test-repo-vcs.sh",
    "scripts/test-codex-preferences.py",
    "scripts/test-codex-hosted-search.mjs",
    "scripts/test-detect-secrets-work-packet-filter.mjs",
    "scripts/test-jcode-lane-settle-retirement.mjs",
    "scripts/test-codex-external-harness-skill.mjs",
    "scripts/test-codex-external-run.mjs",
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

test("otel-env.sh resolves OTLP helpers without mutating caller PATH", async () => {
  const otel = await source("shell/bash/otel-env.sh");
  assert.doesNotMatch(otel, /^\s*PATH=/m);
  assert.doesNotMatch(otel, /export\s+PATH/);
  assert.match(otel, /_cc_otel_resolve/);
  assert.match(otel, /\/run\/current-system\/sw\/bin/);
  assert.doesNotMatch(otel, /mise\/shims\/cursor-agent/);
});

test("cursor-agent and agent share one OTEL wrapper with unified binary resolution", async () => {
  const aiTools = await source("home/modules/ai-tools.nix");
  assert.match(aiTools, /cursorAgentEntrypoint\s*=/);
  assert.doesNotMatch(aiTools, /mise\/shims\/cursor-agent/);

  const cursorAgentFile = listBody(
    aiTools,
    /"\.local\/bin\/cursor-agent"\s*=\s*\{([\s\S]*?)\n\s*\};/,
    ".local/bin/cursor-agent",
  );
  const agentFile = listBody(
    aiTools,
    /"\.local\/bin\/agent"\s*=\s*\{([\s\S]*?)\n\s*\};/,
    ".local/bin/agent",
  );

  assert.match(cursorAgentFile, /text\s*=\s*cursorAgentEntrypoint;/);
  assert.match(agentFile, /text\s*=\s*cursorAgentEntrypoint;/);

  const entrypoint = listBody(
    aiTools,
    /cursorAgentEntrypoint\s*=\s*''([\s\S]*?)'';/,
    "cursorAgentEntrypoint",
  );
  assert.match(entrypoint, /otel-env\.sh/);
  assert.match(entrypoint, /OTEL_SERVICE_NAME="cursor-agent"/);
  assert.match(
    entrypoint,
    /versions[\s\S]*llm-pkgs\.cursor-agent[\s\S]*mise\/installs/,
    "binary policy must prefer versioned install, then Nix store, then mise install",
  );
  assert.match(entrypoint, /\.local\/bin\/(cursor-agent|agent)/);
});

test("Claude Code remains native-installer-owned outside Home Manager", async () => {
  const aiTools = await source("home/modules/ai-tools.nix");
  const flake = await source("flake.nix");
  assert.doesNotMatch(aiTools, /"\.local\/bin\/claude"/);
  assert.doesNotMatch(aiTools, /pkgs\.claude-code/);
  assert.doesNotMatch(flake, /claude-code/);
});

// Home Manager merges every module's home.file set into one attrset and every
// module's home.packages into one pkgs.buildEnv, so two modules claiming one
// path is an eval-time error that otherwise surfaces only during a full nix
// build. GAP 7: ai-tools.nix and jcode-server.nix both claimed
// ~/.local/bin/jcode and both listed a derivation named "jcode", producing a
// conflicting home.file definition and then a buildEnv "conflicting subpath".
// These scanners are deliberately textual so the next such pair fails in
// `just check` in milliseconds instead of during `land`.
//
// Known blind spots — a flagged duplicate needs triage, not an automatic bug
// verdict, and a clean run is not proof that no collision exists:
//   * computed keys (`${stableBashRel}` in stable-shell.nix) are
//     invisible to a quoted-key scan;
//   * generated attrsets (`xdg.configFile = lib.mapAttrs' …` in
//     home-emergency-backup.nix) are skipped whole;
//   * host gating (`lib.mkIf (lib.toLower hostname == …)` in jcode-server.nix)
//     is not modelled, so two modules may legitimately claim one path on
//     disjoint hosts;
//   * bin names of raw pkgs entries are not knowable without evaluating nix;
//     only the attr-name heuristic below approximates them.
// The sentinel assertions exist because a scanner whose regexes stopped
// matching reports zero duplicates exactly like a clean tree does.

const moduleSources = async () => {
  const dir = "home/modules";
  const names = (await readdir(join(contractRoot, dir)))
    .filter((name) => name.endsWith(".nix"))
    .sort();
  return Promise.all(
    names.map(async (name) => ({
      name,
      lines: (await source(join(dir, name))).split("\n"),
    })),
  );
};

// Quoted attr keys inside a `home.file = { … }` / `file = { … }` /
// `xdg.configFile = { … }` block at depth 0 of that block, plus the dotted
// single-key forms `home.file."…"`, `file."…"` and `xdg.configFile."…"`.
const collectFileKeys = (modules) => {
  const keys = new Map();
  const add = (key, where) => {
    if (!keys.has(key)) keys.set(key, []);
    keys.get(key).push(where);
  };
  for (const { name, lines } of modules) {
    let inBlock = false;
    let depth = 0;
    lines.forEach((line, index) => {
      const code = line.split("#")[0];
      const dotted = code.match(/(?:^|\s)(?:home\.)?(?:file|xdg\.configFile|configFile)\."([^"]+)"/);
      if (dotted) {
        add(dotted[1], `${name}:${index + 1}`);
        return;
      }
      if (!inBlock) {
        if (/^\s*(?:home\.file|file|xdg\.configFile|configFile)\s*=\s*\{/.test(code)) {
          inBlock = true;
          depth = 0;
        }
        return;
      }
      if (depth === 0) {
        const key = code.match(/^\s*"([^"]+)"\s*=/);
        if (key) add(key[1], `${name}:${index + 1}`);
      }
      depth += (code.match(/\{/g) ?? []).length - (code.match(/\}/g) ?? []).length;
      if (depth < 0) inBlock = false;
    });
  }
  return keys;
};

// `name = pkgs.writeShellScriptBin "bin"` and
// `name = pkgs.writeShellApplication { name = "bin"; … }`.
const collectWrappers = (modules) => {
  const wrappers = [];
  for (const { name, lines } of modules) {
    lines.forEach((line, index) => {
      const code = line.split("#")[0];
      const script = code.match(
        /^\s*([A-Za-z0-9_'-]+)\s*=\s*pkgs\.(?:writeShellScriptBin|writeScriptBin)\s+"([^"]+)"/,
      );
      if (script) {
        wrappers.push({ variable: script[1], bin: script[2], where: `${name}:${index + 1}` });
        return;
      }
      const application = code.match(
        /^\s*([A-Za-z0-9_'-]+)\s*=\s*pkgs\.writeShellApplication\s*\{/,
      );
      if (!application) return;
      for (let ahead = index + 1; ahead < Math.min(index + 6, lines.length); ahead += 1) {
        const bin = lines[ahead].match(/^\s*name\s*=\s*"([^"]+)"/);
        if (bin) {
          wrappers.push({ variable: application[1], bin: bin[1], where: `${name}:${index + 1}` });
          break;
        }
      }
    });
  }
  return wrappers;
};

// Tokens listed inside any `home.packages = [ … ]` / `packages = [ … ]`, with
// comments stripped so a commented-out entry does not count as active.
const collectPackageEntries = (modules) => {
  const entries = [];
  for (const { name, lines } of modules) {
    let inList = false;
    // Armed = we have seen `packages =` but not yet the `[` that opens its
    // value. alejandra reformats `packages = [ … ] ++ lib.optionals … [ … ]`
    // onto separate lines, leaving `packages =` alone with the opener below
    // it. Matching only the single-line form made the scanner skip such a
    // module entirely, which does not fail loudly -- every ownership
    // assertion built on the result just turns vacuous. Stay armed until the
    // `;` that ends the binding so the `++ … [` segments are scanned too.
    let armed = false;
    let depth = 0;
    lines.forEach((line, index) => {
      const code = line.split("#")[0];
      let scanFrom = code;
      if (!inList) {
        if (/^\s*(?:home\.packages|packages)\s*=\s*(?:with pkgs;\s*)?\[/.test(code)) {
          armed = true;
        } else if (/^\s*(?:home\.packages|packages)\s*=\s*$/.test(code)) {
          armed = true;
          return;
        } else if (!armed || !code.includes("[")) {
          if (armed && code.includes(";")) armed = false;
          return;
        }
        inList = true;
        depth = 1;
        scanFrom = code.slice(code.indexOf("[") + 1);
      }
      for (const token of scanFrom.match(/[A-Za-z0-9_'.-]+/g) ?? []) {
        entries.push({ token, where: `${name}:${index + 1}` });
      }
      depth += (scanFrom.match(/\[/g) ?? []).length - (scanFrom.match(/\]/g) ?? []).length;
      if (depth <= 0) {
        inList = false;
        // Keep `armed` so a following `++ lib.optionals … [` segment of the
        // same binding is still scanned; the `;` above disarms at its end.
        if (code.includes(";")) armed = false;
      }
    });
  }
  return entries;
};

test("Home Manager modules keep single ownership of every managed path and bin name", async () => {
  const modules = await moduleSources();
  assert.ok(modules.length >= 20, `module scan found only ${modules.length} files`);

  const fileKeys = collectFileKeys(modules);
  // Sentinel: the key scanner still sees the real key set.
  assert.ok(fileKeys.size >= 60, `home.file scan found only ${fileKeys.size} keys`);
  const duplicateKeys = [...fileKeys]
    .filter(([, sites]) => sites.length > 1)
    .map(([key, sites]) => `${key} <- ${sites.join(", ")}`);
  assert.deepEqual(
    duplicateKeys,
    [],
    "two modules claim one home.file path; home-manager merges them into one attrset and fails to evaluate",
  );

  const wrappers = collectWrappers(modules);
  // Sentinel: the wrapper scanner still sees both jcode-named derivations, so
  // the bin-collision assertion below is exercised rather than vacuous.
  assert.deepEqual(
    wrappers.filter((wrapper) => wrapper.bin === "jcode").map((wrapper) => wrapper.variable).sort(),
    ["jcodeGatewayWrapper", "jcodeLauncher"],
    "wrapper scan no longer sees both jcode-named derivations",
  );

  const entries = collectPackageEntries(modules);
  const listedVariables = new Set(entries.map((entry) => entry.token));
  // Sentinel: the packages scanner still reaches entries on continuation lines.
  assert.ok(
    listedVariables.has("jcodeGatewayWrapper"),
    "packages scan no longer sees multi-line home.packages entries",
  );
  // Sentinel: the scanner also reaches a `++ lib.optionals … [ … ]` segment.
  // Without this, an arch-guarded package is invisible to the bin-ownership
  // assertions below and a duplicate bin there would ship unnoticed.
  assert.ok(
    listedVariables.has("llm-pkgs.codex"),
    "packages scan no longer sees ++ lib.optionals package segments",
  );

  const binOwners = new Map();
  for (const wrapper of wrappers) {
    if (!listedVariables.has(wrapper.variable)) continue;
    if (!binOwners.has(wrapper.bin)) binOwners.set(wrapper.bin, []);
    binOwners.get(wrapper.bin).push(`${wrapper.variable}@${wrapper.where}`);
  }
  const collidingBins = [...binOwners]
    .filter(([, owners]) => owners.length > 1)
    .map(([bin, owners]) => `bin/${bin} <- ${owners.join(", ")}`);
  assert.deepEqual(
    collidingBins,
    [],
    'two derivations named alike are both in home.packages; pkgs.buildEnv fails with "conflicting subpath"',
  );

  // A raw package whose attr name resolves to a wrapper's bin name collides the
  // same way (re-enabling llm-pkgs.goose-cli would shadow gooseGatewayWrapper).
  const wrapperVariables = new Set(wrappers.map((wrapper) => wrapper.variable));
  const wrapperBins = new Set(wrappers.map((wrapper) => wrapper.bin));
  const shadowedRawPackages = entries
    .filter((entry) => {
      if (wrapperVariables.has(entry.token)) return false;
      const base = entry.token.split(".").pop().replace(/-(?:cli|bin)$/, "");
      return wrapperBins.has(base);
    })
    .map((entry) => `${entry.token} @ ${entry.where}`);
  assert.deepEqual(
    shadowedRawPackages,
    [],
    "a raw package in home.packages provides a bin name a wrapper derivation already owns",
  );
});
