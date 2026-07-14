{
  config,
  pkgs,
  lib,
  ...
}: {
  # Keep the local compiler cache bounded. WebDAV credentials remain injected
  # by the existing secret-loading path and are never written to the Nix store.
  home.sessionVariables = {
    SCCACHE_CACHE_SIZE = lib.mkForce "8G";
    SCCACHE_DIR = "$HOME/.cache/sccache";
    SCCACHE_WEBDAV_ENDPOINT = "https://cache.flakecache.com/default/sccache/project/singularity-engine";
    SCCACHE_MULTILEVEL_CHAIN = "disk,webdav";
    SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY = "l0";
    SCCACHE_IDLE_TIMEOUT = "0";
  };

  systemd.user.services.nix-gc = {
    Unit = {
      Description = "Collect old user Nix generations";
      Documentation = "man:nix-collect-garbage(1)";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 14d";
    };
  };

  systemd.user.timers.nix-gc = {
    Unit.Description = "Collect old user Nix generations weekly";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
    Install.WantedBy = ["timers.target"];
  };

  # sccache reads backend variables only when its daemon starts. Stop an older
  # disk-only daemon after activation; the next compiler invocation starts it
  # with the current shell's WebDAV token and these declarative settings.
  home.activation.restartSccacheOnConfigChange = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.sccache}/bin/sccache --stop-server >/dev/null 2>&1 || true
  '';
}
