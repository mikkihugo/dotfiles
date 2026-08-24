#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/refuse" "$tmp/pinned"
printf '#!/usr/bin/env bash\nexit 126\n' >"$tmp/refuse/git"
printf '#!/usr/bin/env bash\nprintf "pinned-git %%s\\n" "$*"\n' >"$tmp/pinned/git"
chmod 0755 "$tmp/refuse/git" "$tmp/pinned/git"

actual="$({ PATH="$tmp/refuse:$PATH" SE_GIT_BIN="$tmp/pinned/git" "$root/scripts/repo-vcs.sh" status; } 2>&1)"
[[ "$actual" == "pinned-git -C $root status" ]] || {
	printf 'facade did not use pinned SE_GIT_BIN: %s\n' "$actual" >&2
	exit 1
}
help_log="$tmp/describe-help.log"
mkdir -p "$tmp/record"
cat >"$tmp/record/git" <<'RECORD_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DESCRIBE_HELP_LOG"
RECORD_GIT
chmod 0755 "$tmp/record/git"
if ! DESCRIBE_HELP_LOG="$help_log" SE_GIT_BIN="$tmp/record/git" "$root/bin/repo" vcs describe --help >"$tmp/describe-help.out" 2>"$tmp/describe-help.err"; then
	printf 'repo vcs describe --help must succeed without invoking Git\n' >&2
	cat "$tmp/describe-help.err" >&2
	exit 1
fi
grep -Fxq 'usage: repo vcs describe <message>' "$tmp/describe-help.out"
[[ ! -s "$help_log" ]] || {
	printf 'repo vcs describe --help unexpectedly invoked Git\n' >&2
	exit 1
}

amend_log="$tmp/amend.log"
mkdir -p "$tmp/amend"
cat >"$tmp/amend/git" <<'AMEND_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AMEND_LOG"
if [[ "$*" == *'merge-base --is-ancestor HEAD origin/main'* ]]; then
	exit 1
fi
if [[ "$*" == *'symbolic-ref --quiet --short HEAD'* ]]; then
	printf '%s\n' codex/test
fi
if [[ "$*" == *'for-each-ref --contains HEAD --format=%(refname) refs/remotes/origin'* ]] && [[ "${REMOTE_CONTAINS_HEAD:-}" == 1 ]]; then
	printf '%s\n' refs/remotes/origin/codex/test
fi
AMEND_GIT
chmod 0755 "$tmp/amend/git"
if ! AMEND_LOG="$amend_log" SE_GIT_BIN="$tmp/amend/git" "$root/bin/repo" vcs amend 'fix(vcs): safe help' >"$tmp/amend.out" 2>"$tmp/amend.err"; then
	printf 'repo vcs amend must correct an unpushed task commit through the facade\n' >&2
	cat "$tmp/amend.err" >&2
	exit 1
fi
grep -Fqx -- "-C $root commit --amend --only -m fix(vcs): safe help" "$amend_log"
grep -Fqx -- "-C $root fetch --prune https://git.centralcloud.net/mhugo/dotfiles.git +refs/heads/*:refs/remotes/origin/*" "$amend_log"
grep -Fqx -- "-C $root for-each-ref --contains HEAD --format=%(refname) refs/remotes/origin" "$amend_log"

amend_blocked_log="$tmp/amend-blocked.log"
if REMOTE_CONTAINS_HEAD=1 AMEND_LOG="$amend_blocked_log" SE_GIT_BIN="$tmp/amend/git" "$root/bin/repo" vcs amend 'fix(vcs): safe help' >"$tmp/amend-blocked.out" 2>"$tmp/amend-blocked.err"; then
	printf 'repo vcs amend must reject a task HEAD already present on a remote branch\n' >&2
	exit 1
fi
if grep -Fq -- 'commit --amend --only' "$amend_blocked_log"; then
	printf 'repo vcs amend rewrote a task HEAD already present on a remote branch\n' >&2
	exit 1
