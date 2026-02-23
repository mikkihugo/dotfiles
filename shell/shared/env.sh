#!/bin/bash
# Shared environment loader for dotfiles

export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

load_env_file() {
	local file=$1
	if [[ -f "$file" ]]; then
		set -a
		# shellcheck source=/dev/null
		source "$file"
		set +a
	fi
}

# Load standard env files if they exist
# Legacy env files (will be replaced by SOPS)
load_env_file "$HOME/.env_tokens"
load_env_file "$HOME/.env_ai"
load_env_file "$HOME/.env_docker"
load_env_file "$HOME/.env_repos"
load_env_file "$HOME/.env_local"

# SOPS-managed environment (if available)
if command -v sops >/dev/null 2>&1 && [[ -f "$DOTFILES_ROOT/secrets/shared.yaml" ]]; then
	# Export SOPS-decrypted variables directly
	eval "$(sops -d "$DOTFILES_ROOT/secrets/shared.yaml" | grep -E '^[A-Z_]+=' | sed 's/^/export /')"
fi

# Nix daemon (multi-user install) — ensure nix CLI and user profile are on PATH
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
	# shellcheck source=/dev/null
	. '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# nix binary lives in the system profile, not the user profile — add it explicitly
case ":${PATH}:" in
*":/nix/var/nix/profiles/default/bin:"*) ;;
*) export PATH="/nix/var/nix/profiles/default/bin:${PATH}" ;;
esac

# Local bin paths are now managed by Nix flake
# Only add $HOME/bin if not already present (for non-Nix environments)
case ":$PATH:" in
*:"$HOME/bin":*) ;;
*) export PATH="$HOME/bin:$PATH" ;;
esac

# pnpm managed bin
if [[ -d "$HOME/.local/share/pnpm" ]]; then
	export PNPM_HOME="$HOME/.local/share/pnpm"
	case ":$PATH:" in
	*:"$PNPM_HOME":*) ;;
	*) export PATH="$PNPM_HOME:$PATH" ;;
	esac
fi

export EDITOR=${EDITOR:-nvim}
export PAGER=${PAGER:-less}
export TERM=${TERM:-xterm-256color}

unset -f load_env_file
