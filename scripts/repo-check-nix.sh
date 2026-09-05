#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fail() {
	printf 'dotfiles Nix environment rejected: %s\n' "$1" >&2
	# shellcheck disable=SC2016 # Print the recovery command literally for the caller.
	printf 'Next: cd %q and eval "$(direnv export bash)".\n' "$root" >&2
	exit 1
}
[[ $# == 0 ]] || fail 'unexpected arguments'
[[ "${IN_NIX_SHELL:-}" == pure || "${IN_NIX_SHELL:-}" == impure ]] || fail 'Nix shell is not active'
[[ "${NIX_DIRENV_DID_FALLBACK:-}" != 1 ]] || fail 'direnv fallback is active'
command -v nix >/dev/null || fail 'nix is unavailable'
[[ "$(command -v repo || true)" == "$root/bin/repo" ]] || fail 'repo resolves outside this checkout'
[[ -z "${DIRENV_DIR:-}" || "${DIRENV_DIR#-}" == "$root" ]] || fail 'direnv belongs to another checkout'
printf 'dotfiles exact-root Nix environment: ok\n'
