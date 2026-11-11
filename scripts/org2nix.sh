#!/usr/bin/env bash
# dotfiles org2nix shim — prefer Engine nix/cache/org2nix.sh, else minimal embed.
# shellcheck shell=bash
set -euo pipefail

_dotfiles_org2nix_engine_root() {
	local engine_root="${SE_ORG_NIX_CONFIG_ROOT:-${SINGULARITY_ENGINE_ROOT:-}}"
	if [[ -z "$engine_root" || ! -f "$engine_root/nix/cache/org2nix.sh" ]]; then
		for engine_root in "${HOME}/code/singularity-engine" "/home/mhugo/code/singularity-engine"; do
			[[ -f "$engine_root/nix/cache/org2nix.sh" ]] && break
			engine_root=""
		done
	fi
	[[ -n "$engine_root" && -f "$engine_root/nix/cache/org2nix.sh" ]] || return 1
	printf '%s' "$engine_root"
}

_org2nix_loaded=false
if _dotfiles_root="$(_dotfiles_org2nix_engine_root 2>/dev/null)"; then
	# shellcheck source=/dev/null
	source "$_dotfiles_root/nix/cache/org2nix.sh"
	_org2nix_loaded=true
fi

if [[ "$_org2nix_loaded" != true ]]; then
	_org2nix_engine_root() {
		local engine_root="${SE_ORG_NIX_CONFIG_ROOT:-}"
		for engine_root in "${engine_root:-}" "${HOME}/code/singularity-engine" "/home/mhugo/code/singularity-engine"; do
			[[ -n "$engine_root" ]] || continue
			[[ -f "$engine_root/nix/cache/org-nix-config.sh" ]] && break
			engine_root=""
		done
		[[ -n "$engine_root" ]] || {
			printf 'org2nix: missing Engine nix/cache/org-nix-config.sh\n' >&2
			return 1
		}
		printf '%s' "$engine_root"
	}

	org2nix_activate() {
		local engine_root
		engine_root="$(_org2nix_engine_root)" || return 1
		# shellcheck source=/dev/null
		source "$engine_root/nix/cache/org-nix-config.sh"
		SE_ORG_NIX_CONFIG_ROOT="$engine_root" se_org_nix_config_activate || return 1
		export NIX_CONFIG="${NIX_CONFIG}
max-jobs = 0
"
	}

	org2nix() {
		org2nix_activate || return $?
		case "${1:-}" in
		build | copy | develop | profile | run | shell | store)
			command nix --option max-jobs 0 "$@"
			;;
		flake)
			case "${2:-}" in
			build | check) command nix --option max-jobs 0 "$@" ;;
			*) command nix "$@" ;;
			esac
			;;
		*) command nix "$@" ;;
		esac
	}
fi

# repo-check historically called this name.
activate_org_nix_config_for_build() {
	org2nix_activate
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	org2nix "$@"
fi
