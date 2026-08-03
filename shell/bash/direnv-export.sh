#!/usr/bin/env sh
# Load a repository environment for non-interactive shells without repeatedly
# evaluating the same repo. Consumers: bashrc-driven agent and CI shells.
# Contract: same-repo nested shells reuse the inherited direnv environment;
# shells moved to another repo get one 15-second-bounded refresh and fail open.

if [ -n "${DIRENV_DISABLE:-}" ] || [ "${-#*i}" != "$-" ]; then
	return 0
fi

_direnv_active_root="${DIRENV_DIR#-}"
if [ -n "${IN_NIX_SHELL:-}" ] && [ -n "$_direnv_active_root" ]; then
	case "$PWD/" in
	"$_direnv_active_root/"*)
		unset _direnv_active_root
		return 0
		;;
	esac
fi
unset _direnv_active_root

# Home Manager supplies coreutils, but fail open if either dependency is absent;
# never replace the bounded contract with an unbounded fallback.
if ! command -v direnv >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
	return 0
fi

unset DIRENV_DIFF DIRENV_WATCHES
eval "$(timeout 15s direnv export bash 2>/dev/null)" || true
