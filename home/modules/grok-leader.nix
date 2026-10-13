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
  leaderSupervisor = pkgs.writeShellScript "grok-leader-supervisor" ''
    reachable() {
      "$HOME/.local/bin/grok" leader list 2>&1 | ${pkgs.gnugrep}/bin/grep -Fq Reachable
    }
    if reachable; then
      while reachable; do
        sleep 15
      done
      exit 1
    fi
    exec "$HOME/.local/bin/grok" agent leader --no-exit-on-disconnect \
      --relay-on-demand --grok-ws-url wss://code.grok.com/ws/code-agent \
      --grok-ws-origin https://grok.com
  '';
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    systemd.user.services.grok-leader = {
      Unit = {
        Description = "Grok shared leader supervisor";
        After = ["default.target"];
        ConditionPathExists = "%h/.local/bin/grok";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
        # Do not restart the shared leader (and every grok session riding on
        # it) just because a Home Manager switch edited this unit; changes
        # take effect at its next start.
        X-RestartIfChanged = false;
      };
      Service = {
        Type = "simple";
        ExecStart = "${leaderSupervisor}";
        Restart = "on-failure";
        RestartSec = 10;
        # Memory envelope (2026-10-10, after two hard resets that day; the
        # 17:21 one followed host memory exhaustion). Peaked at 20.4G; a live
        # read showed anon 0.5G + file cache 6.5G, so MemoryHigh mostly trims
        # reclaimable cache and MemoryMax bounds a real leak. A kill at the
        # ceiling restarts via Restart=on-failure instead of hanging the VM.
        MemoryHigh = "6G";
        MemoryMax = "12G";
        ManagedOOMPreference = "avoid";
      };
      Install.WantedBy = ["default.target"];
    };
  }
