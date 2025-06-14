#!/usr/bin/env zsh
#
# Minimal zshrc - Sandboxed from system configs
# Purpose: Clean zsh environment without system pollution
# Version: 1.0.0

# Skip all system-wide zsh configs
setopt no_global_rcs

# Essential PATH only
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# Add npm global bin and scripts
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.scripts:$PATH"

# Basic environment
export EDITOR=${EDITOR:-nano}
export PAGER=${PAGER:-less}
export TERM=${TERM:-xterm-256color}

# Better history
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt share_history
setopt hist_ignore_dups

# Essential aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# Load mise if available
if [ -f "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate zsh)" 2>/dev/null || true
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# Load tokens if available
if [ -f "$HOME/.env_tokens" ]; then
  set -a
  source "$HOME/.env_tokens" 2>/dev/null || true
  set +a
fi

# Add dotfiles tools
if [ -d "$HOME/.dotfiles/tools" ]; then
  export PATH="$HOME/.dotfiles/tools:$PATH"
fi

# Load aliases if available
if [ -f "$HOME/.dotfiles/.aliases" ]; then
  source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Claude aliases
if [ -f "$HOME/.npm-global/bin/claude-yolo" ]; then
  alias claude-yolo="$HOME/.npm-global/bin/claude-yolo"
fi

if [ -f "$HOME/.claude/local/claude" ]; then
  alias claude="$HOME/.claude/local/claude"
fi

# Enable fzf if available
if command -v fzf &>/dev/null; then
  eval "$(fzf --zsh)" 2>/dev/null || true
fi

# Simple prompt if no starship
if ! command -v starship &>/dev/null; then
  PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '
else
  eval "$(starship init zsh)"
fi