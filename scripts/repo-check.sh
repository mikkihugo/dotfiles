#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Paths whose changes can alter the homeConfigurations activation package:
# any *.nix file, the lock, plus the non-nix trees the modules read through
# ${../../...} references (config/, secrets/, scripts/codex-preferences,
# scripts/merge-authorized-keys — see home/modules/activation.nix and
# home/modules/files.nix).
nix_gate_path_re='(^|/)[^/]+\.nix$|^flake\.lock$|^home/|^config/|^secrets/|^scripts/codex-preferences$|^scripts/merge-authorized-keys$'

nix_gate_needs_build() {
	# Returns 0 when the nix build gate must run, 1 when the diff against
	# origin/main contains nothing that can change the activation package.
	# Fails OPEN: any uncertainty (origin/main missing, no merge-base,
	# unreadable diff) runs the build. An empty diff also builds, preserving
	# the historical behaviour of a standalone `just check` on synced main.
	local base changed
	base="$(git -C "$root" merge-base origin/main HEAD 2>/dev/null)" || return 0
	changed="$(git -C "$root" diff --name-only "$base" HEAD 2>/dev/null)" || return 0
	[[ -n "$changed" ]] || return 0
	printf '%s\n' "$changed" | grep -Eq "$nix_gate_path_re"
}

main() {
	local profile
	profile="$("$root/scripts/current-home-profile")"
	"$root/scripts/test-repo-vcs.sh"
	HOME_MANAGER_PROFILE="$profile" bash "$root/scripts/test-ast-grep-shim.sh"
	python3 "$root/scripts/test-codex-preferences.py"
	python3 "$root/scripts/test-merge-authorized-keys.py"
	(
		cd "$root"
		node --test \
			scripts/test-cargo-pgrx-wrapper.mjs \
			scripts/test-codex-hosted-search.mjs \
			scripts/test-stable-shell-path.mjs \
			scripts/test-swarm-messages.mjs \
			scripts/test-swarm-hook-config.mjs \
			scripts/test-nix-tooling.mjs
	)
	if ! nix_gate_needs_build; then
		printf 'skipped home-manager build gate (no nix-relevant changes vs origin/main)\n'
		return 0
	fi
	# This gate evaluates exactly one activation package. Using nix-fast-build here
	# adds no parallelism, while its nix-eval-jobs workers reread daemon-only Nix
	# settings and contend on the shared evaluation cache. Keep nix-fast-build
	# installed for multi-attribute builds; use Nix directly for this single target.
	nix build --no-link "path:$root#homeConfigurations.${profile}.activationPackage"
}

# Function-only when sourced, so the gate decision can be tested in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
