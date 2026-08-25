{
  pkgs,
  lib,
  ...
}: let
  # Minimal explicit PATH: user units do not inherit an interactive PATH.
  binPath = lib.makeBinPath [pkgs.procps pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.bash];
in {
  # Reap search processes whose agent already stopped waiting for them.
  #
  # codex's exec_command `yield_time_ms` is a YIELD, not a kill: at the deadline
  # codex records "Script completed" with EMPTY output and moves on, leaving the
  # whole subtree running. On 2026-08-25 four such orphans scanning /nix/store
  # and $HOME held this box at load 70 with PSI io full=40% while CPU sat ~46%
  # idle. Nothing else here reaps them — every janitor unit prunes files, and
  # systemd-oomd triggers on memory pressure only, never on I/O.
  #
  # Targeting is by ANCESTRY, not age alone, so a human's deliberate long search
  # is never killed. See scripts/reap-abandoned-searches.sh for the rule.
  home.file.".local/bin/reap-abandoned-searches" = {
    source = ../../scripts/reap-abandoned-searches.sh;
    executable = true;
  };

  systemd.user.services.reap-abandoned-searches = {
    Unit.Description = "Reap abandoned agent search processes (rg/find/grep orphans)";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/reap-abandoned-searches";
      Environment = [
        "PATH=${binPath}"
        "BASH_ENV=/dev/null"
      ];
      # Never let the reaper itself contend for the I/O it exists to protect.
      IOSchedulingClass = "idle";
      Nice = 19;
      TimeoutStartSec = "2min";
      WorkingDirectory = "/tmp";
    };
  };

  systemd.user.timers.reap-abandoned-searches = {
    Unit.Description = "Reap abandoned agent search processes every 5 minutes";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
      Unit = "reap-abandoned-searches.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
