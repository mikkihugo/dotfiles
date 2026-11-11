#!/usr/bin/env bash
# Purpose: fail the publish gate when the vendored direnv export-shell guard
#   drifts from centralcloud/infra's canonical copy.
# Consumer: scripts/repo-check.sh (the dotfiles publish gate).
# Failure boundary: infra changes the guard, dotfiles keeps building the old
#   one and the fleet runs two different guards.
# Falsifier: change a code line in either vendored file and this must fail.
#
# The vendored copy exists so the dotfiles build does not follow /srv/infra's
# working tree. A `path:/srv/infra` flake input makes every dotfiles build
# evaluate infra's whole flake (every output, `checks` included) and copy its
# 253k-file tree into the store; an in-flight edit in another repo then broke
# publication here. This check is the price of that decoupling.
#
# Comparison rules (both files, local vs canonical):
#   - the leading comment header is dropped: it is provenance prose and names
#     a different consumer path on each side.
#   - the guard source path is normalized: the local .nix reads its sibling
#     file, infra's reads ../../scripts/lib/... The guard CONTENT is compared
#     byte for byte by the .sh half of this check.
# Everything else — including the wrapper's shebang — must match exactly.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
canonical_root="${INFRA_ROOT:-/srv/infra}"

local_dir="$root/config/direnv"
canonical_nix="$canonical_root/hosts/_shared/direnv-export-shell-guard.nix"
canonical_sh="$canonical_root/scripts/lib/direnv-export-shell-guard.sh"

if [[ ! -f "$canonical_nix" || ! -f "$canonical_sh" ]]; then
	printf 'skip: canonical guard not present under %s (host without the infra checkout)\n' "$canonical_root"
	exit 0
fi

normalize() {
	sed -e '/^[^#[:space:]]/,$!d' -e 's#lib\.cleanSource .*#lib.cleanSource GUARD#' "$1"
}

failures=0
compare() {
	local label="$1" local_file="$2" canonical_file="$3"
	if diff -u <(normalize "$canonical_file") <(normalize "$local_file"); then
		printf 'ok   %s matches %s\n' "$label" "$canonical_file"
	else
		printf 'FAIL: %s drifted from %s\n' "$label" "$canonical_file" >&2
		failures=$((failures + 1))
	fi
}

compare 'direnv-export-shell-guard.sh' "$local_dir/direnv-export-shell-guard.sh" "$canonical_sh"
compare 'direnv-export-shell-guard.nix' "$local_dir/direnv-export-shell-guard.nix" "$canonical_nix"

if ((failures > 0)); then
	printf '%s guard drift failure(s): re-vendor from %s\n' "$failures" "$canonical_root" >&2
	exit 1
fi
printf 'direnv export-shell guard matches centralcloud/infra\n'
