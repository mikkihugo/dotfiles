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

  const gitBackup = await source("home/modules/git-auto-backup.nix");
  assert.match(gitBackup, /X-SwitchMethod\s*=\s*"keep-old"/);
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

test("Home Manager owns one persistent JCode server on the devbox", async () => {
  const home = await source("home/home.nix");
  assert.match(home, /\.\/modules\/jcode-server\.nix/);

  const service = await source("home/modules/jcode-server.nix");
  assert.match(service, /lib\.toLower hostname == "cc-se-sto-devbox-01"/);
  assert.match(service, /systemd\.user\.services\.jcode-server/);
  assert.match(
    service,
    /ExecStart\s*=\s*"\$\{jcodeLauncher\}\/bin\/jcode --no-update --model llm-gateway:umans-ai-coding-plan\/umans-glm-5\.2 serve --server-name devbox"/,
  );
  assert.match(service, /Restart\s*=\s*"always"/);
  assert.match(service, /KillMode\s*=\s*"control-group"/);
  assert.match(service, /Install\.WantedBy\s*=\s*\["default\.target"\]/);
  assert.match(service, /"JCODE_DEBUG_CONTROL=1"/);
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
  assert.match(service, /systemd\.user\.services\.jcode-webtty/);
  assert.match(
    service,
    /ExecStart\s*=\s*"\$\{pkgs\.ttyd\}\/bin\/ttyd -W -O -i lo -p 7681 -m 4 -w \$\{homeDir\} \$\{jcodeTui\}\/bin\/jcode-tui"/,
  );
  assert.match(service, /After\s*=\s*\["jcode-server\.service"\]/);
  assert.match(service, /Wants\s*=\s*\["jcode-server\.service"\]/);
  assert.match(service, /NoNewPrivileges\s*=\s*true/);
  assert.match(
    service,
    /RestrictAddressFamilies\s*=\s*\["AF_UNIX" "AF_INET" "AF_NETLINK"\]/,
  );
  assert.doesNotMatch(
    service,
    /ExecStartPre|rm\s+-f.*jcode(?:-daemon\.lock|\.sock)/,
    "service must not delete another daemon's live lock or socket",
  );
  assert.doesNotMatch(
    service,
    /ttyd[^"\n]*(?:0\.0\.0\.0|\[::\]|--credential|jcode connect)/,
    "WebTTY must remain loopback-only, credential-free behind SSH, and use the full TUI",
  );
});

test("JCode keeps one runtime with direct-preferred K3 and M3 plus explicit gateway fallbacks", async () => {
  const home = await source("home/home.nix");
  const service = await source("home/modules/jcode-server.nix");
  const providers = await source("home/modules/jcode-providers.nix");
  const preferences = await source("config/jcode/shared-preferences.toml");
  const prompt = await source("config/jcode/swarm-prompt.md");

  assert.match(home, /\.\/modules\/jcode-providers\.nix/);

  assert.match(service, /jcodeLauncher\s*=\s*pkgs\.writeShellApplication/);
  assert.match(service, /name\s*=\s*"jcode"/);
  // jcodeLauncher must stay OUT of home.packages: it is a writeShellApplication
  // named "jcode", so listing it collides in pkgs.buildEnv with ai-tools.nix's
  // jcodeGatewayWrapper, which owns bin/jcode and enforces the provider
  // allowlist. The service consumes the launcher by store path in ExecStart.
  assert.match(service, /packages\s*=\s*\[jcodeTui\]/);
  assert.doesNotMatch(service, /packages\s*=\s*\[[^\]]*jcodeLauncher/);
  assert.doesNotMatch(service, /file\."\.local\/bin\/jcode"/);
  assert.match(
    service,
    /unset[\s\S]*JCODE_PROVIDER_LLM_GATEWAY_API_KEY[\s\S]*KIMI_API_KEY/,
  );
  assert.match(
    service,
    /ExecStart\s*=\s*"\$\{jcodeLauncher\}\/bin\/jcode --no-update --model llm-gateway:umans-ai-coding-plan\/umans-glm-5\.2 serve --server-name devbox"/,
  );
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
  assert.match(service, /Requires\s*=\s*\["jcode-provider-config\.service"\]/);
  assert.match(
    service,
    /After\s*=\s*\["network-online\.target" "jcode-provider-config\.service"\]/,
  );
  assert.doesNotMatch(
    providers,
    /(?:KIMI_API_KEY|MINIMAX_API_KEY|JCODE_PROVIDER_LLM_GATEWAY_API_KEY)\s*=\s*"[A-Za-z0-9_-]{16,}"/,
  );

  assert.match(preferences, /model_picker_providers\s*=\s*\["llm-gateway", "kimi", "minimax-direct", "openai-oauth"\]/);
  assert.match(preferences, /cross_provider_failover\s*=\s*"manual"/);
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
  // Keep automation non-interactive: an anchored assignment rejects appended
  // flags such as --ask while allowing ordinary Nix whitespace.
  const hmsAlias = /^\s*hms\s*=\s*"nh home switch"\s*;/m;
  assert.match(shell, hmsAlias);
  assert.doesNotMatch(shell, /hms\s*=\s*"nh home switch --ask/);
  assert.match('hms  =  "nh home switch" ;', hmsAlias);
  assert.doesNotMatch('hms = "nh home switch --ask";', hmsAlias);
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
