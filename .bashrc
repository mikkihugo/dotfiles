#!/bin/bash
#
# Copyright 2024 Mikki Hugo. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# Minimal bashrc for distfiles/base system compatibility
# Purpose: Provide absolute minimum shell environment that works everywhere
# Version: 1.0.0
# Dependencies: None (uses only POSIX/bash built-ins)

# Exit early if not running interactively
[[ $- != *i* ]] && return

# Essential PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# Basic environment
export EDITOR=${EDITOR:-nano}
export PAGER=${PAGER:-less}
export TERM=${TERM:-xterm-256color}

# Minimal history
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoreboth
shopt -s histappend

# Basic completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Essential aliases only
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Auto-upgrade to better shell if available and on SSH
if [ -n "$SSH_CONNECTION" ] && [ -z "$SHELL_UPGRADED" ]; then
    export SHELL_UPGRADED=1
    
    # Prefer fish first (if available), then zsh, then stay in bash
    if command -v fish >/dev/null 2>&1; then
        echo "🐟 Upgrading to fish..."
        exec fish
    elif command -v zsh >/dev/null 2>&1; then
        echo "🚀 Upgrading to zsh..."
        exec zsh
    fi
    # If neither fish nor zsh available, stay in bash
fi

# mise activation (lightweight check)
if [ -f "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)" 2>/dev/null || true
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# Multi-Environment File Loading
# Load in priority order: base configs → specific configs → local overrides

# Function to safely load environment files
load_env_file() {
    if [ -f "$1" ]; then
        set -a  # Auto-export all variables
        source "$1" 2>/dev/null || echo "Warning: Failed to load $1" >&2
        set +a
    fi
}

# Load environment files in order (later files override earlier ones)
load_env_file "$HOME/.env_tokens"    # Personal tokens (from private gist)
load_env_file "$HOME/.env_ai"        # AI service configurations  
load_env_file "$HOME/.env_docker"    # Container & Docker configs
load_env_file "$HOME/.env_repos"     # Repository & project paths
load_env_file "$HOME/.env_local"     # Local machine overrides (not synced)

# Load dotfiles if available (but don't fail if missing)
if [ -f "$HOME/.dotfiles/.aliases" ]; then
    source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Add dotfiles tools if available
if [ -d "$HOME/.dotfiles/tools" ]; then
    export PATH="$HOME/.dotfiles/tools:$PATH"
fi

# Add npm global bin
export PATH="$HOME/.npm-global/bin:$PATH"

# Add scripts to PATH
export PATH="$HOME/.scripts:$PATH"

# SQLite3 library path for Python
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Initialize starship if available
if command -v starship &>/dev/null; then
  eval "$(starship init bash)"
fi

# Initialize zoxide if available
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi

# Claude CLI
if [ -f "$HOME/.claude/local/claude" ]; then
    # claude now handled by npm global (via pnpm)
fi

# Load bash.d modules (except guardian which can interfere)
if [ -d "$HOME/.dotfiles/config/bash.d" ]; then
    for module in "$HOME/.dotfiles/config/bash.d"/*.sh; do
        if [ -r "$module" ]; then
            # Skip loading guardian module unless explicitly enabled
            if [[ "$(basename "$module")" == "01-failsafe.sh" ]] && [ "$ENABLE_SHELL_GUARDIAN" != "1" ]; then
                continue
            fi
            source "$module"
        fi
    done
fi

export COMPOSE_PROJECT_NAME=hugo-server
# Use pnpm instead of npm/npx/yarn
alias npm="echo 'Use pnpm instead!' && false"
alias npx="echo 'Use pnpm dlx instead!' && false"
alias yarn="echo 'Use pnpm instead!' && false"

# pnpm shortcuts
alias pn="pnpm"
alias pnx="pnpm dlx"
