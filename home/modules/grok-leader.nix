# Shared Grok leader: one backend for TUI/ACP clients.
#
# Clients still need `[cli] use_leader = true` in ~/.grok/config.toml (Grok
# owns that file; Home Manager does not pin it). Cursor worker stays off.
{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  # A Grok TUI spawns its own leader on demand when none is running. If that
  # leader already holds ~/.grok/leader.sock, this unit's start exits 1 with
  # "Another leader already holds the lock", Restart=on-failure loops, and the
  # unit ends in start-limit-hit (observed 2026-09-19 after an `hms` restart).
  # ExecCondition exit 1 = skip (not failed) while a reachable leader owns the
  # default socket; exit 0 = no leader, start one.
  noLiveLeader = pkgs.writeShellScript "grok-leader-no-live-leader" ''
    # `grok leader list` prints its listing on stderr, not stdout.
    listing="$("$HOME/.local/bin/grok" leader list 2>&1 || true)"
    case "$listing" in
      *"(Reachable) -- $HOME/.grok/leader.sock"*) exit 1 ;;
    esac
    exit 0
  '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    systemd.user.services.grok-leader = {
      Unit = {
        Description = "Grok shared leader process";
        After = ["default.target"];
        ConditionPathExists = "%h/.local/bin/grok";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      Service = {
        Type = "simple";
        ExecCondition = "${noLiveLeader}";
        # Wrapper unsets XAI_API_KEY and execs ~/.grok/bin/grok (OIDC).
        # Flags mirror the live invocation (2026-09-20): relay for headless/IDE
        # clients, grok.com code-agent ws; auto-update deliberately on so a
        # service-owned leader tracks the same channel the TUI does.
        ExecStart = "%h/.local/bin/grok agent leader --no-exit-on-disconnect --relay-on-demand --grok-ws-url wss://code.grok.com/ws/code-agent --grok-ws-origin https://grok.com";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = ["default.target"];
    };
  }
