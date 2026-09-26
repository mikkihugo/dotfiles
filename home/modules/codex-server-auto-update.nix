{pkgs, ...}: let
  prepareDaemon = pkgs.writeShellScript "codex-managed-daemon-prepare" ''
    set -euo pipefail

    # A previous Codex client may have started the managed daemon outside
    # systemd. It is the only process allowed to own this socket.
    for pid in $(/run/current-system/sw/bin/pgrep -u "$UID" -f \
      'codex app-server --remote-control .*--managed-daemon' || true); do
      /run/current-system/sw/bin/kill -TERM "$pid" || true
    done
  '';
  codexServer = pkgs.writeShellScript "codex-managed-daemon" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    exec "$HOME/.codex/packages/standalone/current/bin/codex" \
      app-server --remote-control --listen unix:// --managed-daemon
  '';
  refreshServer = pkgs.writeShellScript "codex-server-auto-update" ''
    set -euo pipefail

    current="$(readlink -f /home/mhugo/.codex/packages/standalone/current/bin/codex)"
    pid="$(systemctl --user show --property=MainPID --value codex-managed-daemon.service)"
    if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && [[ -r "/proc/$pid/exe" ]]; then
      running="$(readlink -f "/proc/$pid/exe")"
      if [[ "$running" != "$current" ]]; then
        systemctl --user restart codex-managed-daemon.service
      fi
    fi
  '';
in {
  # Purpose: keep the one managed Codex app-server on the same release as the
  # installed CLI. Consumer: Codex clients using the managed app-server socket.
  # Contract: Home Manager owns one restartable daemon whose executable is the
  # current standalone release. The guardian is intentionally not involved.
  systemd.user = {
    services = {
      codex-managed-daemon = {
        Unit = {
          Description = "Managed Codex app-server";
          After = ["default.target"];
        };
        Service = {
          Type = "simple";
          ExecStartPre = "${prepareDaemon}";
          ExecStart = "${codexServer}";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };

      codex-server-auto-update = {
        Unit.Description = "Refresh the managed Codex app-server after CLI updates";
        Service = {
          Type = "oneshot";
          ExecStart = "${refreshServer}";
        };
      };
    };

    timers.codex-server-auto-update = {
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
        Unit = "codex-server-auto-update.service";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
