#!/usr/bin/env sh
# Load a repository environment for non-interactive shells without repeatedly
# evaluating the same repo. Consumers: bashrc, BASH_ENV (Claude/Codex/goose),
# zshenv (Cursor `zsh -c`), and the host-wide agent-shell wrapper.
# Contract: same-repo nested shells reuse the inherited direnv environment;
# shells moved to another repo get one 15-second-bounded refresh and fail open.
# IN_NIX_SHELL=impure from direnv is valid; do not recover with nix develop.

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

# Allow is idempotent (whitelist still requires an allow record on some
# direnv builds). Then export the cached flake env. Impure is expected.
direnv allow . >/dev/null 2>&1 || true
unset DIRENV_DIFF DIRENV_WATCHES
eval "$(timeout 15s direnv export bash 2>/dev/null)" || true
# Child bash (Claude/Codex/goose/kimi/vtcode) reuses this loader via BASH_ENV.
export BASH_ENV="${BASH_ENV:-$HOME/.dotfiles/shell/bash/noninteractive-path.sh}"
