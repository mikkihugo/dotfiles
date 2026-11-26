# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
#
# Agent hooks are NOT managed here: each CLI owns its hook files as plain
# files in its own home (see AGENTS.md "Agent hooks — not managed here").
{
  pkgs,
  lib,
  hostname ? "",
  ...
}: let
  # This host's Nix and direnv configuration is the NixOS module under
  # /srv/infra. A user nix.conf is loaded after /etc/nix/nix.conf and wins,
  # which is how keep-derivations=false used to undo the daemon.
  nixosOwnsHostNix = builtins.elem (lib.toLower hostname) ["cc-se-sto-devbox-01" "cc-fr-lau-devbox-01"];
in {
  home.file = {
    ".config/ripgrep/config" = {
      source = ../../config/ripgreprc;
      force = true;
    };

    ".config/bat/config".source = ../../config/bat/config;

    # VSCode: terminal font (Nerd Font), shell (zsh), editor defaults.
    # WSL2: also install the font on the Windows side for VSCode Remote:
    #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
    # Cursor Agent Shell is NOT controlled here — see shell.nix
    # home.file.".local/bin/zsh" → pkgs.zsh.
    ".config/Code/User/settings.json" = {
      source = ../../config/vscode/settings.json;
      force = true;
    };

    # Claude Code status line for Jujutsu-backed repos. Those repos replace `jj`
    # on PATH with a refuse shim and expose reads only through their own `repo
    # vcs` facade, so the usual git-branch status line has nothing to read.
    ".claude/statusline-jj.sh" = {
      source = pkgs.replaceVars ../../config/claude/statusline-jj.sh {
        bash = "${pkgs.bash}/bin/bash";
        jq = "${pkgs.jq}/bin/jq";
      };
      executable = true;
      force = true;
    };

    # ~/.copilot/copilot-instructions.md is intentionally NOT HM-symlinked:
    # Copilot writes its global custom instructions into this file, so a
    # read-only store symlink breaks in-client edits. Seeded as a mutable file
    # by seedMutableCopilotConfig in activation.nix (same pattern as goose).
    #
    # Custom /agent definitions for the interactive CLI (`/agent [name]`).
    # The .agent.md format is the user-defined-agent surface; the YAML
    # frontmatter declares name/description/model/tools, the body is the
    # agent's system prompt. NOT the same surface as the built-in
    # `task` tool's `agent_type` (those system prompts live in the CLI
    # binary). See config/copilot/agents/README.md for the split.
    #
    # All ~/.copilot content (settings.json, copilot-instructions.md, and
    # these agents/*.md) is intentionally NOT HM-symlinked: the Copilot CLI
    # may rewrite any of them in place, and a read-only nix-store symlink
    # makes in-client edits fail. Every path below is seeded as a mutable
    # file by seedMutableCopilotConfig in activation.nix (same pattern as
    # goose config.yaml). Do not re-add them to home.file.

    # goose config.yaml is intentionally NOT HM-symlinked: goose writes
    # telemetry consent and other prefs into it. Seeded/merged in activation.nix.
    #
    ".config/goose/moim-guardrails.md" = {
      source = ../../config/goose/moim-guardrails.md;
      force = true;
    };

    ".agents/host/codex-device-auth.md" = {
      source = ../../config/agents/host/codex-device-auth.md;
      force = true;
    };

    # SSH client config: host aliases for all servers (mail.hugo.dk, aidev, llm-gateway).
    # hetzner_id_ed25519 is rendered from SOPS by the renderHetznerSshKey activation hook.
    ".ssh/config" = {
      source = ../../config/ssh_config;
      force = true;
    };

    # Other Home Manager profiles still use the user builder file.
    # Fleet devboxes do not: /etc/nix/nix.conf is the config.
    ".config/nix/nix.conf" = lib.mkIf (!nixosOwnsHostNix) {
      source = ../../config/nix/local-build.nix.conf;
      force = true;
    };

    # ~/.copilot/settings.json is intentionally NOT HM-symlinked: Copilot
    # persists its own user settings into this file, so a read-only store
    # symlink blocks in-client setting changes. Seeded as a mutable file by
    # seedMutableCopilotConfig in activation.nix (same pattern as goose).

    ".factory/droids/worker.md" = {
      source = ../../config/factory/droids/worker.md;
      force = true;
    };

    ".factory/droids/scrutiny-feature-reviewer.md" = {
      source = ../../config/factory/droids/scrutiny-feature-reviewer.md;
      force = true;
    };

    ".factory/droids/user-testing-flow-validator.md" = {
      source = ../../config/factory/droids/user-testing-flow-validator.md;
      force = true;
    };

    ".factory/droids/mission-plan-validator.md" = {
      source = ../../config/factory/droids/mission-plan-validator.md;
      force = true;
    };

    ".factory/droids/repo-explorer.md" = {
      source = ../../config/factory/droids/repo-explorer.md;
      force = true;
    };

    ".factory/droids/debugger.md" = {
      source = ../../config/factory/droids/debugger.md;
      force = true;
    };

    ".factory/droids/security-reviewer.md" = {
      source = ../../config/factory/droids/security-reviewer.md;
      force = true;
    };

    ".factory/droids/release-readiness.md" = {
      source = ../../config/factory/droids/release-readiness.md;
      force = true;
    };

    ".local/share/applications/mynt-receipts.desktop" = {
      executable = true;
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Mynt Receipts
        Comment=Open Mynt in the dedicated receipts browser profile
        Exec=/home/mhugo/.local/bin/mynt-receipts
        Terminal=false
        Categories=Office;Finance;
        StartupWMClass=ReceiptsBrowser
      '';
    };

    ".local/share/applications/mynt-receipts-api.desktop" = {
      executable = true;
      force = true;
      text = ''
        [Desktop Entry]
        Type=Application
        Name=Mynt Receipts API
        Comment=Open Mynt with local-only CDP for receipt API discovery
        Exec=/home/mhugo/.local/bin/mynt-receipts-api
        Terminal=false
        Categories=Office;Finance;
        StartupWMClass=ReceiptsBrowserApi
      '';
    };
  };
}
