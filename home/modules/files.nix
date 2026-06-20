# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
_: {
  home.file = {
    ".config/ripgrep/config" = {
      source = ../../config/ripgreprc;
      force = true;
    };

    ".config/bat/config".source = ../../config/bat/config;

    # VSCode: terminal font (Nerd Font), shell (zsh), editor defaults.
    # WSL2: also install the font on the Windows side for VSCode Remote:
    #   winget install -e --id DEVCOM.JetBrainsMonoNerdFont
    ".config/Code/User/settings.json" = {
      source = ../../config/vscode/settings.json;
      force = true;
    };

    # Codex CLI config is seeded by activation.nix as a mutable file. The Codex
    # client owns model/reasoning choices, approvals, notices, and feature
    # toggles at runtime, so this path must not be a Home Manager symlink.
    ".codex/rules/default.rules" = {
      source = ../../config/codex/default.rules;
      force = true;
    };

    # Shared cross-agent skills. Keep these in dotfiles so Codex, Claude,
    # Gemini, and other clients read the same personal process library.
    ".agents/AGENTS.md" = {
      source = ../../config/agents/AGENTS.md;
      force = true;
    };

    ".agents/skills" = {
      source = ../../config/agents/skills;
      force = true;
    };

    # SSH client config: host aliases for all servers (mail.hugo.dk, aidev, llm-gateway).
    # hetzner_id_ed25519 is rendered from SOPS by the renderHetznerSshKey activation hook.
    ".ssh/config" = {
      source = ../../config/ssh_config;
      force = true;
    };

    # Nix user config: build locally, consume shared binary caches.
    ".config/nix/nix.conf" = {
      source = ../../config/nix/local-build.nix.conf;
      force = true;
    };

    ".factory/settings.json" = {
      source = ../../config/factory/settings.json;
      force = true;
    };

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
