# cargo-target-prune.nix — schedule jcode's pool-key pruning (operator
# directive 2026-10-27: "repo cleanup from engine should find the ones we
# don't find"): the per-toolchain cargo target pool accretes a new ~5-20 GiB
# key per lockfile change and nothing removed the old ones — 154 GB observed
# on this devbox (jcode#540) and 86 GB of dead keys on the jcode CI runner in
# 7 days (2026-10-27, cleared by hand while the runner was idle).
#
# Also sweeps in-tree `target/` leftovers under the jj worktree pools. Engine,
# jcode, and infra already export workspace-keyed CARGO_TARGET_DIR under
# XDG_CACHE_HOME from their direnv/flake shells; bare `cargo` without that
# shell still writes ./target and re-fills backups/disk (96 GiB cleared
# 2026-10-31 on Engine lanes alone). Reuse jcode's --worktrees-root mode
# rather than a second pruner.
#
# Daily prune, niced: jcode's own prune-cargo-target.sh (dry-run by default;
# --apply here), 3-day freshness floor, in-use detection built in. Fails open:
# a failed prune leaves the next cycle to catch it.
{pkgs, ...}: let
  prune = "$HOME/code/jcode/scripts/prune-cargo-target.sh";
  # One shell so pool + worktree roots share the same nice/ionice and so a
  # missing worktree pool (repo not checked out) cannot abort the pool prune.
  start = pkgs.writeShellScript "cargo-target-prune" ''
    set -u
    export DIRENV_DISABLE=1
    run() {
      ${pkgs.bash}/bin/bash ${prune} "$@" 2>&1 | tail -5
    }
    run --apply --days 3
    for root in \
      "$HOME/code/worktrees/jj/jcode" \
      "$HOME/code/worktrees/jj/singularity-engine" \
      "$HOME/code/worktrees/jj/infra"
    do
      if [ -d "$root" ]; then
        run --worktrees-root "$root" --apply --days 3 || true
      fi
    done
  '';
in {
  systemd.user.services.cargo-target-prune = {
    Unit.Description = "Prune stale jcode cargo-target pool keys and in-tree worktree target/ leftovers (jcode#540)";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'nice -n19 ionice -c3 ${start}'";
      WorkingDirectory = "%h/code/jcode";
    };
  };
  systemd.user.timers.cargo-target-prune = {
    Unit.Description = "Daily cargo-target pool + worktree leftover prune";
    Timer = {
      OnCalendar = "*-*-* 03:37:00"; # off-herd; after the daily eval churn
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
