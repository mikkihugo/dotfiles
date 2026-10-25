# Daily discovery run for the prior-art knowledge repo (singularity/prior-art):
# fetch leads, rebuild IMPACT.md / TRENDS.md, validate cards, commit and push.
# The repo script is the logic; this unit only schedules it. It is skipped on
# hosts without the checkout (ConditionPathExists).
{pkgs, ...}: {
  systemd.user.services.prior-art-daily = {
    Unit = {
      Description = "prior-art daily discovery (leads, impact, trends)";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
      ConditionPathExists = "%h/code/prior-art/scripts/daily.sh";
    };
    Service = {
      Type = "oneshot";
      Nice = 10;
      IOSchedulingClass = "idle";
      Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.python3 pkgs.git pkgs.gh pkgs.openssh pkgs.coreutils pkgs.bash]}"];
      ExecStart = "${pkgs.bash}/bin/bash %h/code/prior-art/scripts/daily.sh";
      TimeoutStartSec = "45min";
    };
  };

  systemd.user.timers.prior-art-daily = {
    Unit.Description = "Run prior-art daily discovery";
    Timer = {
      OnCalendar = "*-*-* 05:17:00";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "prior-art-daily.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
