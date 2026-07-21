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
if grep -Eq 'timeout[^\n]*[[:space:]]git[[:space:]]+-C' "$root/scripts/repo-vcs.sh"; then
	printf 'timeout-wrapped publication bypasses pinned Git\n' >&2
	exit 1
fi

"$root/scripts/repo-vcs.sh" contract-test
"$root/bin/repo" help | grep -q 'repo vcs land'
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
