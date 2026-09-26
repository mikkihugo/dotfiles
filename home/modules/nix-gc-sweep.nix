# home/modules/nix-gc-sweep.nix
#
# Prune stale nix-direnv gc roots and reclaim the resulting orphaned store
# paths. The companion binary `nix-direnv-gc` lives in
# ~/code/nix-direnv-gc (source repo, on the forge) and is installed to
# ~/.local/bin by `cargo install --path .` from that checkout.
#
# Four steps run on every sweep:
#   1. nix-direnv-gc --apply                    (worktree .direnv including leftover flake-inputs, jcode-cache, direnv layouts)
#   2. nix-direnv-gc --apply --deep-scan        (filesystem-wide sweep, 7d floor)
#   3. nix-collect-garbage --delete-older-than 1d  (reclaim store space)
#   4. nix-gc-reprovision                       (warm canonical dev shells + Engine repo-vcs generation store)
#
# Step 4 also runs after the standalone `nix-gc.service` (weekly `nix-collect-garbage -d`)
# via OnSuccess, so timers do not have to wait for the daily sweep.
#
# Leftover `.direnv/flake-inputs/` dirs are always prune candidates: the
# flake-profile already keeps the built shell. Recursing into those dirs is
# still skipped (they are Nix store copies, not nested worktrees).
#
# The 7d floor in step 2 protects active primaries (canonical jcode, active
# singularity-engine / infra worktrees) — anything younger than 7d is left
# alone. The 1d grace in step 3 gives running processes time to release
# closures that step 1 or 2 just orphaned.
{pkgs, ...}: let
  canonicalDevRoots = [
    "/home/mhugo/code/singularity-engine"
    "/home/mhugo/code/jcode"
    "/srv/infra"
  ];

  reprovisionScript = pkgs.writeShellScript "nix-gc-reprovision" ''
    set -euo pipefail

    LOG_PREFIX="[nix-gc-reprovision $(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    DRY_RUN="''${DRY_RUN:-0}"
    DIRENV="${pkgs.direnv}/bin/direnv"

    reprovision_root() {
      local root="$1"
      if [[ ! -f "$root/.envrc" ]]; then
        echo "$LOG_PREFIX skip (no .envrc): $root" >&2
        return 0
      fi
      echo "$LOG_PREFIX warm dev shell: $root" >&2
      if [[ "$DRY_RUN" = "1" ]]; then
        echo "$LOG_PREFIX (dry-run) would run: direnv exec $root …" >&2
        return 0
      fi
      if ! "$DIRENV" exec "$root" ${pkgs.bash}/bin/bash -c "cd \"$root\" && command -v true >/dev/null"; then
        echo "$LOG_PREFIX WARN: direnv exec failed for $root (continuing)" >&2
        return 0
      fi
      if [[ -x "$root/scripts/se_repo_vcs_bin.sh" ]]; then
        echo "$LOG_PREFIX provision repo-vcs generation: $root" >&2
        if ! "$DIRENV" exec "$root" ${pkgs.bash}/bin/bash -c "cd \"$root\" && bash scripts/se_repo_vcs_bin.sh"; then
          echo "$LOG_PREFIX WARN: se_repo_vcs_bin.sh failed for $root (continuing)" >&2
        fi
      fi
      return 0
    }

    for root in ${builtins.concatStringsSep " " canonicalDevRoots}; do
      reprovision_root "$root"
    done

    echo "$LOG_PREFIX done" >&2
  '';

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
    run ${pkgs.util-linux}/bin/flock \
      --wait 900 \
      /run/user/1000/codex-fleet-nix-evaluation.lock \
      ${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 1d

    # Step 4: rebuild canonical direnv profiles and Engine repo-vcs shared generation.
    if [[ "$DRY_RUN" = "1" ]]; then
      echo "$LOG_PREFIX (dry-run) would run: ${reprovisionScript}" >&2
    else
      ${reprovisionScript}
    fi

    echo "$LOG_PREFIX done"
  '';
in {
  systemd.user.services = {
    nix-gc-reprovision = {
      Unit = {
        Description = "Warm canonical dev shells after Nix GC (Engine, jcode, infra)";
        Documentation = "file:///home/mhugo/.dotfiles/home/modules/nix-gc-sweep.nix";
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${reprovisionScript}";
        Nice = 19;
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
        TimeoutStartSec = "45min";
      };
    };

    # Replaces the static ~/.config/systemd/user/nix-gc.service on switch so
    # weekly `nix-collect-garbage -d` also triggers reprovision.
    nix-gc = {
      Unit = {
        Description = "Nix Garbage Collector";
        Documentation = ["man:nix-collect-garbage(1)"];
        OnSuccess = ["nix-gc-reprovision.service"];
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.nix}/bin/nix-collect-garbage -d";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    nix-gc-sweep = {
      Unit = {
        Description = "Prune stale nix-direnv gc roots and reclaim Nix store space";
        Documentation = "file:///home/mhugo/code/nix-direnv-gc/README.md";
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${sweepScript}";
        Nice = 19;
        IOSchedulingClass = "idle";
        IOSchedulingPriority = 7;
        # 2026-09-26: the daily run was killed at 30min mid `--deep-scan`
        # (Result: timeout, 5min CPU over 30min wall: it is I/O-bound at idle
        # priority on a busy disk), so the store-space step never ran. Give the
        # scan room; the unit is Nice=19/idle-IO and a timer, nobody waits on it.
        TimeoutStartSec = "2h";
      };
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
