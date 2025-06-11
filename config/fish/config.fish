# Fish Shell Configuration
# ~/.dotfiles/config/fish/config.fish

# Source common environment variables
if test -f ~/.dotfiles/config/common/env.sh
    bass source ~/.dotfiles/config/common/env.sh
end

# Mise integration
if command -v mise &> /dev/null
    mise activate fish | source
end

# Starship prompt
if command -v starship &> /dev/null
    starship init fish | source
end

# Zoxide (smart cd)
if command -v zoxide &> /dev/null
    zoxide init fish --cmd cd | source
end

# FZF integration
if command -v fzf &> /dev/null
    fzf --fish | source
end

# Common aliases (converted to fish syntax)
alias ls='eza'
alias ll='eza -la --git --time-style=relative'
alias la='eza -a'
alias l='eza -l --git'
alias tree='eza --tree'
alias cat='bat --paging=never'
alias grep='rg'
alias find='fd --threads=4'
alias sed='sd'
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

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get services'

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Shell switching
alias sh-switch='~/.dotfiles/.scripts/shell-switcher.sh'
alias sh-bash='exec bash --login'
alias sh-zsh='exec zsh'
alias sh-nu='exec nu'

# Fish-specific features
function fish_greeting
    echo "🐟 Welcome to Fish Shell"
    echo "   Type 'help' for Fish documentation"
    echo "   Type 'sh-switch' to change shells"
end

# Smart repo navigation (Fish version)
function c
    if test (count $argv) -eq 0
        cd ~/code
        return
    end
    
    set -l pattern $argv[1]
    set -l matches (fd -t d -d 1 "*$pattern*" ~/code --base-directory ~/code 2>/dev/null)
    
    switch (count $matches)
        case 0
            echo "No repos matching '$pattern'"
            return 1
        case 1
            cd ~/code/$matches[1]
        case '*'
            set -l selected (printf '%s\n' $matches | fzf --reverse --height=40% --prompt="Multiple matches for '$pattern': ")
            if test -n "$selected"
                cd ~/code/$selected
            end
    end
end

# Create dynamic aliases for repos
if test -d ~/code
    for dir in (fd -t d -d 1 . ~/code --base-directory ~/code 2>/dev/null)
        set -l alias_name "c$dir"
        if not command -v $alias_name &> /dev/null
            alias $alias_name="cd ~/code/$dir"
        end
    end
end

# Claude shell
alias claude-shell='~/.dotfiles/.scripts/claude-shell.sh'
alias safe-run='~/.dotfiles/.scripts/claude-safe-wrapper.sh'

# Fish key bindings
bind \ct 'fzf-file-widget'
bind \cr 'fzf-history-widget'
bind \ec 'fzf-cd-widget'