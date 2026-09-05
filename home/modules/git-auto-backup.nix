{pkgs, ...}: let
  backupScript = pkgs.writeShellScript "git-auto-backup" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    export GIT_TERMINAL_PROMPT=0

    # A single unresponsive remote must not stall the whole sweep. Without
    # keepalives a stalled git-receive-pack hangs forever: on 2026-07-18 the
    # mhugo/dotfiles Forgejo repo stopped answering ref advertisement and,
    # being the first root, blocked backups for all 61 repositories behind it.
    # ConnectTimeout bounds the handshake; ServerAlive* bounds an established
    # session that stops responding (~60s). ControlMaster is disabled so a
    # shared mux socket cannot couple unrelated repositories together.
    export GIT_SSH_COMMAND="ssh -o ControlMaster=no -o ControlPath=none -o ControlPersist=no -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4"

    state_dir="$HOME/.local/state/git-auto-backup"
    log_dir="$state_dir/logs"
    mkdir -p "$log_dir"

    host="$(${pkgs.hostname}/bin/hostname -s 2>/dev/null || echo unknown)"
    stamp="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
    log_file="$log_dir/$stamp.log"

    roots=(
      "$HOME/.dotfiles"
      # Git worktrees of .dotfiles live outside the repo root, so the sweep
      # below never reached them: on 2026-07-25 all 7 codex/* branches there
      # were unmerged and one carried 10 uncommitted files, none backed up.
      "$HOME/.dotfiles-worktrees"
      "$HOME/code"
      "$HOME/backups"
      "$HOME/workspaces"
      "/srv/infra"
    )

    git_net() {
      # Hard bound on any network git call. SSH keepalives are not enough:
      # a server can answer at the transport layer while git-receive-pack /
      # git-upload-pack never completes ref advertisement (observed against
      # mhugo/dotfiles on 2026-07-18), which hangs the process indefinitely.
      ${pkgs.coreutils}/bin/timeout --kill-after=10s 180s ${pkgs.git}/bin/git "$@"
    }

    slugify() {
      printf '%s' "$1" | ${pkgs.gnused}/bin/sed \
        -e "s|^$HOME/||" \
        -e 's|^/||' \
        -e 's|^\.\+||' \
        -e 's|[^A-Za-z0-9._-]|-|g' \
        -e 's|-\\+|-|g'
    }

    repo_remote() {
      local repo="$1"
      if ${pkgs.git}/bin/git -C "$repo" remote get-url origin >/dev/null 2>&1; then
        printf '%s\n' origin
      elif ${pkgs.git}/bin/git -C "$repo" remote get-url forgejo >/dev/null 2>&1; then
        printf '%s\n' forgejo
      else
        return 1
      fi
    }

    push_dirty_ref() {
      local repo="$1" remote="$2" branch="$3" slug="$4"
      local tmp_index tree commit ref snapshot_ref
      tmp_index="$(${pkgs.coreutils}/bin/mktemp "$state_dir/index.XXXXXX")"
      trap 'rm -f "$tmp_index"' RETURN

      GIT_INDEX_FILE="$tmp_index" ${pkgs.git}/bin/git -C "$repo" read-tree HEAD
      GIT_INDEX_FILE="$tmp_index" ${pkgs.git}/bin/git -C "$repo" add -A
      if GIT_INDEX_FILE="$tmp_index" ${pkgs.git}/bin/git -C "$repo" diff-index --cached --quiet HEAD --; then
        rm -f "$tmp_index"
        trap - RETURN
        return 0
      fi

      tree="$(GIT_INDEX_FILE="$tmp_index" ${pkgs.git}/bin/git -C "$repo" write-tree)"
      commit="$(printf 'git-auto-backup dirty snapshot\n\nrepo: %s\nbranch: %s\nhost: %s\ntime: %s\n' \
        "$repo" "$branch" "$host" "$stamp" |
        GIT_INDEX_FILE="$tmp_index" ${pkgs.git}/bin/git -C "$repo" commit-tree "$tree" -p HEAD)"
      ref="refs/backup/$host/$slug/$branch/wip"
      snapshot_ref="refs/backup/$host/$slug/$branch/wip-$stamp"
      ${pkgs.git}/bin/git -C "$repo" update-ref "$ref" "$commit"
      ${pkgs.git}/bin/git -C "$repo" update-ref "$snapshot_ref" "$commit"
      if ! git_net -C "$repo" push --quiet --no-verify "$remote" "$snapshot_ref:$snapshot_ref"; then
        echo "dirty-backup-snapshot-failed $repo $remote $snapshot_ref $commit"
        rm -f "$tmp_index"
        trap - RETURN
        return 1
      fi
      if ! git_net -C "$repo" push --quiet --force --no-verify "$remote" "$ref:$ref"; then
        echo "dirty-backup-latest-failed $repo $remote $ref $commit"
        rm -f "$tmp_index"
        trap - RETURN
        return 1
      fi
      echo "dirty-backup $repo $remote $ref $snapshot_ref $commit"

      rm -f "$tmp_index"
      trap - RETURN
    }

    push_branch_or_backup() {
      local repo="$1" remote="$2" branch="$3" slug="$4"
      local upstream counts local_ahead remote_ahead backup_ref

      # Colocated jj repositories: git's HEAD/index can lag jj's working copy,
      # so a live-branch push here can publish state jj never staged — or
      # silently push nothing while reporting success. Back these up to the
      # refs/backup namespace only and let jj own branch publication.
      if [ -d "$repo/.jj" ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        if git_net -C "$repo" push --quiet --force --no-verify "$remote" "HEAD:$backup_ref"; then
          echo "head-backup-jj $repo $remote $backup_ref"
        else
          echo "head-backup-jj-failed $repo $remote $backup_ref"
        fi
        return 0
      fi

      upstream="$(${pkgs.git}/bin/git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
      if [ -z "$upstream" ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet --no-verify "$remote" "HEAD:$backup_ref"
        echo "head-backup-no-upstream $repo $remote $backup_ref"
        return 0
      fi

      counts="$(${pkgs.git}/bin/git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || echo '0 0')"
      local_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $1}')"
      remote_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $2}')"

      if [ "$local_ahead" -gt 0 ] && [ "$remote_ahead" -eq 0 ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet --force --no-verify "$remote" "HEAD:$backup_ref"
        echo "head-backup-ahead $repo $remote $backup_ref +$local_ahead"
      elif [ "$local_ahead" -gt 0 ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet --no-verify "$remote" "HEAD:$backup_ref"
        echo "head-backup-diverged $repo $remote $backup_ref local+$local_ahead remote+$remote_ahead"
      else
        echo "branch-current $repo $upstream"
      fi
    }

    mirror_branch_to_remote() {
      # Mirror the committed branch HEAD to an additional remote (e.g. the public
      # github mirror alongside the private forgejo origin). Branch history only;
      # callers do NOT send dirty WIP snapshots here. Best-effort and non-fatal:
      # on divergence we stash a force-pushed backup ref instead of the branch.
      local repo="$1" remote="$2" branch="$3" slug="$4" backup_ref
      [ "$branch" = "detached" ] && return 0
      # Same jj reasoning as push_branch_or_backup: never mirror a live branch
      # out of a colocated jj repo.
      if [ -d "$repo/.jj" ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet --force --no-verify "$remote" "HEAD:$backup_ref" 2>/dev/null &&
          echo "mirror-jj-backup $repo $remote $backup_ref" ||
          echo "mirror-jj-failed $repo $remote $backup_ref"
        return 0
      fi
      backup_ref="refs/backup/$host/$slug/$branch/head"
      if git_net -C "$repo" push --quiet --force --no-verify "$remote" "HEAD:$backup_ref" 2>/dev/null; then
        echo "mirror-diverged-backup $repo $remote $backup_ref"
        return 0
      fi
      echo "mirror-push-failed $repo $remote $branch"
      return 1
    }

    handle_repo() {
      # Runs in a parallel xargs worker (one repo per process), so the old
      # `seen` dedup map cannot live here: it is not exportable between
      # processes. Dedup moved to add_repo during serial sweep generation.
      # State is line-oriented: workers echo status lines, the parent
      # aggregates counters and no-remote.current afterwards. Anything this
      # function mutates beyond stdout is lost with the worker process.
      local repo="$1" remote branch slug dirty
      repo="$(${pkgs.git}/bin/git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
      [ -n "$repo" ] || return 0

      remote="$(repo_remote "$repo" || true)"
      if [ -z "$remote" ]; then
        # A repository with no remote is not "nothing to do" — it is the only
        # unrecoverable state this sweep can encounter. ~/code/jcode-custom sat
        # here for weeks: 210 MB, one local commit, 118 uncommitted files, and a
        # silent skip-no-remote line every 15 minutes that nobody read. Counted
        # and re-listed in the run summary so it cannot hide again.
        echo "skip-no-remote $repo"
        return 0
      fi

      branch="$(${pkgs.git}/bin/git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
      slug="$(slugify "$repo")"

      git_net -C "$repo" fetch --quiet "$remote" || {
        echo "fetch-failed $repo $remote"
        return 0
      }

      push_branch_or_backup "$repo" "$remote" "$branch" "$slug" || echo "branch-backup-failed $repo"

      dirty="$(${pkgs.git}/bin/git -C "$repo" status --porcelain | ${pkgs.gawk}/bin/awk 'END {print NR + 0}')"
      if [ "$dirty" -gt 0 ]; then
        push_dirty_ref "$repo" "$remote" "$branch" "$slug" || echo "dirty-backup-failed $repo"
      fi

      # Always keep the committed branch on every configured remote — e.g. the
      # public github mirror alongside the primary forgejo/origin. Dirty WIP
      # snapshots above stay on the primary only (not leaked to public mirrors).
      while IFS= read -r other; do
        [ -n "$other" ] || continue
        [ "$other" = "$remote" ] && continue
        # 'upstream' by convention is a third-party repo you forked and cannot
        # push to — skip it so we don't retry a guaranteed failure every run.
        [ "$other" = "upstream" ] && continue
        mirror_branch_to_remote "$repo" "$other" "$branch" "$slug" || echo "mirror-failed $repo $other"
      done < <(${pkgs.git}/bin/git -C "$repo" remote)
    }

    handle_jj_workspace() {
      # jj workspaces carry only .jj — no .git — so the git sweep below cannot
      # see them at all. On 2026-07-25 that hid 27 workspaces across infra,
      # singularity-engine and centralcloud, each holding a commit that existed
      # nowhere but this disk. All of these repos are colocated, so jj has
      # already exported the working-copy commit into the git object store;
      # pushing that object id by hash is enough to make it durable.
      #
      # Best-effort by design: this backs work up, it does not publish it.
      # Branch publication stays with jj and the repo's own vcs facade.
      local ws="$1" repo remote slug wsname commit
      repo="$(${pkgs.jujutsu}/bin/jj --ignore-working-copy -R "$ws" workspace root --name default 2>/dev/null || true)"
      [ -n "$repo" ] || repo="$ws"
      [ -d "$repo/.git" ] || return 0

      # The default checkout is already covered by push_branch_or_backup's
      # colocated-jj branch. Without this guard the sweep re-pushes every repo
      # root a second time: 87 workspaces instead of the ~28 that are actually
      # additional, on a run that already overruns its 15-minute interval.
      [ "$ws" != "$repo" ] || return 0

      remote="$(repo_remote "$repo" || true)"
      [ -n "$remote" ] || { echo "jj-ws-skip-no-remote $ws"; return 0; }

      # --ignore-working-copy is required, not an optimisation. A plain jj read
      # snapshots the working copy first, which writes a commit and an op-log
      # entry into a repo someone may be actively using -- on a timer, every 15
      # minutes, including /srv/infra where only one workspace per owner may be
      # active. Reading the last-known @ is accurate whenever anyone is working
      # and costs nothing when nobody is.
      commit="$(${pkgs.jujutsu}/bin/jj --ignore-working-copy -R "$ws" log --no-graph -r @ -T 'commit_id' 2>/dev/null || true)"
      [ -n "$commit" ] || { echo "jj-ws-no-commit $ws"; return 0; }

      ${pkgs.git}/bin/git -C "$repo" cat-file -e "$commit" 2>/dev/null || {
        echo "jj-ws-not-exported $ws $commit"
        return 0
      }

      wsname="$(${pkgs.coreutils}/bin/basename "$ws")"
      slug="$(slugify "$repo")"
      # --no-verify: a refs/backup snapshot is not a publication. Without it
      # every workspace push drags in the repo's pre-push gate -- for /srv/infra
      # that is infra-pre-push running kubeconform, digest contracts and tests,
      # which pushed a run that used to take 15-19 minutes past its 20-minute
      # TimeoutStartSec and got it killed mid-sweep. Those gates guard what
      # lands on a branch; they have no bearing on whether a snapshot is durable.
      if git_net -C "$repo" push --quiet --force --no-verify "$remote" \
        "$commit:refs/backup/$host/$slug/workspace-$wsname/wip"; then
        echo "jj-ws-backup $ws $remote $commit"
      else
        echo "jj-ws-backup-failed $ws $remote $commit"
      fi
    }

    # The sweep's cost is per-repo network I/O: ~140 repositories, each with
    # 180s-bounded fetch/push calls, ran fully serial and took 15-19 minutes --
    # longer than the 15-minute timer interval. Generation below stays serial
    # (local-only git/find reads, milliseconds each) and the network-bound
    # handle_repo / handle_jj_workspace calls fan out through xargs -P, one
    # repository per worker process for load balancing. Counters and
    # no-remote.current are derived from the aggregated worker output, since
    # anything a worker mutates dies with its process.
    # Backups protect durability but must remain subordinate to the interactive
    # operator workload on this shared host.
    jobs=2
    run_out="$(${pkgs.coreutils}/bin/mktemp "$state_dir/run-output.XXXXXX")"
    trap 'rm -f "$run_out"' EXIT

    repos=()
    jj_workspaces=()
    declare -A listed
    add_repo() {
      local top
      top="$(${pkgs.git}/bin/git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)"
      [ -n "$top" ] || return 0
      [ -z "''${listed[$top]+x}" ] || return 0
      listed[$top]=1
      repos+=("$top")
    }

    for root in "''${roots[@]}"; do
      [ -e "$root" ] || continue
      if [ -d "$root/.git" ]; then
        add_repo "$root"
        continue
      fi
      # -name .git without -type d: a git worktree's .git is a regular FILE,
      # so the old -type d filter silently skipped every worktree it found.
      # maxdepth 6, not 4: ~/code/worktrees/jj/<repo>/<workspace> sits at
      # depth 5, one level past where the old sweep stopped looking.
      # -prune, not -not -path: a -not -path clause only filters the RESULT,
      # find still descends the whole tree. Measured over ~/code, pruning cuts
      # the walk from 2300ms to 104ms -- it matters because maxdepth 6 now
      # reaches into build trees the old maxdepth 4 never touched.
      while IFS= read -r gitdir; do
        add_repo "$(${pkgs.coreutils}/bin/dirname "$gitdir")"
      done < <(${pkgs.findutils}/bin/find "$root" -maxdepth 6 \
        \( -name node_modules -o -name target -o -name .direnv -o -name .cache \
           -o -name '.sf-test-*' \) -prune -o \
        -name .git -print 2>/dev/null)

      while IFS= read -r jjdir; do
        jj_workspaces+=("$(${pkgs.coreutils}/bin/dirname "$jjdir")")
      done < <(${pkgs.findutils}/bin/find "$root" -maxdepth 6 \
        \( -name node_modules -o -name target -o -name .direnv -o -name .cache \) \
        -prune -o -type d -name .jj -print 2>/dev/null)
    done

    # xargs spawns fresh bash processes; exported functions arrive through the
    # BASH_FUNC_* environment. All pkgs.* paths inside the functions are
    # absolute store paths baked in at eval time, so nothing else is needed.
    export -f git_net slugify repo_remote push_dirty_ref push_branch_or_backup \
      mirror_branch_to_remote handle_repo handle_jj_workspace
    export host stamp state_dir

    {
      echo "git-auto-backup start $stamp host=$host"
      if ((''${#repos[@]})); then
        printf '%s\0' "''${repos[@]}" | ${pkgs.findutils}/bin/xargs -0 -r -P "$jobs" -n 1 \
          ${pkgs.bash}/bin/bash -c 'handle_repo "$1"' _ >> "$run_out" 2>&1 || true
      fi
      if ((''${#jj_workspaces[@]})); then
        printf '%s\0' "''${jj_workspaces[@]}" | ${pkgs.findutils}/bin/xargs -0 -r -P "$jobs" -n 1 \
          ${pkgs.bash}/bin/bash -c 'handle_jj_workspace "$1"' _ >> "$run_out" 2>&1 || true
      fi
      ${pkgs.coreutils}/bin/cat "$run_out"

      # Aggregate worker output into the same state the serial sweep kept:
      # no-remote.current holds the current standing-risk list (refreshed per
      # completed run, so a killed run now leaves the previous list instead of
      # an empty file), and the summary counters come from the status lines.
      ${pkgs.gnugrep}/bin/grep '^skip-no-remote ' "$run_out" |
        ${pkgs.coreutils}/bin/cut -d' ' -f2- > "$state_dir/no-remote.current" || true
      n_skip_no_remote=$(${pkgs.gnugrep}/bin/grep -c '^skip-no-remote ' "$run_out" || true)
      n_failed=$(${pkgs.gnugrep}/bin/grep -cE '^jj-ws-(no-commit|not-exported|backup-failed) ' "$run_out" || true)
      n_jj_ws=$(${pkgs.gnugrep}/bin/grep -c '^jj-ws-backup ' "$run_out" || true)

      # The summary exists because the per-repo lines above scroll past unread.
      # A repository with no remote is a standing data-loss risk, not an event;
      # it must be visible in the last line of every run, not only the first
      # run that introduced it.
      echo "git-auto-backup summary no-remote=$n_skip_no_remote failures=$n_failed jj-workspaces=$n_jj_ws"
      if [ "$n_skip_no_remote" -gt 0 ]; then
        echo "git-auto-backup UNPROTECTED (no remote configured):"
        ${pkgs.gnused}/bin/sed 's|^|  |' "$state_dir/no-remote.current"
      fi
      echo "git-auto-backup done $(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
    } | tee "$log_file"
  '';

  serializedBackupScript = pkgs.writeShellScript "git-auto-backup-serialized" ''
    set -euo pipefail
    lock="''${XDG_RUNTIME_DIR:-/run/user/$UID}/home-mutable-workspace-sweep.lock"
    echo "git-auto-backup waiting for mutable sweep lock: $lock"
    ${pkgs.util-linux}/bin/flock --exclusive --wait 21600 --conflict-exit-code 75 \
      "$lock" ${pkgs.coreutils}/bin/timeout --kill-after=10s 45m ${backupScript} || {
      status=$?
      echo "git-auto-backup mutable sweep lock unavailable or backup failed: status=$status lock=$lock" >&2
      exit "$status"
    }
  '';

  workspaceLedgerScript = pkgs.writeShellScript "workspace-ledger-snapshot" ''
    set -euo pipefail
    # Must track the Engine operator's SE_LOCK_ROOT default exactly (see
    # tools/repository-operator/src/env.rs::resolve_lease_root /
    # lib/se_vcs.sh:255 in singularity-engine): SE_LOCK_ROOT override, else
    # XDG_STATE_HOME, else $HOME/.local/state. Also back up the pre-migration
    # /tmp/singularity-engine root while it can still exist, so the ledger
    # keeps protecting whichever root the live lease data is actually under
    # during the transition.
    lease_root="''${SE_LOCK_ROOT:-''${XDG_STATE_HOME:-$HOME/.local/state}/singularity-engine}/workspace-leases"
    legacy_lease_root="/tmp/singularity-engine/workspace-leases"
    ledger_dir="$HOME/.local/state/workspace-ledger/records"
    synced=false
    if [ -d "$lease_root" ] || [ -d "$legacy_lease_root" ]; then
      ${pkgs.coreutils}/bin/mkdir -p "$ledger_dir"
    fi
    if [ -d "$lease_root" ]; then
      ${pkgs.rsync}/bin/rsync -a "$lease_root/" "$ledger_dir/"
      synced=true
    fi
    if [ -d "$legacy_lease_root" ]; then
      ${pkgs.rsync}/bin/rsync -a "$legacy_lease_root/" "$ledger_dir/"
      synced=true
    fi
    [ "$synced" = true ] || exit 0
  '';
in {
  systemd.user = {
    services.git-auto-backup = {
      Unit = {
        Description = "Back up local Git repositories to their configured remotes";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
        # Repository sweeps are timer-owned and can take minutes. Do not start or
        # wait for one merely because Home Manager switched generations.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${serializedBackupScript}";
        # Backstop for anything the SSH keepalives cannot bound (a wedged local
        # git process, a stalled HTTPS remote). A run that cannot finish inside
        # this window is failing, not working; kill it so the next tick is clean.
        #
        # Raised from 20min on 2026-07-25: coverage grew from 79 to 110 git repos
        # plus ~28 jj workspaces, and a killed run is strictly worse than a slow
        # one -- it leaves the tail of the sweep unbacked while reporting nothing.
        # The per-call `timeout 180s` in git_net still bounds any single hang, so
        # this only widens the total, it does not weaken the stall protection.
        # The lock may be held by a full-home Borg sweep. Bound that wait in
        # the wrapper, then independently bound the actual Git backup to 45m.
        TimeoutStartSec = "7h";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUWeight = 10;
        IOWeight = 10;
        MemoryHigh = "8G";
        MemoryMax = "12G";
      };
    };

    timers.git-auto-backup = {
      Unit.Description = "Periodically back up local Git repositories";
      Timer = {
        # Arm relative to timer activation, not boot: OnBootSec can already be
        # expired when Home Manager starts the timer and then provides no first
        # service anchor. After that first run, wait a full interval after each
        # completed sweep so long runs cannot create catch-up loops.
        OnActiveSec = "5m";
        OnUnitInactiveSec = "15m";
        Unit = "git-auto-backup.service";
      };
      Install.WantedBy = ["timers.target"];
    };

    services.workspace-ledger-snapshot = {
      Unit.Description = "Preserve workspace ownership ledger outside volatile storage";
      Service = {
        Type = "oneshot";
        ExecStart = "${workspaceLedgerScript}";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUWeight = 10;
        IOWeight = 10;
      };
    };

    timers.workspace-ledger-snapshot = {
      Unit.Description = "Hourly workspace ownership ledger preservation";
      Timer = {
        # Snapshot soon after activation, then one hour after each completion.
        # A wall-clock daily run could race systemd-tmpfiles-clean and preserve
        # an already-pruned ledger.
        OnActiveSec = "10m";
        OnUnitInactiveSec = "1h";
        Unit = "workspace-ledger-snapshot.service";
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
