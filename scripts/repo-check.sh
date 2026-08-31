#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Paths whose changes can alter the homeConfigurations activation package:
# any *.nix file, the lock, and the home/config/secrets trees the modules
# read directly.
nix_gate_path_re='(^|/)[^/]+\.nix$|^flake\.lock$|^home/|^config/|^secrets/'

# Non-nix scripts pulled into the activation package through a
# `${../../scripts/NAME}` interpolation in home/modules/*.nix. The name part is
# an open character class on purpose: grex over the three references that exist
# today emits
#   ^\.\./\.\./scripts/(?:merge\-authorized\-key|(?:codex|jcode)\-preference)s$
# which is a closed enumeration and would reintroduce exactly the drift below.
# Derived at check time rather than hand-listed: the old hardcoded allow-list named
# codex-preferences and merge-authorized-keys but not jcode-preferences, so once
# home/modules/jcode-providers.nix started referencing it that script could be
# changed alone and silently skip this gate.
nix_gate_referenced_scripts() {
	grep -rhoE '\.\./\.\./scripts/[A-Za-z0-9_.-]+' "$root/home/modules" 2>/dev/null |
		sed -E 's#^\.\./\.\./##' | sort -u
}

nix_gate_needs_build() {
	# Returns 0 when the nix build gate must run, 1 when the diff against
	# origin/main contains nothing that can change the activation package.
	# Fails OPEN: any uncertainty (origin/main missing, no merge-base,
	# unreadable diff) runs the build. An empty diff also builds, preserving
	# the historical behaviour of a standalone `just check` on synced main.
	local base changed script
	base="$(git -C "$root" merge-base origin/main HEAD 2>/dev/null)" || return 0
	changed="$(git -C "$root" diff --name-only "$base" HEAD 2>/dev/null)" || return 0
	[[ -n "$changed" ]] || return 0
	printf '%s\n' "$changed" | grep -Eq "$nix_gate_path_re" && return 0
	while IFS= read -r script; do
		[[ -n "$script" ]] || continue
		grep -Fxq "$script" <<<"$changed" && return 0
	done < <(nix_gate_referenced_scripts)
	return 1
}

main() {
	local profile
	profile="$("$root/scripts/current-home-profile")"
	"$root/scripts/test-repo-vcs.sh"
	HOME_MANAGER_PROFILE="$profile" bash "$root/scripts/test-ast-grep-shim.sh"
	python3 "$root/scripts/test-codex-preferences.py"
	python3 "$root/scripts/test-jcode-preferences.py"
	python3 "$root/scripts/test-merge-authorized-keys.py"
	bash "$root/scripts/test-nix-gate-script-coverage.sh"
	bash "$root/scripts/test-engine-worktree-cleanup.sh"
	bash "$root/scripts/test-sccache-profile-scope.sh"
	(
		cd "$root"
		node --test \
			scripts/test-cargo-pgrx-wrapper.mjs \
			scripts/test-codex-hosted-search.mjs \
			scripts/test-codex-external-harness-skill.mjs \
			scripts/test-codex-external-run.mjs \
			scripts/test-detect-secrets-work-packet-filter.mjs \
			scripts/test-jcode-lane-settle-retirement.mjs \
			scripts/test-sops-trace-guard.mjs \
			scripts/test-stable-shell-path.mjs \
			scripts/test-swarm-messages.mjs \
			scripts/test-swarm-hook-config.mjs \
			scripts/test-nix-tooling.mjs \
			scripts/test-nix-direnv-no-flake-input-gcroots.mjs \
			scripts/test-retired-infra-hosts.mjs \
			scripts/test-ssh-sto-core.mjs \
			scripts/test-ssh-bunker-windows.mjs
	)
	# Keep the NixOS ownership evaluation out of the nominal Node-only suite: it
	# evaluates the homeConfigurations attrset and is intentionally a separate
	# slow gate.
	(
		cd "$root"
		RUN_NIX_EVAL_TESTS=1 node --test \
			--test-name-pattern='the NixOS devbox is the sole interactive direnv hook authority' \
			scripts/test-stable-shell-path.mjs
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
