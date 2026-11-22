# devshell-prewarm.nix — warm the canonical dev-shell caches (devbox only)
#
# The operator asked for warm dev shells ("a worktree dont need cold eval")
# without the I/O storms the earlier prewarm attempts caused ("direnv-instant
# prewarm and alternatives as this here is giving issues"). Three rules keep
# both promises:
#
#   * I/O pressure gate — when /proc/pressure/io reports "some avg10" above the
#     threshold the box is already thrashing on I/O, and a cold flake
#     evaluation now would add to the stall. The cycle is skipped, not queued:
#     ExecCondition makes systemd skip the unit cleanly (Result=success).
#   * Low priority — nice 19 and idle I/O scheduling, so a prewarm never
#     competes with the shell that asked for it.
#   * Every 30 minutes and at session start.
#
# What it warms: the three canonical checkouts, by running their .envrc once
# through `direnv exec`. nix-direnv then has a cached profile in the layout
# dir, so the first `cd` into that root does not pay a cold evaluation.
#
# What it deliberately does NOT do: publish the agent-shell dumps. That is the
# infra-owned system unit devshell-prewarm.service
# (hosts/cc-se-sto-devbox-01/etc/nixos/devshell-prewarm.nix), which owns the
# shared-dump format, the fleet evaluation lock and the store paths. A second
# producer for the same artifact would double the I/O this unit exists to
# avoid. Same name, different scope: this one is `systemctl --user`, that one
# is `systemctl`.
#
# ponytail: the per-root loop is bash generated into the nix store, not a repo
# script, and it shells out to `direnv exec` because no engine-owned prewarm
# verb exists yet. Replace the loop with the Engine operator's prewarm verb
# (Engine task #12) when that lands; the gate, the scheduling and the timer
# stay as they are.
{
  pkgs,
  lib,
  hostname ? "",
  ...
}: let
  onDevbox = lib.toLower hostname == "cc-se-sto-devbox-01";

  # Canonical primaries, not worktrees: a worktree's flake bytes differ, so a
  # warm primary says nothing about a worktree.
  roots = [
    "/home/mhugo/code/singularity-engine"
    "/home/mhugo/code/jcode"
    "/srv/infra"
  ];

  # NixOS owns nix and direnv on this host (/run/current-system/sw); home
  # manager's own copies are not installed for the devbox profile and a user
  # unit does not inherit an interactive PATH.
  systemBin = "/run/current-system/sw/bin";

  binPath = lib.makeBinPath [pkgs.coreutils pkgs.bash];

  # I/O pressure gate. Exit 0 runs the cycle, exit 1 skips it. The "some"
  # line is the primary PSI signal (share of time at least one task was
  # stalled on I/O); "full" is the stricter subset where every task was.
  # Fail closed: an unreadable /proc/pressure/io skips the cycle rather than
  # piling an evaluation onto a box whose I/O state is unknown.
  ioGate = lib.removeSuffix "\n" ''
    ${pkgs.gawk}/bin/awk 'BEGIN{while((getline l<"/proc/pressure/io")>0){if(l~/^some avg10=/){split(l,a," ");split(a[2],k,"=");v=k[2]+0;exit(v<=${toString ioPressureAvg10Max})?0:1}}exit 1}'
  '';

  # Above this average the box is already I/O bound.
  ioPressureAvg10Max = 40;

  # Per-root evaluation budget, matching the infra producer's
  # PREWARM_ROOT_TIMEOUT_SECONDS default, so one slow root cannot eat the
  # whole unit budget.
  rootTimeoutSeconds = 900;

  prewarm = pkgs.writeShellScriptBin "devshell-prewarm-run" ''
    set -u
    PATH="${systemBin}:${binPath}"
    export PATH
    direnv_bin="${systemBin}/direnv"
    timeout_bin="${pkgs.coreutils}/bin/timeout"

    failed=0
    total=0
    for root in ${lib.concatStringsSep " " roots}; do
      total=$((total + 1))
      start=$(date +%s)
      if out=$("$timeout_bin" --kill-after=30s ${toString rootTimeoutSeconds} "$direnv_bin" exec "$root" true 2>&1); then
        echo "devshell-prewarm: root=$root outcome=warmed duration_seconds=$(( $(date +%s) - start ))"
      else
        rc=$?
        failed=$((failed + 1))
        echo "devshell-prewarm: root=$root outcome=failed rc=$rc duration_seconds=$(( $(date +%s) - start ))"
        printf '%s\n' "$out" | sed 's/^/devshell-prewarm: /' >&2
      fi
    done

    if [ "$failed" -eq "$total" ]; then
      echo "devshell-prewarm: every root failed ($failed/$total)" >&2
      exit 1
    fi
    exit 0
  '';
in
  lib.mkIf onDevbox {
    systemd.user.services.devshell-prewarm = {
      Unit = {
        Description = "Warm the canonical dev-shell caches (Engine, JCode, Infra)";
        # House pattern (see modules/stable-shell.nix): start at session start.
        After = ["default.target"];
      };
      Service = {
        Type = "oneshot";
        ExecCondition = ioGate;
        ExecStart = "${prewarm}/bin/devshell-prewarm-run";
        Environment = [
          "PATH=${binPath}"
          "HOME=%h"
          "XDG_RUNTIME_DIR=%t"
          "XDG_CACHE_HOME=%h/.cache"
          # The devbox keeps the live direnvrc (nix-direnv 3.2.0 and the shared
          # dump reader) in /etc/direnv. The user manager does not inherit
          # DIRENV_CONFIG, so state it here or direnv finds no nix-direnv at all.
          "DIRENV_CONFIG=/etc/direnv"
          # No shell rc: this unit must not pick up the interactive direnv hook.
          "BASH_ENV=/dev/null"
        ];
        # Never let the prewarm compete for the I/O it exists to protect.
        IOSchedulingClass = "idle";
        Nice = 19;
        TimeoutStartSec = "3h";
        WorkingDirectory = "/tmp";
      };
      Install.WantedBy = ["default.target"];
    };

    systemd.user.timers.devshell-prewarm = {
      Unit.Description = "Warm the canonical dev shells every 30 minutes";
      Timer = {
        OnBootSec = "2min";
        OnUnitActiveSec = "30min";
        Persistent = true;
        Unit = "devshell-prewarm.service";
      };
      Install.WantedBy = ["timers.target"];
    };
  }