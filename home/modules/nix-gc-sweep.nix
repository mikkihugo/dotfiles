# home/modules/nix-gc-sweep.nix
#
# Prune stale nix-direnv gc roots and reclaim the resulting orphaned store
# paths. The companion binary `nix-direnv-gc` lives in
# ~/code/nix-direnv-gc (source repo, on the forge) and is installed to
# ~/.local/bin by `cargo install --path .` from that checkout.
#
# Three steps run on every sweep:
#   1. nix-direnv-gc --apply                    (worktree .direnv, jcode-cache, direnv layouts)
#   2. nix-direnv-gc --apply --deep-scan        (filesystem-wide sweep, 7d floor)
#   3. nix-collect-garbage --delete-older-than 1d  (reclaim store space)
#
# The 7d floor in step 2 protects active primaries (canonical jcode, active
# singularity-engine / infra worktrees) — anything younger than 7d is left
# alone. The 1d grace in step 3 gives running processes time to release
# closures that step 1 or 2 just orphaned.
#
# Recovery: if a live agent loses its cache, the next `direnv exec` triggers a
# ~15s re-eval and nix-direnv rebuilds the gc root symlink. Nothing is
# permanently lost.
{
  pkgs,
  ...
}: let
  sweepScript = pkgs.writeShellScript "nix-gc-sweep" ''
    set -euo pipefail

    LOG_PREFIX="[nix-gc-sweep $(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    DRY_RUN="''${DRY_RUN:-0}"
    GC_BIN="/home/mhugo/.local/bin/nix-direnv-gc"

    if [ ! -x "$GC_BIN" ]; then
        echo "$LOG_PREFIX nix-direnv-gc not found at $GC_BIN; aborting" >&2
        exit 1
    fi

    run() {
        echo "$LOG_PREFIX" "$@"
        if [ "$DRY_RUN" = "1" ]; then
            echo "$LOG_PREFIX (dry-run) would run:" "$@"
            return 0
        fi
        "$@"
    }

    # Step 1: prune known locations (worktree .direnv, nix-direnv cache, direnv layouts)
    run "$GC_BIN" --apply

    # Step 2: deep-scan filesystem for any flake-profile-* symlink we missed.
    # 7-day floor protects active primaries that the layout-dir walk already
    # sees; anything older is fair game.
    run "$GC_BIN" --apply --deep-scan --min-age-days 7

    # Step 3: reclaim store space for closures no other live root references.
    # --delete-older-than 1d gives a 1-day grace period for any new gc roots
    # that we just orphaned (e.g. closures still held open by running processes).
    run ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 1d

    echo "$LOG_PREFIX done"
  '';
in {
  systemd.user.services.nix-gc-sweep = {
    Unit = {
      Description = "Prune stale nix-direnv gc roots and reclaim Nix store space";
      Documentation = "file:///home/mhugo/code/nix-direnv-gc/README.md";
      # A Home Manager switch must never start this. Without keep-old, every
      # `hms` that changes the unit runs a sweep at an arbitrary moment, across
      # whatever caches are live. The timer is the sole start authority.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sweepScript}";
      Nice = 19;
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
      # nix-store walks can run for minutes on big stores; don't kill.
      TimeoutStartSec = "30min";
    };
  };

  systemd.user.timers.nix-gc-sweep = {
    Unit.Description = "Daily nix-direnv gc root sweep";
    Timer = {
      OnCalendar = "*-*-* 04:17:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
      Unit = "nix-gc-sweep.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}