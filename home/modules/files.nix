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
        flock = "${pkgs.util-linux}/bin/flock";
        bash = "${pkgs.bash}/bin/bash";
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

    ".kimi-code/hooks/swarm-messages.sh" = {
      source = pkgs.replaceVars ../../config/kimi-code/hooks/swarm-messages.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    # coordination-mailbox-sweep is the renamed, bounded, cursor-based
    # successor to the swarm-messages hook above. The swarm-messages.* paths
    # above stay as compatibility shims for one release (factory still names
    # them directly). Codex, Claude, Kimi-Code, Copilot, and Cursor hook
    # registrations point at the coordination-mailbox-sweep names below.
    ".codex/hooks/coordination-mailbox-sweep.mjs" = {
      source = pkgs.replaceVars ../../config/codex/hooks/coordination-mailbox-sweep.mjs {
        node = "${pkgs.nodejs}/bin/node";
        flock = "${pkgs.util-linux}/bin/flock";
        bash = "${pkgs.bash}/bin/bash";
      };
      executable = true;
      force = true;
    };

    ".claude/hooks/coordination-mailbox-sweep.sh" = {
      source = pkgs.replaceVars ../../config/claude/hooks/coordination-mailbox-sweep.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    # Claude-only lifecycle hooks. Hand-installed 2026-07/08 and never migrated
    # into HM-managed wiring until now: settings.json referenced them while
    # files.nix did not, so a ~/.claude/hooks/ wipe would remove them silently
    # and leave settings.json pointing at absent scripts.
    #
    # block-raw-git-in-jj-repos.sh is the PreToolUse guard that enforces the
    # raw-git prohibition in jj-backed repos -- losing it removes an
    # enforcement mechanism without removing the rule it enforces, which is
    # the worst of both.
    #
    # All four are self-contained (no @var@ placeholders, no /nix/store/
    # references), so plain source, no replaceVars -- same shape as
    # .copilot/hooks/remind-skills.sh above.
    ".claude/hooks/block-raw-git-in-jj-repos.sh" = {
      source = ../../config/claude/hooks/block-raw-git-in-jj-repos.sh;
      executable = true;
      force = true;
    };
    ".claude/hooks/workspace-closure-report.sh" = {
      source = ../../config/claude/hooks/workspace-closure-report.sh;
      executable = true;
      force = true;
    };
    ".claude/hooks/worktree-create-global.sh" = {
      source = ../../config/claude/hooks/worktree-create-global.sh;
      executable = true;
      force = true;
    };
    ".claude/hooks/worktree-remove-global.sh" = {
      source = ../../config/claude/hooks/worktree-remove-global.sh;
      executable = true;
      force = true;
    };

    # SessionStart skills gate. Our using-skills router is `origin: superpowers
    # ... adapted`; upstream ships a SessionStart hook that force-injects its
    # router body, and our adaptation kept the prose but dropped that hook. The
    # measured result was a gate nothing executed: 26 of 43 skills at zero uses
    # ever, and the router invoked only on the day a human asked about it.
    #
    # Client-agnostic on purpose -- it selects its output shape per harness
    # (SKILLS_GATE_SHAPE=claude|cursor|sdk), so the same file serves every CLI
    # coder. Only .claude is wired so far; the other clients each need their own
    # registration in their own config format.
    ".claude/hooks/skills-gate-session-start.sh" = {
      source = ../../config/claude/hooks/skills-gate-session-start.sh;
      executable = true;
      force = true;
    };

    # Stop hook: blocks the session from going idle while a "question" or
    # "blocker" bus message sits unacked, capped so it can never livelock.
    # Claude-only (not shared with other clients the way the sweep script
    # is), so both files render into .claude/hooks/ rather than a shared
    # canonical path.
    ".claude/hooks/stop-continue-if-actionable.mjs" = {
      source = ../../config/claude/hooks/stop-continue-if-actionable.mjs;
      executable = true;
      force = true;
    };

    ".claude/hooks/stop-continue-if-actionable.sh" = {
      source = pkgs.replaceVars ../../config/claude/hooks/stop-continue-if-actionable.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".kimi-code/hooks/coordination-mailbox-sweep.sh" = {
      source = pkgs.replaceVars ../../config/kimi-code/hooks/coordination-mailbox-sweep.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".copilot/hooks/coordination-mailbox-sweep.sh" = {
      source = pkgs.replaceVars ../../config/copilot/hooks/coordination-mailbox-sweep.sh {
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

    # remind-skills userPromptSubmitted hook: emits a skill-catalog nudge to
    # stderr on non-trivial prompts (throttled to 1-in-5). Hand-installed
    # 2026-06-21; never migrated into HM-managed wiring until now. Without
    # this entry, the hook disappears on the next `~/.copilot/hooks/` wipe.
    # Script is self-contained (no @var@ placeholders), so no replaceVars.
    ".copilot/hooks/remind-skills.json" = {
      source = ../../config/copilot/hooks/remind-skills.json;
      force = true;
    };
    ".copilot/hooks/remind-skills.sh" = {
      source = ../../config/copilot/hooks/remind-skills.sh;
      executable = true;
      force = true;
    };

    ".cursor/hooks.json" = {
      source = ../../config/cursor/hooks.json;
      force = true;
    };

    ".factory/hooks/coordination-mailbox-sweep.sh" = {
      source = pkgs.replaceVars ../../config/factory/hooks/coordination-mailbox-sweep.sh {
        bash = "${pkgs.bash}/bin/bash";
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    # goose config.yaml is intentionally NOT HM-symlinked: goose writes
    # telemetry consent and other prefs into it. Seeded/merged in activation.nix.
    #
    # goose has no coordination-mailbox-sweep equivalent: verified (2026-09-06,
    # via block/goose docs + DeepWiki) that goose has no lifecycle hook system
    # at all -- only MCP extensions, which run tools by the agent's own choice,
    # not deterministically on session start. It already gets bus access via
    # the centralcloud-mcp-gateway extension activation.nix seeds into
    # extensions:; that is the ceiling of what's possible here today.

    ".config/goose/moim-guardrails.md" = {
      source = ../../config/goose/moim-guardrails.md;
      force = true;
    };

    # opencode has a real plugin API (opencode.ai/docs/plugins) but only a
    # generic event(input) dispatcher for session lifecycle -- no
    # UserPromptSubmit equivalent, so this covers SessionStart only. Global
    # plugins load from ~/.config/opencode/plugins/ per opencode's docs; no
    # opencode.json registration needed.
    ".config/opencode/plugins/coordination-mailbox-sweep.js" = {
      source = ../../config/opencode/plugins/coordination-mailbox-sweep.js;
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
    # One Codex-only user skill is managed here; do not mirror .agents/skills,
    # .system, or unrelated skill trees.
    # Codex-only external-harness launcher with run provenance; installed only
    # under ~/.codex/bin (never ~/.agents or global PATH). See
    # config/codex/skills/external-harness-orchestration.
    ".codex/bin/codex-external-run" = {
      source = pkgs.replaceVars ../../config/codex/bin/codex-external-run.mjs {
        node = "${pkgs.nodejs}/bin/node";
      };
      executable = true;
      force = true;
    };

    ".codex/skills/external-harness-orchestration" = {
      source = ../../config/codex/skills/external-harness-orchestration;
      recursive = true;
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
