# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
{pkgs, ...}: {
  home.file = {
    ".config/ripgrep/config" = {
      source = ../../config/ripgreprc;
      force = true;
    };

    ".config/bat/config".source = ../../config/bat/config;

    # Cargo: use sccache for all Rust builds launched by this user.
    ".cargo/config.toml" = {
      force = true;
      text = ''
        [build]
        rustc-wrapper = "sccache"
      '';
    };

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

    ".codex/AGENTS.md" = {
      source = ../../config/codex/AGENTS.md;
      force = true;
    };

    ".codex/hooks.json" = {
      source = ../../config/codex/hooks.json;
      force = true;
    };

    ".codex/hooks/swarm-messages.mjs" = {
      source = pkgs.replaceVars ../../config/codex/hooks/swarm-messages.mjs {
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".claude/hooks/swarm-messages.sh" = {
      source = pkgs.replaceVars ../../config/claude/hooks/swarm-messages.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".kimi-code/hooks/swarm-messages.sh" = {
      source = pkgs.replaceVars ../../config/kimi-code/hooks/swarm-messages.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".copilot/hooks/swarm-messages.json" = {
      source = ../../config/copilot/hooks/swarm-messages.json;
      force = true;
    };

    ".cursor/hooks.json" = {
      source = ../../config/cursor/hooks.json;
      force = true;
    };

    # goose config.yaml is intentionally NOT HM-symlinked: goose writes
    # telemetry consent and other prefs into it. Seeded/merged in activation.nix.

    ".codex/agents/default.toml" = {
      source = ../../config/codex/agents/default.toml;
      force = true;
    };

    ".codex/agents/worker.toml" = {
      source = ../../config/codex/agents/worker.toml;
      force = true;
    };

    ".codex/agents/coder-fast.toml" = {
      source = ../../config/codex/agents/coder-fast.toml;
      force = true;
    };

    ".codex/agents/coder-smart.toml" = {
      source = ../../config/codex/agents/coder-smart.toml;
      force = true;
    };

    ".codex/agents/test-writer.toml" = {
      source = ../../config/codex/agents/test-writer.toml;
      force = true;
    };

    ".codex/agents/debugger.toml" = {
      source = ../../config/codex/agents/debugger.toml;
      force = true;
    };

    ".codex/agents/reviewer.toml" = {
      source = ../../config/codex/agents/reviewer.toml;
      force = true;
    };

    ".codex/agents/verifier.toml" = {
      source = ../../config/codex/agents/verifier.toml;
      force = true;
    };

    ".codex/agents/web-researcher.toml" = {
      source = ../../config/codex/agents/web-researcher.toml;
      force = true;
    };

    ".codex/agents/explorer.toml" = {
      source = ../../config/codex/agents/explorer.toml;
      force = true;
    };

    ".codex/agents/taxonomy-worker.toml" = {
      source = ../../config/codex/agents/taxonomy-worker.toml;
      force = true;
    };

    ".codex/agents/taxonomy-validator.toml" = {
      source = ../../config/codex/agents/taxonomy-validator.toml;
      force = true;
    };

    ".codex/agents/singularity-engine-harvester.toml" = {
      source = ../../config/codex/agents/singularity-engine-harvester.toml;
      force = true;
    };

    # Agent skills are installed from the Engine-owned Purpose Tool MCP/plugin via
    # install_skills. Dotfiles keeps only archived legacy copies; Home Manager
    # must not republish them as live ~/.agents, ~/.claude, or ~/.copilot skills.

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

    ".copilot/settings.json" = {
      source = ../../config/copilot/settings.json;
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
