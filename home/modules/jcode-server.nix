# One long-lived JCode runtime owns sessions, MCP connections, and background
# work. Interactive `jcode` invocations detect its socket and attach as clients.
{
  config,
  hostname ? "",
  lib,
  pkgs,
  ...
}: let
  homeDir = config.home.homeDirectory;
  jcodeRaw = "${homeDir}/.jcode/builds/current/jcode";
  jcodeLauncher = pkgs.writeShellApplication {
    name = "jcode";
    text = ''
      export JCODE_NO_AUTO_UPDATE=1

      # Provider keys are loaded from the three Home Manager-rendered J-Code
      # env files. Remove ambient shell credentials so another client wrapper
      # or login shell cannot silently widen this runtime's provider surface.
      unset \
        ALIBABA_API_KEY \
        ALIBABA_CODING_PLAN_API_KEY \
        ALIBABA_TOKEN_PLAN_API_KEY \
        ANTHROPIC_API_KEY \
        AZURE_OPENAI_API_KEY \
        AZURE_OPENAI_ENDPOINT \
        CEREBRAS_API_KEY \
        CHUTES_API_KEY \
        CURSOR_ACCESS_TOKEN \
        CURSOR_API_KEY \
        CURSOR_REFRESH_TOKEN \
        DEEPINFRA_API_KEY \
        DEEPSEEK_API_KEY \
        GEMINI_API_KEY \
        GOOGLE_API_KEY \
        GOOGLE_GENERATIVE_AI_API_KEY \
        GROQ_API_KEY \
        JCODE_PROVIDER_LLM_GATEWAY_API_KEY \
        KIMI_API_KEY \
        KIMI_CODE_API_KEY \
        MINIMAX_API_KEY \
        MISTRAL_API_KEY \
        MOONSHOT_API_KEY \
        OLLAMA_API_KEY \
        OLLAMA_CLOUD_API_KEY \
        OPENAI_API_KEY \
        OPENCODE_API_KEY \
        OPENCODE_GO_API_KEY \
        OPENROUTER_API_KEY \
        XAI_API_KEY \
        ZAI_API_KEY \
        || true
      export JCODE_CURSOR_CLI_PATH="/nonexistent/jcode-disabled-cursor-agent"

      exec ${jcodeRaw} "$@"
    '';
  };
  jcodeTui = pkgs.writeShellApplication {
    name = "jcode-tui";
    runtimeInputs = [pkgs.coreutils pkgs.systemd pkgs.tmux];
    text = ''
      export JCODE_NO_AUTO_UPDATE=1
      runtimeDir="/run/user/$(${pkgs.coreutils}/bin/id -u)"
      tmuxSocket="$runtimeDir/jcode-ui.tmux.sock"

      if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet jcode-server.service; then
        echo "jcode-tui: jcode-server.service is not active" >&2
        exit 1
      fi

      if ! ${jcodeLauncher}/bin/jcode --no-update debug server:info >/dev/null; then
        echo "jcode-tui: J-Code server socket is not ready" >&2
        exit 1
      fi

      # A tmux session outlives WebTTY and Home Manager service restarts. Keep
      # that persistence across browser disconnects, but replace a pane whose
      # embedded launcher belongs to an older Home Manager generation.
      if ${pkgs.tmux}/bin/tmux -S "$tmuxSocket" has-session -t jcode-ui 2>/dev/null; then
        paneStartCommand="$(${pkgs.tmux}/bin/tmux -S "$tmuxSocket" display-message -p -t jcode-ui:0.0 '#{pane_start_command}' 2>/dev/null || true)"
        case "$paneStartCommand" in
          *"${jcodeLauncher}/bin/jcode"*) ;;
          *) ${pkgs.tmux}/bin/tmux -S "$tmuxSocket" kill-session -t jcode-ui || true ;;
        esac
      fi

      exec ${pkgs.tmux}/bin/tmux -S "$tmuxSocket" new-session -A -s jcode-ui "${jcodeLauncher}/bin/jcode"
    '';
  };
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    home = {
      # jcodeLauncher is deliberately NOT in home.packages: it is a
      # writeShellApplication named "jcode", so it collides in buildEnv with
      # ai-tools.nix's jcodeGatewayWrapper (also bin/jcode, and the module that
      # enforces the provider allowlist). The service reaches it by store path in
      # ExecStart, so it needs no PATH entry.
      packages = [jcodeTui];
      # The shadowed jcode entry under ~/.local/bin is owned by ai-tools.nix
      # (jcodeGatewayWrapper), which enforces the llm-gateway + OAuth provider
      # allowlist. Declaring it here too produced a conflicting home-manager
      # definition and broke evaluation. The allowlist wrapper wins; this service
      # reaches its launcher through the store path in ExecStart instead.

      # The NixOS jcode-server unit does not know about jcode-provider-config,
      # which is a Home Manager service rendering the provider env files. A
      # systemd DROP-IN adds that ordering without redefining the unit, so NixOS
      # keeps sole ownership of ExecStart and there is still exactly one unit.
      # Replacing the whole unit here is what caused the shadowing bug below.
      file.".config/systemd/user/jcode-server.service.d/10-provider-config.conf".text = ''
        [Unit]
        Requires=jcode-provider-config.service
        After=jcode-provider-config.service
      '';

      # Client-local memory off, via ENVIRONMENT rather than config.toml, because
      # jcode's TOML path is fail-open: load_from_file() swallows any parse error
      # and returns None, config.rs:13 does .unwrap_or_default(), and
      # FeatureConfig::default() has memory = true -- so ONE bad key anywhere in
      # ~/.jcode/config.toml silently re-enables memory. That is not theoretical:
      # it was off for 77 of the first 86 minutes after `[features] memory = false`
      # landed, with 2005 "Failed to parse config file" lines to show for it.
      # config.rs:14 applies env overrides AFTER unwrap_or_default(), so these
      # survive an unparsable config; the TOML setting cannot.
      #
      # Both tools are required: "memory" alone does not close the store, because
      # the "initiative" tool writes the same directory through
      # goal.rs sync_goal_memory -> upsert_project_memory/upsert_global_memory.
      # Durable agent memory belongs in the repo_memory bank, not a per-client store.
      file.".config/systemd/user/jcode-server.service.d/20-memory-disable.conf".text = ''
        [Service]
        Environment="JCODE_DISABLED_TOOLS=memory,initiative"
        Environment="JCODE_MEMORY_ENABLED=0"
      '';
    };

    # jcode-server and jcode-webtty are declared by NixOS in
    # /srv/infra/hosts/cc-se-sto-devbox-01/etc/nixos/swarm-runtime.nix as systemd
    # *user* services. Home Manager writes ~/.config/systemd/user, which takes
    # precedence over /etc/systemd/user, so duplicating them here silently
    # SHADOWED the system units: `systemctl --user show jcode-webtty
    # -p FragmentPath` resolved to the Home Manager copy.
    #
    # The two designs are not interchangeable. The system pair is coherent - the
    # server listens on %t/jcode.sock and webtty attaches to that same socket via
    # jcode-tmux-session, so the browser terminal survives disconnects. The Home
    # Manager copies ran a different binary with no socket and piped jcode-tui
    # straight into ttyd. Both wanted port 7681, so the shadowing copy won the
    # unit name and lost the bind, leaving jcode-webtty in an EADDRINUSE restart
    # loop (38 restarts in 5 minutes, 2026-08-08) while a hand-started
    # webtty-manual.service held the port and actually served the browser.
    #
    # One owner: NixOS. Home Manager keeps only the jcode-tui package.
  }
