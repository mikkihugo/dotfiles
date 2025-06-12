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
    
    # Try zsh first, then fish, then stay in bash
    if command -v zsh >/dev/null 2>&1; then
        echo "🚀 Upgrading to zsh..."
        exec zsh
    elif command -v fish >/dev/null 2>&1; then
        echo "🐟 Upgrading to fish..."
        exec fish
    fi
fi

# mise activation (lightweight check)
if [ -f "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)" 2>/dev/null || true
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# Auto-load tokens from gist backup (if available)
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens" 2>/dev/null || true
    set +a
fi

# Load dotfiles if available (but don't fail if missing)
if [ -f "$HOME/.dotfiles/.aliases" ]; then
    source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Add dotfiles tools if available
if [ -d "$HOME/.dotfiles/tools" ]; then
    export PATH="$HOME/.dotfiles/tools:$PATH"
fi
# AI API Keys - Added by Nexus setup
export GITHUB_TOKEN=$(gh auth token 2>/dev/null)
export GOOGLE_AI_PERSONAL_FREE="AIzaSyA5Di0rwS2vLRbzgyRdGlF7V-tTTVBck_0"
export CF_API_TOKEN="4d8d4b4c4ab849f6934face0f36e201f7bddc"

# Aliases for the keys with common names
export GOOGLE_AI="$GOOGLE_AI_PERSONAL_FREE"
export GOOGLE_AI_KEY="$GOOGLE_AI_PERSONAL_FREE"
export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
EOF < /dev/null
export PATH="$HOME/.npm-global/bin:$PATH"
