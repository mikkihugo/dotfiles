# evalgate — fleet lock gate (see tools/evalgate/README.md).
# Built with gomod2nix (ADR-0097 *2nix doctrine): per-dep derivations via the
# generated deps.nix. Regenerate after any go.mod change:
#   nix run github:nix-community/gomod2nix -- generate   (in tools/evalgate)
# Freshness falsifier: a dep bump without regenerating gomod2nix.toml must
# fail tools/evalgate/check-deps-fresh.sh (wired into repo test).
{pkgs, ...}: {
  home.packages = [
    (pkgs.buildGoApplication {
      pname = "evalgate";
      version = "0.1.0";
      src = ../../tools/evalgate;
      modules = ../../tools/evalgate/gomod2nix.toml;
      ldflags = ["-s" "-w"];
    })
  ];
  # Bounded-holder watchdog: no nix process may hold the fleet eval locks past
  # the budget. A dead remote builder turned a 30s derivation into a 1h52m hang
  # on 2026-11-13; the SSH ConnectTimeout is the source fix, this is the
  # backstop for every other stall class.
  systemd.user.services.evalgate-sweep = {
    Unit.Description = "Kill nix processes that exceed the wall-clock budget";
    Service = {
      Type = "oneshot";
      ExecStart = "/home/mhugo/.local/bin/evalgate sweep -max-age 45m -apply";
    };
  };
  systemd.user.timers.evalgate-sweep = {
    Unit.Description = "Run the evalgate sweep every 10 minutes";
    Timer = {
      OnCalendar = "*:0/10";
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
