#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
"$root/scripts/repo-vcs.sh" contract-test
"$root/bin/repo" help | grep -q 'repo vcs land'
[[ "$(env -u DOTFILES_GIT_PUSH_TIMEOUT "$root/scripts/repo-vcs.sh" config)" == "push_timeout=300" ]]
[[ "$(DOTFILES_GIT_PUSH_TIMEOUT=17 "$root/scripts/repo-vcs.sh" config)" == "push_timeout=17" ]]
if DOTFILES_GIT_PUSH_TIMEOUT=invalid "$root/scripts/repo-vcs.sh" config >/dev/null 2>&1; then
	printf 'invalid push timeout unexpectedly accepted\n' >&2
	exit 1
fi
