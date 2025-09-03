#!/bin/bash
# Fallback normal bash configuration
# Use this when guardian system or advanced features cause issues
# To activate: cp ~/.dotfiles/config/bash.d/99-fallback-normal.sh ~/.bashrc

# Exit early if not running interactively
[[ $- != *i* ]] && return

# Essential PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$HOME/bin"

# Basic environment
export EDITOR=nano
export PAGER=less
export TERM=xterm-256color

# History
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

# Basic prompt
PS1='\u@\h:\w\$ '

# Load API tokens if available
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens" 2>/dev/null || true
    set +a
fi

# Development tools paths
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.scripts:$PATH"

# SQLite3 library path for Python
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# mise activation (for Node.js, Python, etc.)
if command -v mise &> /dev/null; then
  eval "$(mise activate bash)"
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

# Load custom aliases if available
if [ -f "$HOME/.aliases" ]; then
    source "$HOME/.aliases"
fi

# Claude CLI aliases
if [ -f "/usr/local/bin/claude" ]; then
    alias claude="/usr/local/bin/claude"
    alias claude-yolo="/usr/local/bin/claude --dangerously-skip-permissions"
fi