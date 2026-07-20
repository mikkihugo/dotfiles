# home/modules/nix-index.nix — keep the nix-index database generated.
#
# nix-index without its generated database leaves both nix-locate and comma
# installed but unusable. The database is derived cache state, not repository
# state, so Home Manager schedules regeneration instead of committing it.
{pkgs, ...}: {
  # Lets `nh home switch` resolve the managed flake without another argument.
  home.sessionVariables.NH_HOME_FLAKE = "$HOME/.dotfiles";

  systemd.user.services.nix-index-update = {
    Unit.Description = "Regenerate the nix-index database for nix-locate and comma";
    Service = {
      Type = "oneshot";
      Nice = 19;
      IOSchedulingClass = "idle";
      ExecStart = "${pkgs.nix-index}/bin/nix-index";
      TimeoutStartSec = "45min";
    };
  };

  systemd.user.timers.nix-index-update = {
    Unit.Description = "Weekly nix-index database refresh";
    Timer = {
      # Persistent catch-up applies to wall-clock timers. A monotonic-only
      # boot anchor can leave a long-lived user manager with no next firing.
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "30min";
      Unit = "nix-index-update.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
