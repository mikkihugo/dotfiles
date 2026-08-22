{
  pkgs,
  lib,
  ...
}: {
  # Fleet hosts run system sccache.service (nix-cache.nix): one daemon, one L0
  # disk cache (/var/cache/sccache), one FlakeCache /host bucket. Point every
  # client at the system socket so jcode, engine, and other repos share hits for
  # the same dependency + rustc version.
  home.sessionVariables = {
    SCCACHE_DIR = lib.mkForce "/var/cache/sccache";
    SCCACHE_SERVER_UDS = lib.mkForce "/run/sccache/server.sock";
    SCCACHE_CACHE_SIZE = lib.mkForce "8G";
    SCCACHE_IDLE_TIMEOUT = lib.mkForce "0";
    SCCACHE_IGNORE_SERVER_IO_ERROR = lib.mkForce "1";
  };

  systemd.user = {
    services.nix-gc = {
      Unit = {
        Description = "Prune home-manager generations (keep 5) and collect old user Nix generations";
        Documentation = "man:nix-collect-garbage(1)";
      };
      Service = {
        Type = "oneshot";
        # Keep only the 5 most recent home-manager generations, then GC
        ExecStartPre = pkgs.writeShellScript "hm-prune-generations" ''
          set -euo pipefail
          ${pkgs.home-manager}/bin/home-manager generations \
            | awk 'NR>5 {print $5}' \
            | xargs --no-run-if-empty ${pkgs.home-manager}/bin/home-manager remove-generations
        '';
        ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 3d";
      };
    };

    timers.nix-gc = {
      Unit.Description = "Collect old user Nix generations twice daily";
      Timer = {
        OnCalendar = [
          "04:15"
          "16:45"
        ];
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
