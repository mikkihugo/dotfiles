{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  healthCheck = pkgs.writeShellScript "minimax-responses-compat-health" ''
    set -eu
    unit=minimax-responses-compat.service
    if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet "$unit"; then
      ${pkgs.systemd}/bin/systemctl --user restart "$unit"
    fi
    if ! ${pkgs.python3}/bin/python3 -c 'import json, urllib.request; r=urllib.request.urlopen("http://127.0.0.1:18787/v1/models-v2", timeout=10); d=json.load(r); assert r.status == 200 and any(x.get("id") == "minimax-m3-responses" for x in d.get("data", []))'; then
      ${pkgs.systemd}/bin/systemctl --user restart "$unit"
    fi
    listing="$(${pkgs.bash}/bin/bash -lc '$HOME/.local/bin/grok leader list 2>&1' || true)"
    case "$listing" in
      *"(Reachable) -- $HOME/.grok/leader.sock"*) ;;
      *) ${pkgs.systemd}/bin/systemctl --user start grok-leader.service || true ;;
    esac
  '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    home.file.".local/bin/minimax-responses-compat" = {
      source = ./minimax-responses-compat.py;
      executable = true;
    };

    systemd.user = {
      services.minimax-responses-compat = {
        Unit = {
          Description = "MiniMax Responses compatibility proxy for Grok";
          After = ["default.target"];
        };
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 %h/.local/bin/minimax-responses-compat";
          Restart = "on-failure";
          RestartSec = 3;
          Environment = [
            "MINIMAX_RESPONSES_UPSTREAM=https://api.minimax.io/v1"
            "MINIMAX_RESPONSES_LISTEN_HOST=127.0.0.1"
            "MINIMAX_RESPONSES_LISTEN_PORT=18787"
          ];
        };
        Install.WantedBy = ["default.target"];
      };

      services.minimax-responses-compat-health = {
        Unit.Description = "Check MiniMax Responses proxy and Grok leader";
        Service = {
          Type = "oneshot";
          ExecStart = healthCheck;
        };
      };

      timers.minimax-responses-compat-health = {
        Unit.Description = "Periodic MiniMax Responses proxy health check";
        Timer = {
          OnCalendar = "*:0/15";
          Persistent = true;
          Unit = "minimax-responses-compat-health.service";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  }
