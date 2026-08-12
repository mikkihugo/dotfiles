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

  # sccache as a supervised service, not a daemon forked by whichever compiler
  # invocation happens to be first. Before this it had NO unit at all: the
  # running servers showed ppid=1, which reads like systemd owns them but is
  # only init adopting an orphan. Nothing restarted it, and its lifetime was
  # decided by whatever raced to start or stop it.
  #
  # systemd user units do NOT source hm-session-vars.sh, so every variable the
  # daemon needs is set here explicitly. SCCACHE_SERVER_UDS must match what
  # scripts/se_sccache_wrapper.sh hands clients ($SCCACHE_DIR/server.sock) or
  # they will start a second, competing server.
  systemd.user = {
    services.sccache = {
      Unit = {
        Description = "sccache compilation cache server";
        Documentation = "https://github.com/mozilla/sccache";
      };
      Service = {
        Type = "simple";
        Environment = [
          "SCCACHE_START_SERVER=1"
          "SCCACHE_NO_DAEMON=1"
          "SCCACHE_DIR=%h/.cache/sccache"
          "SCCACHE_SERVER_UDS=%h/.cache/sccache/server.sock"
          "SCCACHE_CACHE_SIZE=8G"
          "SCCACHE_IDLE_TIMEOUT=0"
        ];
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/.cache/sccache";
        ExecStart = "${pkgs.sccache}/bin/sccache";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = ["default.target"];
    };

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
        ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 14d";
      };
    };

    timers.nix-gc = {
      Unit.Description = "Collect old user Nix generations weekly";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
      Install.WantedBy = ["timers.target"];
    };
  };

  # sccache reads backend variables only when its daemon starts. Stop an older
  # disk-only daemon after activation; the next compiler invocation starts it
  # with the current shell's WebDAV token and these declarative settings.
  home.activation.restartSccacheOnConfigChange = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Restart the SUPERVISED unit rather than stopping a loose daemon. The old
    # form ran `sccache --stop-server`, which killed the server every build on
    # the host shared and left nothing to bring it back: sccache only
    # auto-starts a replacement on ConnectionRefused, TimedOut or NotFound, so
    # compiles already in flight blocked in read_one_response() -- which has no
    # timeout -- instead of failing. On 2026-08-12 an activation at 03:19:37
    # stranded eight clients; one gate sat 70 minutes at 0% CPU and the host
    # reached load 42.9.
    #
    # try-restart is a no-op when the unit is not running, so this stays safe on
    # a first activation before the unit exists.
    ${pkgs.systemd}/bin/systemctl --user try-restart sccache.service >/dev/null 2>&1 || true
  '';
}