fi

if grep -Eq 'timeout[^\n]*[[:space:]]git[[:space:]]+-C' "$root/scripts/repo-vcs.sh"; then
	printf 'timeout-wrapped publication bypasses pinned Git\n' >&2
	exit 1
fi

"$root/scripts/repo-vcs.sh" contract-test
"$root/bin/repo" help | grep -q 'repo vcs land'
"$root/bin/repo" help | grep -q 'repo vcs rebase'
grep -q 'rebase --continue requires at least one resolved path' "$root/scripts/repo-vcs.sh" || {
	printf 'rebase continuation must require explicit resolved paths\n' >&2
	exit 1
}
grep -q 'conflict markers remain in' "$root/scripts/repo-vcs.sh" || {
	printf 'rebase continuation must reject unresolved conflict markers\n' >&2
	exit 1
}
"$root/bin/repo" help | grep -q 'repo vcs sync-main'
"$root/bin/repo" help | grep -q 'repo vcs worktree-abandon'
"$root/bin/repo" help | grep -q 'repo vcs branch-retire'
# Leftover lanes used chore/* branches and prunable missing checkouts. Abandon
# must resolve the live worktree HEAD and prune a vanished path.
grep -q 'symbolic-ref --quiet --short HEAD' "$root/scripts/repo-vcs.sh" || {
	printf 'task_branch_for must resolve a registered worktree HEAD when worktree/ and codex/ refs are absent\n' >&2
	exit 1
}
grep -q 'worktree prune' "$root/scripts/repo-vcs.sh" || {
	printf 'worktree-abandon must prune a registered missing checkout\n' >&2
	exit 1
}
if "$root/scripts/repo-vcs.sh" rebase >/dev/null 2>&1; then
	printf 'rebase unexpectedly accepted a missing revision\n' >&2
	exit 1
fi
if "$root/scripts/repo-vcs.sh" worktree-abandon ast-grep-sg wrong-confirmation >/dev/null 2>&1; then
	printf 'worktree-abandon unexpectedly accepted an invalid confirmation\n' >&2
	exit 1
fi
if "$root/scripts/repo-vcs.sh" branch-retire main >/dev/null 2>&1; then
	printf 'branch-retire unexpectedly accepted main\n' >&2
	exit 1
fi
if "$root/scripts/repo-vcs.sh" branch-retire leftover-unnamespaced >/dev/null 2>&1; then
	printf 'branch-retire unexpectedly accepted an unnamespaced ref\n' >&2
	exit 1
fi

