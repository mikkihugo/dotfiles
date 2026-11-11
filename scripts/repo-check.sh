#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Paths whose changes can alter the homeConfigurations activation package by
# structure alone: any *.nix file (evaluation can change), the lock, and the
# secrets tree (read by modules even where not interpolated).
nix_gate_path_re='(^|/)[^/]+\.nix$|^flake\.lock$|^secrets/'

# Non-nix files pulled into the activation package by a home/ module or the
# root flake: `${./path}` / `${../../path}` interpolations and
# builtins.readFile/readDir arguments. Derived by scanning the nix sources for
# relative-path tokens and resolving each against the referencing FILE's
# directory — `../x` from home/modules/y.nix is home/x while from home/y.nix
# it is the repo-root x, so a flat prefix grep cannot resolve them.
#
# Derived at check time rather than hand-listed: the previous prefix rule
# (`^config/`, `^home/`) ran the full activation build for EVERY change under
# those trees — including docs such as config/code/AGENTS.md that no module
# references (a ~20-30 min build gate on a markdown edit). Extension-based
# rules are unsafe in the other direction: markdown IS interpolated where it
# is referenced (config/agents/purpose-backbone.md is readFile'd by
# jcode-providers.nix; config/copilot/agents/*.md are sources). Reference
# derivation covers both: build when a referenced file changes, skip when
# nothing referenced changed. Over-inclusion from comment strings only adds
# build triggers (the safe direction); the empty-derivation check below is
# the fail-open guard against under-inclusion.
nix_gate_referenced_files() {
	grep -rHnoE '(\.{1,2}/)+[A-Za-z0-9_./+-]+' "$root/home" "$root/flake.nix" 2>/dev/null |
		while IFS=: read -r file _ token; do
			resolved="$(realpath -m --relative-to="$root" "$(dirname "$file")/$token" 2>/dev/null)" || continue
			[[ -n "$resolved" && "$resolved" != "." && "$resolved" != ..* && "$resolved" != /* ]] && printf '%s\n' "$resolved"
			# Neutralize the rejected-token status so the loop (and, under
			# pipefail, the whole pipeline) exits 0 regardless of which
			# token came last — callers use the output, not the status.
			:
		done | sort -u
}

# Module-referenced scripts only; kept as the surface the coverage test
# asserts against (it derives the expected scripts independently).
nix_gate_referenced_scripts() {
	nix_gate_referenced_files | grep -E '^scripts/' || true
}

nix_gate_needs_build() {
	# Returns 0 when the nix build gate must run, 1 when the diff against
	# origin/main contains nothing that can change the activation package.
	# Fails OPEN: any uncertainty (origin/main missing, no merge-base,
	# unreadable diff, empty reference derivation) runs the build. An empty
	# diff also builds, preserving the historical behaviour of a standalone
	# `just check` on synced main.
	local base changed ref referenced
	base="$(git -C "$root" merge-base origin/main HEAD 2>/dev/null)" || return 0
	# Include committed, staged, unstaged, and untracked paths. A dirty worktree
	# must not skip the activation build merely because HEAD's diff is unrelated.
	changed="$({
		git -C "$root" diff --name-only "$base" HEAD
		git -C "$root" diff --name-only
		git -C "$root" diff --cached --name-only
		git -C "$root" ls-files --others --exclude-standard
	} 2>/dev/null | sort -u)" || return 0
	[[ -n "$changed" ]] || return 0
	printf '%s\n' "$changed" | grep -Eq "$nix_gate_path_re" && return 0
	referenced="$(nix_gate_referenced_files)"
	# A derivation that produces nothing means the scan broke, not that the
	# tree is safe — run the build.
	[[ -n "$referenced" ]] || return 0
	while IFS= read -r ref; do
		[[ -n "$ref" ]] || continue
		if [[ -d "$root/$ref" ]]; then
			# Directory interpolation (e.g. `./borg/`): any change under it.
			grep -q "^$ref/" <<<"$changed" && return 0
		else
			grep -Fxq "$ref" <<<"$changed" && return 0
		fi
	done <<<"$referenced"
	return 1
}

# Run one battery stage and report its wall time. Before this existed the
# check printed per-test ok lines but no timing, so "make repo check faster"
# had no data to work from — the 2026-11-10 gate optimization was designed
# from a single slow-land observation instead of measurements.
check_stage() {
	local label="$1" start
	start="$(date +%s%3N)"
	shift
	printf 'stage %s: start\n' "$label"
	"$@"
	printf 'stage %s: ok (%dms)\n' "$label" "$(($(date +%s%3N) - start))"
}

# shellcheck source=scripts/org2nix.sh
source "$root/scripts/org2nix.sh"

DOTFILES_ACTIVATION_PACKAGE=""

build_activation_package() {
	local profile="$1"
	DOTFILES_ACTIVATION_PACKAGE="$(
		org2nix build --no-link --print-out-paths \
			"path:$root#homeConfigurations.${profile}.activationPackage"
	)"
	export DOTFILES_ACTIVATION_PACKAGE
}

verify_activation_package() {
	[[ -n "$DOTFILES_ACTIVATION_PACKAGE" && -d "$DOTFILES_ACTIVATION_PACKAGE" ]] || {
		printf 'repo-check: activation package path missing after build\n' >&2
		return 1
	}
}

stage_python_unit_tests() {
	python3 "$root/scripts/test-repo-check-entry.py"
	python3 "$root/scripts/test-codex-preferences.py"
	python3 "$root/scripts/test-purpose-backbone.py"
	python3 "$root/scripts/test-jcode-preferences.py"
	python3 "$root/scripts/test-merge-authorized-keys.py"
}

stage_bash_unit_tests() {
	bash "$root/scripts/test-nix-gate-script-coverage.sh"
	bash "$root/scripts/test-sccache-profile-scope.sh"
	bash "$root/scripts/test-language-cache-layout.sh"
	bash "$root/scripts/test-codex-rollout-gc.sh"
	bash "$root/scripts/test-git-credential-forgejo-bao.sh"
	bash "$root/scripts/test-forgejo-token-sync.sh"
}

stage_node_unit_tests() {
	(
		cd "$root"
		node --test \
			scripts/test-opencode-config.mjs \
			scripts/test-cargo-pgrx-wrapper.mjs \
			scripts/test-tabby-terminal.mjs \
			scripts/test-codex-hosted-search.mjs \
			scripts/test-codex-external-harness-skill.mjs \
			scripts/test-codex-external-run.mjs \
			scripts/test-detect-secrets-work-packet-filter.mjs \
			scripts/test-jcode-lane-settle-retirement.mjs \
			scripts/test-sops-trace-guard.mjs \
			scripts/test-hms-primary-checkout-guard.mjs \
			scripts/test-nix-tooling.mjs \
			scripts/test-nix-direnv-no-flake-input-gcroots.mjs \
			scripts/test-retired-infra-hosts.mjs \
			scripts/test-ssh-sto-core.mjs \
			scripts/test-ssh-bunker-windows.mjs
	)
}

# The stable-shell tests launch many isolated fake-direnv shells. Run that
# stateful fixture serially; Node's default test concurrency races its
# process-level shell fixtures and makes the BASH_ENV proof flaky.
stage_stable_shell_tests() {
	(
		cd "$root"
		env -u IN_NIX_SHELL -u NIX_DIRENV_DID_FALLBACK -u DIRENV_DISABLE \
			-u DIRENV_DIR -u DIRENV_FILE -u DIRENV_CONFIG \
			-u DIRENV_INSTANT_SHELL_PID -u DIRENV_DIFF -u DIRENV_WATCHES \
			-u AGENT_DIRENV_EXPORT_TRIED -u AGENT_DIRENV_EXPORT_TRIED_ROOT \
			node --test --test-concurrency=1 \
			--test-name-pattern='^(?!BASH_ENV path hook)' scripts/test-stable-shell-path.mjs
		env -u IN_NIX_SHELL -u NIX_DIRENV_DID_FALLBACK -u DIRENV_DISABLE \
			-u DIRENV_DIR -u DIRENV_FILE -u DIRENV_CONFIG \
			-u DIRENV_INSTANT_SHELL_PID -u DIRENV_DIFF -u DIRENV_WATCHES \
			-u AGENT_DIRENV_EXPORT_TRIED -u AGENT_DIRENV_EXPORT_TRIED_ROOT \
			node --test --test-concurrency=1 \
			--test-name-pattern='BASH_ENV path hook' scripts/test-stable-shell-path.mjs
	)
}

stage_nixos_ownership_eval() {
	(
		cd "$root"
		RUN_NIX_EVAL_TESTS=1 node --test \
			--test-name-pattern='the NixOS devbox is the sole interactive direnv hook authority' \
			scripts/test-stable-shell-path.mjs
	)
}

main() {
	case "${1:-}" in
	codex-preferences)
		[[ $# == 1 ]] || {
			printf 'unexpected Codex test arguments\n' >&2
			return 2
		}
		python3 "$root/scripts/test-codex-preferences.py"
		return
		;;
	check-entry)
		[[ $# == 1 ]] || {
			printf 'unexpected entry test arguments\n' >&2
			return 2
		}
		python3 "$root/scripts/test-repo-check-entry.py"
		return
		;;
	"") [[ $# == 0 ]] || {
		printf 'unexpected empty check argument\n' >&2
		return 2
	} ;;
	*)
		printf 'unknown check: %s\n' "$1" >&2
		return 2
		;;
	esac
	local profile
	profile="$("$root/scripts/current-home-profile")"
	# One gate decision for the whole check: the build gate below and the
	# NixOS-ownership eval both test the homeConfigurations activation
	# package, which cannot change when the gate says nothing relevant
	# changed — so a skipped gate skips both.
	local nix_relevant=0
	if nix_gate_needs_build; then
		nix_relevant=1
	fi
	check_stage preamble bash "$root/scripts/test-repo-vcs.sh"
	# One remote activation build per check (ast-grep shim + build gate share it).
	# The shim stage still takes a per-profile flock so concurrent checks serialize.
	if [[ $nix_relevant -eq 1 ]]; then
		check_stage activation-package-build build_activation_package "$profile"
		check_stage ast-grep-shim env \
			"HOME_MANAGER_PROFILE=$profile" \
			"DOTFILES_ACTIVATION_PACKAGE=$DOTFILES_ACTIVATION_PACKAGE" \
			bash "$root/scripts/test-ast-grep-shim.sh"
	else
		printf 'skipped ast-grep shim stage (no nix-relevant changes vs origin/main)\n'
	fi
	check_stage python-unit-tests stage_python_unit_tests
	check_stage bash-unit-tests stage_bash_unit_tests
	check_stage node-unit-tests stage_node_unit_tests
	check_stage stable-shell-tests stage_stable_shell_tests
	# Keep the NixOS ownership evaluation out of the nominal Node-only suite: it
	# evaluates the homeConfigurations attrset and is intentionally a separate
	# slow gate. When the build gate says nothing nix-relevant changed, the
	# evaluated attrset is identical to the last run, so the eval assertions
	# cannot newly fail — skip them with the same decision.
	if [[ $nix_relevant -eq 1 ]]; then
		check_stage nixos-ownership-eval stage_nixos_ownership_eval
	else
		printf 'skipped nixos-ownership eval (no nix-relevant changes vs origin/main)\n'
	fi
	if [[ $nix_relevant -eq 0 ]]; then
		printf 'skipped home-manager build gate (no nix-relevant changes vs origin/main)\n'
		return 0
	fi
	check_stage home-manager-build verify_activation_package
}

# Function-only when sourced, so the gate decision can be tested in isolation.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
