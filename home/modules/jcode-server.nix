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
  servicePath = lib.concatStringsSep ":" [
    "${homeDir}/.local/bin"
    "${homeDir}/.local/share/mise/shims"
    "${homeDir}/.npm-global/bin"
    "${homeDir}/.cargo/bin"
    "${pkgs.bashInteractive}/bin"
    "${pkgs.coreutils}/bin"
    "${pkgs.findutils}/bin"
    "${pkgs.gnugrep}/bin"
    "${pkgs.gnused}/bin"
    "${pkgs.openssh}/bin"
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ];
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
    };

    systemd.user.services.jcode-server = {
      Unit = {
        Description = "JCode single-server agent daemon";
        Requires = ["jcode-provider-config.service"];
        After = ["network-online.target" "jcode-provider-config.service"];
        Wants = ["network-online.target"];
      };

      Service = {
        Type = "simple";
        WorkingDirectory = homeDir;
        # Let J-Code build its MultiProvider catalog so swarm workers can see
        # every configured direct route. The route-prefixed model still pins
        # the root coordinator to the llm-gateway GLM profile.
        ExecStart = "${jcodeLauncher}/bin/jcode --no-update --model llm-gateway:umans-ai-coding-plan/umans-glm-5.2 serve --server-name devbox";
        Environment = [
          "JCODE_DEBUG_CONTROL=1"
          "JCODE_NO_AUTO_UPDATE=1"
          "PATH=${servicePath}"
        ];
        Restart = "always";
        RestartSec = "2s";
        KillMode = "control-group";
        TimeoutStopSec = "30s";
        UMask = "0077";
      };

      Install.WantedBy = ["default.target"];
    };

    systemd.user.services.jcode-webtty = {
      Unit = {
        Description = "Loopback WebTTY for the shared JCode TUI";
        After = ["jcode-server.service"];
        Wants = ["jcode-server.service"];
      };

      Service = {
        Type = "simple";
        WorkingDirectory = homeDir;
        ExecStart = "${pkgs.ttyd}/bin/ttyd -W -O -i lo -p 7681 -m 4 -w ${homeDir} ${jcodeTui}/bin/jcode-tui";
        Restart = "always";
        RestartSec = "2s";
        KillMode = "control-group";
        TimeoutStopSec = "10s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_NETLINK"];
      };

      Install.WantedBy = ["default.target"];
    };
  }