retire_log="$tmp/branch-retire.log"
mkdir -p "$tmp/retire"
cat >"$tmp/retire/git" <<'RETIRE_GIT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RETIRE_LOG"
if [[ "$*" == *'show-ref --verify --quiet refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
if [[ "$*" == *'worktree list --porcelain'* ]]; then
	printf '%s\n' 'worktree /tmp/dotfiles-primary' 'HEAD abc' 'branch refs/heads/main'
	exit 0
fi
if [[ "$*" == *'rev-parse refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	printf '%s\n' a9d8d39252d79d92de7445d136785cce527c7446
	exit 0
fi
if [[ "$*" == *'show-ref --verify --quiet refs/remotes/origin/chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
exit 0
RETIRE_GIT
chmod 0755 "$tmp/retire/git"
if ! RETIRE_LOG="$retire_log" SE_GIT_BIN="$tmp/retire/git" "$root/scripts/repo-vcs.sh" branch-retire chore/retire-infra-centralcloud-com >"$tmp/retire-dry.out" 2>"$tmp/retire-dry.err"; then
	printf 'branch-retire dry-run must succeed for an unused leftover ref\n' >&2
	cat "$tmp/retire-dry.err" >&2
	exit 1
fi
grep -Fq 'dry-run leftover=chore/retire-infra-centralcloud-com' "$tmp/retire-dry.out"
grep -Fq 'apply=false' "$tmp/retire-dry.out"
if grep -Fq 'branch -D' "$retire_log"; then
	printf 'branch-retire dry-run deleted a leftover ref\n' >&2
	exit 1
fi
if grep -Fq 'push ' "$retire_log"; then
	printf 'branch-retire dry-run pushed a leftover delete\n' >&2
	exit 1
fi

checked_out_log="$tmp/branch-retire-checked-out.log"
cat >"$tmp/retire/git-checked-out" <<'RETIRE_CHECKED_OUT'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RETIRE_CHECKED_OUT_LOG"
if [[ "$*" == *'show-ref --verify --quiet refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
if [[ "$*" == *'worktree list --porcelain'* ]]; then
	printf '%s\n' 'worktree /tmp/dotfiles-leftover' 'HEAD abc' 'branch refs/heads/chore/retire-infra-centralcloud-com'
	exit 0
fi
exit 0
RETIRE_CHECKED_OUT
chmod 0755 "$tmp/retire/git-checked-out"
if RETIRE_CHECKED_OUT_LOG="$checked_out_log" SE_GIT_BIN="$tmp/retire/git-checked-out" "$root/scripts/repo-vcs.sh" branch-retire chore/retire-infra-centralcloud-com --apply >"$tmp/retire-co.out" 2>"$tmp/retire-co.err"; then
	printf 'branch-retire must refuse a leftover ref checked out in a worktree\n' >&2
	exit 1
fi
if grep -Fq 'branch -D' "$checked_out_log"; then
	printf 'branch-retire deleted a leftover ref that is checked out\n' >&2
	exit 1
fi

apply_log="$tmp/branch-retire-apply.log"
cat >"$tmp/retire/git-apply" <<'RETIRE_APPLY'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RETIRE_APPLY_LOG"
if [[ "$*" == *'show-ref --verify --quiet refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	if grep -Fq -- 'branch -D chore/retire-infra-centralcloud-com' "$RETIRE_APPLY_LOG"; then
		exit 1
	fi
	exit 0
fi
if [[ "$*" == *'worktree list --porcelain'* ]]; then
	printf '%s\n' 'worktree /tmp/dotfiles-primary' 'HEAD abc' 'branch refs/heads/main'
	exit 0
fi
if [[ "$*" == *'rev-parse refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	printf '%s\n' a9d8d39252d79d92de7445d136785cce527c7446
	exit 0
fi
if [[ "$*" == *'show-ref --verify --quiet refs/remotes/origin/chore/retire-infra-centralcloud-com'* ]]; then
	if grep -Fq -- ':refs/heads/chore/retire-infra-centralcloud-com' "$RETIRE_APPLY_LOG"; then
		exit 1
	fi
	exit 0
fi
if [[ "$*" == *'fetch --prune '* ]]; then
	exit 0
fi
if [[ "$*" == *'ls-remote '* && "$*" == *'github.com'* && "$*" == *'refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	printf '%s\t%s\n' a9d8d39252d79d92de7445d136785cce527c7446 refs/heads/chore/retire-infra-centralcloud-com
	exit 0
fi
if [[ "$*" == *'push '* && "$*" == *':refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
if [[ "$*" == *'branch -D chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
exit 0
RETIRE_APPLY
chmod 0755 "$tmp/retire/git-apply"
if ! RETIRE_APPLY_LOG="$apply_log" SE_GIT_BIN="$tmp/retire/git-apply" "$root/scripts/repo-vcs.sh" branch-retire chore/retire-infra-centralcloud-com --apply >"$tmp/retire-apply.out" 2>"$tmp/retire-apply.err"; then
	printf 'branch-retire --apply must retire an unused leftover ref\n' >&2
	cat "$tmp/retire-apply.err" >&2
	exit 1
fi
grep -Fq 'retired leftover=chore/retire-infra-centralcloud-com' "$tmp/retire-apply.out"
grep -Fq -- 'branch -D chore/retire-infra-centralcloud-com' "$apply_log"
grep -Fq -- ':refs/heads/chore/retire-infra-centralcloud-com' "$apply_log"
grep -Fq -- 'fetch --prune' "$apply_log"

remote_only_log="$tmp/branch-retire-remote-only.log"
cat >"$tmp/retire/git-remote-only" <<'RETIRE_REMOTE_ONLY'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RETIRE_REMOTE_ONLY_LOG"
if [[ "$*" == *'show-ref --verify --quiet refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	exit 1
fi
if [[ "$*" == *'show-ref --verify --quiet refs/remotes/origin/chore/retire-infra-centralcloud-com'* ]]; then
	if grep -Fq -- ':refs/heads/chore/retire-infra-centralcloud-com' "$RETIRE_REMOTE_ONLY_LOG"; then
		exit 1
	fi
	exit 0
fi
if [[ "$*" == *'worktree list --porcelain'* ]]; then
	printf '%s\n' 'worktree /tmp/dotfiles-primary' 'HEAD abc' 'branch refs/heads/main'
	exit 0
fi
if [[ "$*" == *'rev-parse refs/remotes/origin/chore/retire-infra-centralcloud-com'* ]]; then
	printf '%s\n' a9d8d39252d79d92de7445d136785cce527c7446
	exit 0
fi
if [[ "$*" == *'fetch --prune '* ]]; then
	exit 0
fi
if [[ "$*" == *'ls-remote '* ]]; then
	exit 0
fi
if [[ "$*" == *'push '* && "$*" == *':refs/heads/chore/retire-infra-centralcloud-com'* ]]; then
	exit 0
fi
exit 0
RETIRE_REMOTE_ONLY
chmod 0755 "$tmp/retire/git-remote-only"
if ! RETIRE_REMOTE_ONLY_LOG="$remote_only_log" SE_GIT_BIN="$tmp/retire/git-remote-only" "$root/scripts/repo-vcs.sh" branch-retire chore/retire-infra-centralcloud-com --apply >"$tmp/retire-remote-only.out" 2>"$tmp/retire-remote-only.err"; then
	printf 'branch-retire --apply must retire a leftover that exists only on origin\n' >&2
	cat "$tmp/retire-remote-only.err" >&2
	exit 1
fi
grep -Fq 'retired leftover=chore/retire-infra-centralcloud-com' "$tmp/retire-remote-only.out"
if grep -Fq 'branch -D' "$remote_only_log"; then
	printf 'remote-only branch-retire deleted a missing local ref\n' >&2
	exit 1
fi
grep -Fq -- ':refs/heads/chore/retire-infra-centralcloud-com' "$remote_only_log"
[[ "$(env -u DOTFILES_GIT_PUSH_TIMEOUT "$root/scripts/repo-vcs.sh" config)" == "push_timeout=300" ]]
[[ "$(DOTFILES_GIT_PUSH_TIMEOUT=17 "$root/scripts/repo-vcs.sh" config)" == "push_timeout=17" ]]
# Match the literal variable references in the facade implementation.
# shellcheck disable=SC2016
github_push_line="$(grep -n 'push "$github_url" HEAD:main' "$root/scripts/repo-vcs.sh" | cut -d: -f1)"
# shellcheck disable=SC2016
forgejo_push_line="$(grep -n 'push "$forgejo_https_url" HEAD:main' "$root/scripts/repo-vcs.sh" | cut -d: -f1)"
[[ "$github_push_line" -lt "$forgejo_push_line" ]] || {
	printf 'land must converge GitHub before triggering the Forgejo mirror\n' >&2
	exit 1
}
if DOTFILES_GIT_PUSH_TIMEOUT=invalid "$root/scripts/repo-vcs.sh" config >/dev/null 2>&1; then
	printf 'invalid push timeout unexpectedly accepted\n' >&2
	exit 1
fi
