# Common aliases for all shells
# This file should use POSIX-compatible syntax

# Modern rust replacements
alias ls='eza'
alias ll='eza -la --git --time-style=relative'
alias la='eza -a'
alias l='eza -l --git'
alias tree='eza --tree'
alias ps='procs'
alias du='dust'
alias df='duf'
alias top='btop'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='cd ~/code'

# Git shortcuts
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# Docker
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias di='docker images'

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Quick edits
alias dotfiles='cd ~/.dotfiles'
alias reload='exec $SHELL -l'

# Shell switching
alias sh-switch='~/.dotfiles/.scripts/shell-switcher.sh'
alias sh-bash='exec bash --login'
alias sh-zsh='exec zsh'
alias sh-nu='exec nu'
