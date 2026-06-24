{pkgs, ...}: let
  backupScript = pkgs.writeShellScript "git-auto-backup" ''
    set -euo pipefail

    export HOME="/home/mhugo"
    export GIT_TERMINAL_PROMPT=0

    state_dir="$HOME/.local/state/git-auto-backup"
    log_dir="$state_dir/logs"
    mkdir -p "$log_dir"

    host="$(${pkgs.hostname}/bin/hostname -s 2>/dev/null || echo unknown)"
    stamp="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
    log_file="$log_dir/$stamp.log"

    roots=(
      "$HOME/.dotfiles"
      "$HOME/code"
      "/srv/infra"
    )

    declare -A seen

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
      if ! ${pkgs.git}/bin/git -C "$repo" push --quiet "$remote" "$snapshot_ref:$snapshot_ref"; then
        echo "dirty-backup-snapshot-failed $repo $remote $snapshot_ref $commit"
        rm -f "$tmp_index"
        trap - RETURN
        return 1
      fi
      if ! ${pkgs.git}/bin/git -C "$repo" push --quiet --force "$remote" "$ref:$ref"; then
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

      upstream="$(${pkgs.git}/bin/git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
      if [ -z "$upstream" ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        ${pkgs.git}/bin/git -C "$repo" push --quiet "$remote" "HEAD:$backup_ref"
        echo "head-backup-no-upstream $repo $remote $backup_ref"
        return 0
      fi

      counts="$(${pkgs.git}/bin/git -C "$repo" rev-list --left-right --count "HEAD...$upstream" 2>/dev/null || echo '0 0')"
      local_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $1}')"
      remote_ahead="$(printf '%s\n' "$counts" | ${pkgs.gawk}/bin/awk '{print $2}')"

      if [ "$local_ahead" -gt 0 ] && [ "$remote_ahead" -eq 0 ]; then
        ${pkgs.git}/bin/git -C "$repo" push --quiet "$remote" "HEAD:$branch"
        echo "branch-pushed $repo $remote $branch +$local_ahead"
      elif [ "$local_ahead" -gt 0 ]; then
        backup_ref="refs/backup/$host/$slug/$branch/head"
        ${pkgs.git}/bin/git -C "$repo" push --quiet "$remote" "HEAD:$backup_ref"
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
      if ${pkgs.git}/bin/git -C "$repo" push --quiet "$remote" "HEAD:$branch" 2>/dev/null; then
        echo "mirror-ok $repo $remote $branch"
        return 0
      fi
      backup_ref="refs/backup/$host/$slug/$branch/head"
      if ${pkgs.git}/bin/git -C "$repo" push --quiet --force "$remote" "HEAD:$backup_ref" 2>/dev/null; then
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
        echo "skip-no-remote $repo"
        return 0
      fi

      branch="$(${pkgs.git}/bin/git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
      slug="$(slugify "$repo")"

      ${pkgs.git}/bin/git -C "$repo" fetch --quiet "$remote" || {
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

    {
      echo "git-auto-backup start $stamp host=$host"
      for root in "''${roots[@]}"; do
        [ -e "$root" ] || continue
        if [ -d "$root/.git" ]; then
          handle_repo "$root"
          continue
        fi
        while IFS= read -r gitdir; do
          handle_repo "$(${pkgs.coreutils}/bin/dirname "$gitdir")"
        done < <(${pkgs.findutils}/bin/find "$root" -maxdepth 4 -type d -name .git \
          -not -path '*/node_modules/*' \
          -not -path '*/.sf-test-*/*' \
          -not -path '*/.cache/*' 2>/dev/null)
      done
      echo "git-auto-backup done $(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
    } | tee "$log_file"
  '';
in {
  systemd.user.services.git-auto-backup = {
    Unit = {
      Description = "Back up local Git repositories to their configured remotes";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${backupScript}";
    };
  };

  systemd.user.timers.git-auto-backup = {
    Unit.Description = "Periodically back up local Git repositories";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
      Persistent = true;
      Unit = "git-auto-backup.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
