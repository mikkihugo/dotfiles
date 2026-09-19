# home/modules/files.nix — home.file symlinks
#
# Files that tools expect at specific $HOME paths, kept in version control
# and updated atomically on every `hms`. force=true overwrites any manually
# edited copy so the repo stays the source of truth.
#
# Agent hooks are NOT managed here: each CLI owns its hook files as plain
# files in its own home (see AGENTS.md "Agent hooks — not managed here").
{pkgs, ...}: {
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

    ".codex/AGENTS.md" = {
      source = ../../config/codex/AGENTS.md;
      force = true;
    };

    ".codex/model-catalogs/minimax-m3.json" = {
      source = ../../config/codex/model-catalogs/minimax-m3.json;
      force = true;
    };

    ".codex/minimax-m3.config.toml" = {
      source = ../../config/codex/minimax-m3.config.toml;
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

    ".copilot/copilot-instructions.md" = {
      source = ../../config/copilot/copilot-instructions.md;
      force = true;
    };

    # Custom /agent definitions for the interactive CLI (`/agent [name]`).
    # The .agent.md format is the user-defined-agent surface; the YAML
    # frontmatter declares name/description/model/tools, the body is the
    # agent's system prompt. NOT the same surface as the built-in
    # `task` tool's `agent_type` (those system prompts live in the CLI
    # binary). See config/copilot/agents/README.md for the split.
    ".copilot/agents/balanced.agent.md" = {
      source = ../../config/copilot/agents/balanced.agent.md;
      force = true;
    };
    ".copilot/agents/cheap-explore.agent.md" = {
      source = ../../config/copilot/agents/cheap-explore.agent.md;
      force = true;
    };
    ".copilot/agents/tri-lane.agent.md" = {
      source = ../../config/copilot/agents/tri-lane.agent.md;
      force = true;
    };
    ".copilot/agents/task-prompts.md" = {
      source = ../../config/copilot/agents/task-prompts.md;
      force = true;
    };
    ".copilot/agents/README.md" = {
      source = ../../config/copilot/agents/README.md;
      force = true;
    };

    ".cursor/rules/engine-swarm-bus.mdc" = {
      source = ../../config/cursor/rules/engine-swarm-bus.mdc;
      force = true;
    };

    # goose config.yaml is intentionally NOT HM-symlinked: goose writes
    # telemetry consent and other prefs into it. Seeded/merged in activation.nix.
    #
    # goose has no coordination-mailbox-sweep equivalent: verified (2026-09-06,
    # via block/goose docs + DeepWiki) that goose has no lifecycle hook system
    # at all -- only MCP extensions, which run tools by the agent's own choice,
    # not deterministically on session start. It already gets bus access via
    # the ccgw extension activation.nix seeds into
    # extensions:; that is the ceiling of what's possible here today.

    ".config/goose/moim-guardrails.md" = {
      source = ../../config/goose/moim-guardrails.md;
      force = true;
    };

    ".codex/agents/default.toml" = {
      source = ../../config/codex/agents/default.toml;
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

    ".codex/agents/scout.toml" = {
      source = ../../config/codex/agents/scout.toml;
      force = true;
    };

    ".codex/agents/implementer.toml" = {
      source = ../../config/codex/agents/implementer.toml;
      force = true;
    };

    ".codex/agents/reviewer.toml" = {
      source = ../../config/codex/agents/reviewer.toml;
      force = true;
    };

    ".agents/host/codex-device-auth.md" = {
      source = ../../config/agents/host/codex-device-auth.md;
      force = true;
    };

    # Gateway-backed profiles are deliberately outside ~/.codex/agents. They
    # are only for codex exec --ephemeral --profile external-<role>.
    ".codex/external-explorer.config.toml" = {
      source = ../../config/codex/external-profiles/external-explorer.config.toml;
      force = true;
    };

    ".codex/external-reasoner.config.toml" = {
      source = ../../config/codex/external-profiles/external-reasoner.config.toml;
      force = true;
    };

    ".codex/external-reviewer.config.toml" = {
      source = ../../config/codex/external-profiles/external-reviewer.config.toml;
      force = true;
    };

    ".codex/external-verifier.config.toml" = {
      source = ../../config/codex/external-profiles/external-verifier.config.toml;
      force = true;
    };

    ".codex/external-worker.config.toml" = {
      source = ../../config/codex/external-profiles/external-worker.config.toml;
      force = true;
    };

    # Agent skills are installed from the Engine-owned Purpose Tool MCP/plugin via
    # install_skills. Dotfiles keeps only archived legacy copies; Home Manager
    # must not republish them as live ~/.agents, ~/.claude, or ~/.copilot skills.
    # Reusable external-harness-orchestration is installed by Purpose Tool;
    # this module owns only the Codex-specific launcher and role profiles.
    # The provenance launcher is installed only under ~/.codex/bin.
    ".codex/bin/codex-external-run" = {
      source = pkgs.replaceVars ../../config/codex/bin/codex-external-run.mjs {
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
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

    ".copilot/settings.json" = {
      source = ../../config/copilot/settings.json;
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
