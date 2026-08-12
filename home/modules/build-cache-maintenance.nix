{
  pkgs,
  lib,
  ...
}: {
  # Keep the local compiler cache bounded. Do NOT export WebDAV endpoint or a
  # disk,webdav multilevel chain here: session vars apply even when the
  # FlakeCache action token failed to load, and sccache then 401s on
  # `.sccache_check`. WebDAV is enabled only from bashrc when the token is
  # present (and by Engine `nix develop` when credentials are in the env).
  home.sessionVariables = {
    SCCACHE_CACHE_SIZE = lib.mkForce "8G";
    SCCACHE_DIR = "$HOME/.cache/sccache";
    SCCACHE_IDLE_TIMEOUT = "0";
    # Degrade instead of hanging. The client falls back to compiling locally
    # when the server I/O fails, so a dead or restarting daemon costs a slower
    # build rather than a stuck one. Without this, a compile whose server goes
    # away mid-request blocks in read_one_response(), which has no timeout and
    # no env var to bound it — observed 2026-08-12: eight clients stranded, one
    # `just vcs test` sat 70 minutes at 0% CPU with a zombie sccache under
    # .cargo-wrapped, and the host hit load 42.9.
    SCCACHE_IGNORE_SERVER_IO_ERROR = "1";
  };

  systemd.user.services.nix-gc = {
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
