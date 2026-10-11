{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  # kimi web from the hightower fork build (~/.cache/hightower/current is kept
  # current by hightower's .hightower/run-tower.sh). Bound to loopback only; the
  # tailnet reaches it through `tailscale serve --http 8080` (tailnet-only), so
  # auth is bypassed by operator decision (2026-10-11): local + tailnet only.
  port = "58627";
  healthCheck = pkgs.writeShellScript "kimi-web-health" ''
    set -eu
    if ! ${pkgs.curl}/bin/curl -fsS --max-time 10 -o /dev/null "http://127.0.0.1:${port}/"; then
      ${pkgs.systemd}/bin/systemctl --user restart kimi-web.service
    fi
  '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    systemd.user = {
      services.kimi-web = {
        Unit = {
          Description = "Kimi Code web UI (hightower fork build), loopback + tailnet via tailscale serve";
          After = ["default.target"];
        };
        Service = {
          # node via mise shims (Node >= 24.15 required by kimi-code).
          ExecStart = "%h/.local/share/mise/shims/node %h/.cache/hightower/current/apps/kimi-code/dist/main.mjs web --port ${port} --dangerous-bypass-auth";
          WorkingDirectory = "%h/code/hightower";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = ["KIMI_CODE_TRUST_WORKSPACE=1"];
        };
        Install.WantedBy = ["default.target"];
      };

      services.kimi-web-health = {
        Unit.Description = "Restart kimi web if it stops answering";
        Service = {
          Type = "oneshot";
          ExecStart = healthCheck;
        };
      };

      timers.kimi-web-health = {
        Unit.Description = "Periodic kimi web health check";
        Timer = {
          OnCalendar = "*:0/15";
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  }
