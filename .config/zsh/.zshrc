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

# Add all mise tool paths to PATH
for tool_path in $HOME/.local/share/mise/installs/*/*; do
  if [ -d "$tool_path" ] && [ -x "$tool_path" ]; then
    case "$tool_path" in
      */bin) export PATH="$tool_path:$PATH" ;;
      *) export PATH="$tool_path:$PATH" ;;
    esac
  fi
done

# Initialize tools that need it BEFORE loading aliases
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
fi

if command -v starship &>/dev/null; then
  eval "$(starship init zsh)"
fi

if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

# Load aliases if available
if [ -f "$HOME/.dotfiles/.aliases" ]; then
  source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Claude aliases
if [ -f "$HOME/.npm-global/bin/claude-yolo" ]; then
  # Package managers handled by mise/pnpm
fi

if [ -f "$HOME/.claude/local/claude" ]; then
  # claude now handled by global package manager
fi

# Use pnpm instead of npm/npx/yarn
alias npm="echo 'Use pnpm instead!' && false"
alias npx="echo 'Use pnpm dlx instead!' && false"
alias yarn="echo 'Use pnpm instead!' && false"

# pnpm shortcuts
alias pn="pnpm"
alias pnx="pnpm dlx"

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