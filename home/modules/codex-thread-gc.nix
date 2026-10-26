{
  lib,
  pkgs,
  ...
}: let
  binPath = lib.makeBinPath [pkgs.coreutils pkgs.nodejs];
in {
  home.file.".local/bin/codex-thread-gc" = {
    source = ../../scripts/codex-thread-gc.mjs;
    executable = true;
  };

  systemd.user.services.codex-thread-gc = {
    Unit.Description = "Unload completed Codex Companion app-server threads";
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/codex-thread-gc --age-hours=24 --apply";
      Environment = ["PATH=${binPath}" "BASH_ENV=/dev/null"];
      IOSchedulingClass = "idle";
      Nice = 19;
      TimeoutStartSec = "2min";
      WorkingDirectory = "/tmp";
    };
  };

  systemd.user.timers.codex-thread-gc = {
    Unit.Description = "Unload completed Codex Companion threads hourly";
    Timer = {
      OnBootSec = "15min";
      OnUnitActiveSec = "1h";
      Unit = "codex-thread-gc.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
