{pkgs, ...}: let
  checkoutSync = pkgs.writeShellApplication {
    name = "checkout-sync";
    runtimeInputs = [pkgs.python3 pkgs.git pkgs.coreutils];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../scripts/checkout-sync} "$@"
    '';
  };
in {
  systemd.user.services.checkout-sync = {
    Unit.Description = "Safely synchronize local Git checkouts";
    Service = {
      Type = "oneshot";
      ExecStart = "${checkoutSync}/bin/checkout-sync";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.checkout-sync = {
    Unit.Description = "Periodically synchronize local Git checkouts";
    Timer = {
      OnUnitActiveSec = "15min";
      OnBootSec = "5min";
      Persistent = true;
      Unit = "checkout-sync.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
