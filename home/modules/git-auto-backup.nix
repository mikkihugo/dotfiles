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
      "$HOME/workspaces"
      "/srv/infra"
    )

    declare -A seen
    declare -i n_skip_no_remote=0 n_failed=0 n_jj_ws=0

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
      if ! git_net -C "$repo" push --quiet "$remote" "$snapshot_ref:$snapshot_ref"; then
        echo "dirty-backup-snapshot-failed $repo $remote $snapshot_ref $commit"
        rm -f "$tmp_index"
        trap - RETURN
        return 1
      fi
      if ! git_net -C "$repo" push --quiet --force "$remote" "$ref:$ref"; then
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
        if git_net -C "$repo" push --quiet --force "$remote" "HEAD:$backup_ref"; then
          echo "head-backup-jj $repo $remote $backup_ref"
        else
          echo "head-backup-jj-failed $repo $remote $backup_ref"
        fi
        return 0
      fi

      upstream="$(${pkgs.git}/bin/git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
      if [ -z "$upstream" ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet "$remote" "HEAD:$backup_ref"
        echo "head-backup-no-upstream $repo $remote $backup_ref"
        return 0
      fi

      counts="$(${pkgs.git}/bin/git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || echo '0 0')"
      local_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $1}')"
      remote_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $2}')"

      if [ "$local_ahead" -gt 0 ] && [ "$remote_ahead" -eq 0 ]; then
        git_net -C "$repo" push --quiet "$remote" "HEAD:$branch"
        echo "branch-pushed $repo $remote $branch +$local_ahead"
      elif [ "$local_ahead" -gt 0 ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        git_net -C "$repo" push --quiet "$remote" "HEAD:$backup_ref"
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
        git_net -C "$repo" push --quiet --force "$remote" "HEAD:$backup_ref" 2>/dev/null &&
          echo "mirror-jj-backup $repo $remote $backup_ref" ||
          echo "mirror-jj-failed $repo $remote $backup_ref"
        return 0
      fi
      if git_net -C "$repo" push --quiet "$remote" "HEAD:$branch" 2>/dev/null; then
        echo "mirror-ok $repo $remote $branch"
        return 0
      fi
      backup_ref="refs/backup/$host/$slug/$branch/head"
      if git_net -C "$repo" push --quiet --force "$remote" "HEAD:$backup_ref" 2>/dev/null; then
        echo "mirror-diverged-backup $repo $remote $backup_ref"
        return 0
      fi
      echo "mirror-push-failed $repo $remote $branch"
      return 1
    }

    handle_repo() {
      local repo="$1" remote branch slug dirty
      repo="$(${pkgs.git}/bin/git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
      [ -n "$repo" ] || return 0
      [ -z "''${seen[$repo]+x}" ] || return 0
      seen[$repo]=1

      remote="$(repo_remote "$repo" || true)"
      if [ -z "$remote" ]; then
        # A repository with no remote is not "nothing to do" — it is the only
        # unrecoverable state this sweep can encounter. ~/code/jcode-custom sat
        # here for weeks: 210 MB, one local commit, 118 uncommitted files, and a
        # silent skip-no-remote line every 15 minutes that nobody read. Counted
        # and re-listed in the run summary so it cannot hide again.
        echo "skip-no-remote $repo"
        n_skip_no_remote+=1
        printf '%s\n' "$repo" >> "$state_dir/no-remote.current"
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
      [ -n "$commit" ] || { echo "jj-ws-no-commit $ws"; n_failed+=1; return 0; }

      ${pkgs.git}/bin/git -C "$repo" cat-file -e "$commit" 2>/dev/null || {
        echo "jj-ws-not-exported $ws $commit"
        n_failed+=1
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
        n_jj_ws+=1
      else
        echo "jj-ws-backup-failed $ws $remote $commit"
        n_failed+=1
      fi
    }

    {
      echo "git-auto-backup start $stamp host=$host"
      : > "$state_dir/no-remote.current"
      for root in "''${roots[@]}"; do
        [ -e "$root" ] || continue
        if [ -d "$root/.git" ]; then
          handle_repo "$root"
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
          handle_repo "$(${pkgs.coreutils}/bin/dirname "$gitdir")"
        done < <(${pkgs.findutils}/bin/find "$root" -maxdepth 6 \
          \( -name node_modules -o -name target -o -name .direnv -o -name .cache \
             -o -name '.sf-test-*' \) -prune -o \
          -name .git -print 2>/dev/null)

        while IFS= read -r jjdir; do
          handle_jj_workspace "$(${pkgs.coreutils}/bin/dirname "$jjdir")"
        done < <(${pkgs.findutils}/bin/find "$root" -maxdepth 6 \
          \( -name node_modules -o -name target -o -name .direnv -o -name .cache \) \
          -prune -o -type d -name .jj -print 2>/dev/null)
      done

      # The summary exists because the per-repo lines above scroll past unread.
      # A repository with no remote is a standing data-loss risk, not an event;
      # it must be visible in the last line of every run, not only the first
      # run that introduced it.
      # Workspace debt. The SessionEnd hook reports what a session leaves
      # behind, but it cannot fire on a crash or kill -9 -- and on 2026-07-25
      # singularity-engine held 219 task records against 12 live leases, so the
      # ungraceful exit is the common case, not the edge case. This sweep is
      # already running every 15 minutes; counting the leaseless over-age
      # workspaces here costs a directory read and closes that gap.
      #
      # Report only. Nothing here closes or deletes a workspace: deciding one is
      # finished needs to know whether its work landed, which this cannot tell.
      lease_root="''${SE_LOCK_ROOT:-/tmp/singularity-engine}/workspace-leases"
      if [ -d "$lease_root" ]; then
        now_epoch=$(${pkgs.coreutils}/bin/date +%s)
        n_ws_total=0; n_ws_leased=0; n_ws_overage=0
        for task in "$lease_root"/*.task; do
          [ -e "$task" ] || continue
          n_ws_total=$((n_ws_total + 1))
          name="$(${pkgs.coreutils}/bin/basename "$task" .task)"
          if [ -e "$lease_root/$name.lease" ]; then
            n_ws_leased=$((n_ws_leased + 1))
            continue
          fi
          # Field order fixed by scripts/se_task.sh; 6=max_hours, 7=started_epoch.
          mh=$(${pkgs.gawk}/bin/awk -F'\t' '{print $6}' "$task" 2>/dev/null)
          st=$(${pkgs.gawk}/bin/awk -F'\t' '{print $7}' "$task" 2>/dev/null)
          # Both fields must be present and purely numeric. Written as two
          # checks rather than one case with an empty-string branch, because a
          # doubled single-quote inside a Nix indented string opens an escape
          # sequence instead of matching the empty string.
          [ -n "$mh" ] && [ -n "$st" ] || continue
          case "$mh$st" in *[!0-9]*) continue;; esac
          [ "$mh" -gt 0 ] || continue
          [ $(( (now_epoch - st) / 3600 )) -gt "$mh" ] && n_ws_overage=$((n_ws_overage + 1))
        done
        echo "workspace-debt total=$n_ws_total leased=$n_ws_leased overage-no-lease=$n_ws_overage"

        # Preserve the ledger. It is the ONLY record of which agent owns which
        # workspace (task_owner_ref: cursor:/claude:/kimi:/goose:/jcode:) and it
        # lives under /tmp, where systemd-tmpfiles-clean.timer runs daily. On
        # 2026-07-25 the oldest surviving record was 3 days old although the
        # workspaces themselves go back weeks -- attribution was already being
        # deleted on a timer, silently.
        #
        # Deliberately NOT fixed by setting SE_LOCK_ROOT here: the engine's own
        # contract test (scripts/tests/se_vcs_contract_test.sh) requires that
        # root to be "one shared, env-independent path across all agents", and a
        # home-manager session variable reaches only shell-launched clients. A
        # partially-inherited value would split the ledger across two roots,
        # which is worse than one volatile root. The real fix is the default in
        # se_task.sh, which needs a leased engine workspace to change.
        #
        # This copy is a snapshot, never a source: nothing reads it back.
        #
        # ACCUMULATING, not mirroring. No --delete: the whole point is to keep
        # records that tmpfiles has already removed from the live root. A
        # mirroring sync would faithfully reproduce the deletion it exists to
        # survive.
        ledger_dir="$HOME/.local/state/workspace-ledger/records"
        ${pkgs.coreutils}/bin/mkdir -p "$ledger_dir"
        if ${pkgs.rsync}/bin/rsync -a "$lease_root/" "$ledger_dir/" 2>/dev/null; then
          kept=$(${pkgs.findutils}/bin/find "$ledger_dir" -name '*.task' 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
          echo "workspace-ledger-snapshot $ledger_dir live=$n_ws_total preserved=$kept"
        else
          echo "workspace-ledger-snapshot-failed $lease_root"
        fi
      fi

      echo "git-auto-backup summary no-remote=$n_skip_no_remote failures=$n_failed jj-workspaces=$n_jj_ws"
      if [ "$n_skip_no_remote" -gt 0 ]; then
        echo "git-auto-backup UNPROTECTED (no remote configured):"
        ${pkgs.gnused}/bin/sed 's|^|  |' "$state_dir/no-remote.current"
      fi
      echo "git-auto-backup done $(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
    } | tee "$log_file"
  '';
in {
  systemd.user.services.git-auto-backup = {
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
      ExecStart = "${backupScript}";
      # Backstop for anything the SSH keepalives cannot bound (a wedged local
      # git process, a stalled HTTPS remote). A run that cannot finish inside
      # this window is failing, not working; kill it so the next tick is clean.
      #
      # Raised from 20min on 2026-07-25: coverage grew from 79 to 110 git repos
      # plus ~28 jj workspaces, and a killed run is strictly worse than a slow
      # one -- it leaves the tail of the sweep unbacked while reporting nothing.
      # The per-call `timeout 180s` in git_net still bounds any single hang, so
      # this only widens the total, it does not weaken the stall protection.
      TimeoutStartSec = "45min";
    };
  };

  systemd.user.timers.git-auto-backup = {
    Unit.Description = "Periodically back up local Git repositories";
    Timer = {
      # Wall-clock schedule, not monotonic anchors. OnBootSec/OnUnitActiveSec
      # left this timer permanently unarmed after the 2026-07-01 reboot: the
      # timer started 79min after boot (past the OnBootSec window), and
      # OnUnitActiveSec had no anchor because the service never ran that boot,
      # so next_elapse resolved to infinity and backups silently stopped for
      # 19 days. Persistent= only ever applied to OnCalendar, so it could not
      # rescue the monotonic form; with OnCalendar it does catch up after
      # downtime.
      OnCalendar = "*:0/15";
      Persistent = true;
      Unit = "git-auto-backup.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
