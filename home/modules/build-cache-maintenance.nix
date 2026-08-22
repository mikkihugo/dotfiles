{
  pkgs,
  lib,
  ...
}: {
  # Fleet hosts run system sccache.service (nix-cache.nix): one daemon, one L0
  # disk cache (/var/cache/sccache), one FlakeCache /host bucket. Point every
  # client at the system socket so jcode, engine, and CI runner jobs share hits.
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

  home.activation.retireLegacyUserSccache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if systemctl --user is-active --quiet sccache.service 2>/dev/null; then
      systemctl --user stop sccache.service >/dev/null 2>&1 || true
      systemctl --user disable sccache.service >/dev/null 2>&1 || true
    fi
    if [ -d "$HOME/.cache/sccache" ]; then
      rm -rf "$HOME/.cache/sccache"
    fi
  '';
}
