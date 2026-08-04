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
grep -Fqx -- "-C $root fetch --prune https://git.infra.centralcloud.com/mhugo/dotfiles.git +refs/heads/*:refs/remotes/origin/*" "$amend_log"
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
"$root/bin/repo" help | grep -q 'repo vcs sync-main'
"$root/bin/repo" help | grep -q 'repo vcs worktree-abandon'
if "$root/scripts/repo-vcs.sh" rebase >/dev/null 2>&1; then
	printf 'rebase unexpectedly accepted a missing revision\n' >&2
	exit 1
fi
if "$root/scripts/repo-vcs.sh" worktree-abandon ast-grep-sg wrong-confirmation >/dev/null 2>&1; then
	printf 'worktree-abandon unexpectedly accepted an invalid confirmation\n' >&2
	exit 1
fi
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
