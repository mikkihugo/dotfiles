#!/usr/bin/env fish
#
# Minimal fish config - Clean sandbox environment
# Purpose: Essential fish shell without system configs
# Version: 1.0.0

# Essential PATH
set -x PATH /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin $HOME/.local/bin $HOME/bin
set -x PATH $HOME/.npm-global/bin $PATH
set -x PATH $HOME/.scripts $PATH
set -x PATH $HOME/.cargo/bin $PATH

# Basic environment
set -x EDITOR (command -v nano)
set -x PAGER less
set -x TERM xterm-256color

# Load mise if available
if test -f "$HOME/.local/bin/mise"
    $HOME/.local/bin/mise activate fish | source
    set -x PATH $HOME/.local/share/mise/shims $PATH
end

# Add all mise tool paths
for tool_path in $HOME/.local/share/mise/installs/*/*
    if test -d "$tool_path" -a -x "$tool_path"
        set -x PATH $tool_path $PATH
    end
end

# Load tokens if available - handle export prefix
if test -f "$HOME/.env_tokens"
    for line in (cat $HOME/.env_tokens | grep -v '^#' | grep '=' | sed 's/^export //')
        set var_name (echo $line | cut -d= -f1)
        set var_value (echo $line | cut -d= -f2-)
        # Remove quotes if present
        set var_value (echo $var_value | sed 's/^"//;s/"$//')
        set -x $var_name $var_value
    end
end

# Add dotfiles tools
if test -d "$HOME/.dotfiles/tools"
    set -x PATH $HOME/.dotfiles/tools $PATH
end

# Initialize tools
if command -v starship &>/dev/null
    starship init fish | source
else
    # Simple prompt if no starship
    function fish_prompt
        echo (whoami)'@'(hostname)':'(prompt_pwd)'$ '
    end
end

if command -v zoxide &>/dev/null
    zoxide init fish | source
end

if command -v direnv &>/dev/null
    direnv hook fish | source
end

# Load aliases - create fish-compatible versions
if test -f "$HOME/.dotfiles/.config/fish/aliases.fish"
    source "$HOME/.dotfiles/.config/fish/aliases.fish"
end

# Essential abbreviations (fish's aliases)
abbr ll 'ls -alF'
abbr la 'ls -A'
abbr l 'ls -CF'

# Git abbreviations
if command -v git &>/dev/null
    abbr g 'git'
    abbr gs 'git status'
    abbr ga 'git add'
    abbr gc 'git commit'
    abbr gp 'git push'
    abbr gl 'git pull'
    abbr gd 'git diff'
end

# Claude
if test -f "$HOME/.claude/local/claude"
    # claude now handled by global package manager
end

if test -f "$HOME/.npm-global/bin/claude-yolo"
    # Package managers handled by mise/pnpm
end

# Use pnpm instead of npm/npx/yarn
alias npm="echo 'Use pnpm instead!' && false"
alias npx="echo 'Use pnpm dlx instead!' && false"
alias yarn="echo 'Use pnpm instead!' && false"

# pnpm shortcuts
alias pn="pnpm"
alias pnx="pnpm dlx"

# Ensure mise shims are in PATH for proper command interception
if test -d "$HOME/.local/share/mise/shims"
    set -gx PATH "$HOME/.local/share/mise/shims" $PATH
end