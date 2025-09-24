#!/bin/bash
# Shared environment loader for dotfiles

export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"

load_env_file() {
  local file=$1
  if [[ -f "$file" ]]; then
    set -a
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

# Ensure local bin paths are present
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

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
