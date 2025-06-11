#!/usr/bin/env fish
#
# Minimal fish config - Clean sandbox environment
# Purpose: Essential fish shell without system configs
# Version: 1.0.0

# Essential PATH
set -x PATH /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin $HOME/.local/bin $HOME/bin

# Basic environment
set -x EDITOR (command -v nano)
set -x PAGER less
set -x TERM xterm-256color

# Load mise if available
if test -f "$HOME/.local/bin/mise"
    $HOME/.local/bin/mise activate fish | source
end

# Load tokens if available
if test -f "$HOME/.env_tokens"
    for line in (cat $HOME/.env_tokens | grep -v '^#' | grep '=')
        set -x (echo $line | cut -d= -f1) (echo $line | cut -d= -f2-)
    end
end

# Add dotfiles tools
if test -d "$HOME/.dotfiles/tools"
    set -x PATH $HOME/.dotfiles/tools $PATH
end

# Simple prompt if no starship
if not command -v starship &>/dev/null
    function fish_prompt
        echo (whoami)'@'(hostname)':'(prompt_pwd)'$ '
    end
else
    starship init fish | source
end

# Essential abbreviations (fish's aliases)
abbr ll 'ls -alF'
abbr la 'ls -A'
abbr l 'ls -CF'