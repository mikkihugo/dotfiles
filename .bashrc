# Cleaned and optimized .bashrc

# mise activation
if [ -f "$HOME/.local/bin/mise" ]; then
  eval "$("$HOME/.local/bin/mise" activate bash)"
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  
  # Auto-install missing tools (async to avoid blocking login)
  if [ -z "$MISE_AUTO_INSTALL_DONE" ]; then
    export MISE_AUTO_INSTALL_DONE=1
    (
      # Get all missing tools
      all_missing=$(mise ls --missing --quiet 2>/dev/null)
      missing_count=$(echo "$all_missing" | wc -w)
      
      if [ -n "$all_missing" ] && [ "$missing_count" -gt 0 ]; then
        echo "🔧 Auto-installing $missing_count missing mise tools..."
        
        # Install all missing tools at once (faster)
        mise install >> ~/.mise_auto_install.log 2>&1 && {
          echo "✅ All mise tools installed successfully"
        } || {
          echo "⚠️  Some tools failed to install (check ~/.mise_auto_install.log)"
          echo "   Failed tools may need manual installation"
        }
        
        # Update to latest versions for critical tools if they were just installed
        critical_tools="node python"
        echo "🔄 Updating critical tools to latest..."
        for tool in $critical_tools; do
          mise install "$tool@latest" >> ~/.mise_auto_install.log 2>&1 && echo "  ✅ $tool@latest" || echo "  ⚠️ $tool update failed"
        done
      else
        echo "✅ All mise tools are up to date"
      fi
    ) &
  fi
else
  echo "mise not found, installing automatically..."
  # Create installer script
  cat > "$HOME/.mise_installer.sh" << 'EOF'
#!/bin/bash
set -e
MISE_DEST="$HOME/.local/bin/mise"
MISE_TEMP="$HOME/.mise_tmp"
mkdir -p "$HOME/.local/bin"
mkdir -p "$MISE_TEMP"
cd "$MISE_TEMP"

# Try several methods to download the installer
if command -v curl &>/dev/null; then
  curl -fsSL https://mise.run > install.sh
elif command -v wget &>/dev/null; then
  wget -q -O install.sh https://mise.run
elif command -v fetch &>/dev/null; then
  fetch -q -o install.sh https://mise.run
else
  echo "No download tool found (curl, wget, fetch)"
  exit 1
fi

chmod +x install.sh
./install.sh
rm -rf "$MISE_TEMP"
EOF
  
  # Make executable and run
  chmod +x "$HOME/.mise_installer.sh"
  "$HOME/.mise_installer.sh"
  rm -f "$HOME/.mise_installer.sh"
  
  if [ -f "$HOME/.local/bin/mise" ]; then
    eval "$("$HOME/.local/bin/mise" activate bash)"
    export PATH="$HOME/.local/share/mise/shims:$PATH"
  fi
fi

# unset mise function if it exists (to use the binary instead)
unset -f mise 2>/dev/null || true

# starship prompt
if command -v starship &> /dev/null; then
  eval "$(starship init bash)"
else
  echo "starship not found, skipping prompt setup"
fi

# zoxide (smart cd)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init bash)"
  alias cd="z"
fi

# FZF configuration
if command -v fzf &> /dev/null; then
  # Source FZF bash integration
  eval "$(fzf --bash)"
  
  # Load custom FZF config
  if [ -f "$HOME/.config/fzf/config.sh" ]; then
    source "$HOME/.config/fzf/config.sh"
  fi
fi

# Enhanced bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Better history search (only in interactive mode)
if [[ $- == *i* ]]; then
  bind '"\e[A": history-search-backward' 2>/dev/null || true
  bind '"\e[B": history-search-forward' 2>/dev/null || true
  bind '"\C-p": history-search-backward' 2>/dev/null || true
  bind '"\C-n": history-search-forward' 2>/dev/null || true
fi

# Enhanced history settings
export HISTSIZE=50000
export HISTFILESIZE=50000
export HISTCONTROL=ignoreboth:erasedups
export HISTIGNORE="ls:cd:cd -:pwd:exit:date:* --help"
shopt -s histappend
shopt -s cmdhist

# Better cd behavior
shopt -s autocd
shopt -s cdspell
shopt -s dirspell

# Disable mouse reporting to prevent garbage characters
printf '\e[?1000l' 2>/dev/null || true

# Disable paging for continuous scrolling
export PAGER=cat

# Terminal settings for better colors
export TERM=xterm-256color
export COLORTERM=truecolor

# API Keys moved to ~/.env_tokens for security

# Add custom paths if needed
export PATH="$PATH:/home/mhugo/.local/bin:/home/mhugo/bin"

# SQLite3 library path for Python
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Load aliases (dotfiles version)
if [ -f "$HOME/.dotfiles/.aliases" ]; then
    source "$HOME/.dotfiles/.aliases"
elif [ -f "$HOME/.aliases" ]; then
    source "$HOME/.aliases"
fi

# Add dotfiles scripts to PATH
export PATH="$HOME/.dotfiles/.scripts:$PATH"

# Auto-load tokens from ~/.env_tokens (all API keys)
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens"
    set +a
fi

# Load project-specific .env if in a project directory
if [ -f ".env" ] && [ "$PWD" != "$HOME" ]; then
    set -a
    source ".env"
    set +a
fi

# Load git config from dotfiles
if [ -f "$HOME/.dotfiles/.gitconfig" ]; then
    git config --global include.path "$HOME/.dotfiles/.gitconfig"
fi
alias claude="/home/mhugo/.claude/local/claude"
alias claude-unsafe="/home/mhugo/claude-unsafe/safety-wrapper.sh"

# pnpm
export PNPM_HOME="/home/mhugo/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
export PATH="$HOME/.npm-global/bin:$PATH"

# Auto-install everything possible on first login (once)
if [ ! -f "$HOME/.dotfiles/.auto-install-done" ]; then
    if [ -f "$HOME/.dotfiles/.scripts/auto-install.sh" ]; then
        echo "🚀 First login detected - auto-installing everything possible..."
        echo "⏳ This will take a few minutes but only happens once..."
        (cd "$HOME/.dotfiles" && ./.scripts/auto-install.sh > ~/.dotfiles/auto-install.log 2>&1 && touch ~/.dotfiles/.auto-install-done) &
        echo "📋 Installation running in background. Check: tail -f ~/.dotfiles/auto-install.log"
    fi
fi

# Check for system dependencies
if [ ! -f "$HOME/.dotfiles/.system-deps-installed" ]; then
    echo "💡 System packages needed. Run: mise run system-deps"
fi

# Quick async check for dotfiles updates on login
if [ -f "$HOME/.dotfiles/.scripts/quick-check.sh" ]; then
    # Quick hash check (fast, non-blocking)
    if ! "$HOME/.dotfiles/.scripts/quick-check.sh" check >/dev/null 2>&1; then
        echo "📦 Updates found! Syncing dotfiles..."
        # Auto-sync in background
        (cd "$HOME/.dotfiles" && "$HOME/.dotfiles/.scripts/quick-check.sh" sync >/dev/null 2>&1 &)
    fi
fi

# Simple session management - no menus, just quick commands
if [ -f "$HOME/.dotfiles/.scripts/simple-sessions.sh" ]; then
    source "$HOME/.dotfiles/.scripts/simple-sessions.sh"
fi

# Terminal-specific configurations
# Default terminal
export TERMINAL_APP="default"

# Claude Context Commands
alias claude-remind='bash ~/singularity-engine/.repo/scripts/claude-remind.sh'
alias cr='claude-remind'  # Short version

# Retro Login Tool
alias rl='bash ~/.dotfiles/.scripts/retro-login.sh'
alias retro='bash ~/.dotfiles/.scripts/retro-login.sh'

# Mise quick commands
alias mise-fix='unset MISE_AUTO_INSTALL_DONE && source ~/.bashrc'
alias mise-log='tail -f ~/.mise_auto_install.log'

# Auto-reminder on new terminal sessions
# Uncomment to auto-show reminder:
# claude-remind

# Tabby working directory reporting (for SFTP and copy path features)
if [ -n "$TABBY_SESSION_ID" ] || [ -n "$TERM_PROGRAM" ]; then
    export PS1="$PS1\[\e]1337;CurrentDir="'$(pwd)\a\]'
fi

# Auto-launch retro login on SSH login (desktop only) - TEMPORARILY DISABLED
if false && [ -n "$SSH_CONNECTION" ] && [ -z "$RETRO_LOGIN_LAUNCHED" ]; then
    # Check if we're on a desktop (screen width detection)
    if command -v tput >/dev/null 2>&1; then
        screen_width=$(tput cols 2>/dev/null || echo "0")
        
        # Only launch if screen is wide enough (desktop)
        if [ "$screen_width" -ge 80 ]; then
            export RETRO_LOGIN_LAUNCHED=1
            echo "🚀 Launching Retro Login..."
            bash ~/.dotfiles/.scripts/retro-login.sh
        else
            echo "📱 Mobile screen detected (${screen_width} cols) - skipping retro login"
            echo "💡 Use 'rl' or 'retro' to launch manually"
        fi
    else
        # Fallback - check TERM for mobile indicators
        case "$TERM" in
            *mobile*|*android*|*iphone*)
                echo "📱 Mobile terminal detected - skipping retro login"
                echo "💡 Use 'rl' or 'retro' to launch manually"
                ;;
            *)
                export RETRO_LOGIN_LAUNCHED=1
                echo "🚀 Launching Retro Login..."
                bash ~/.dotfiles/.scripts/retro-login.sh
                ;;
        esac
    fi
fi

# Fix resource limits for thread pools
ulimit -u 4096 2>/dev/null || true

# Deno configuration (disabled - using Node.js instead)
# To re-enable Deno as Node replacement, uncomment the functions below

# Ensure node/npm/npx use actual Node.js, not Deno
unalias node 2>/dev/null || true
unalias npm 2>/dev/null || true
unalias npx 2>/dev/null || true

# Claude CLI completion
_claude_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        # First argument - show main commands
        COMPREPLY=( $(compgen -W "update claude-yolo --help --version --model --config --memory --mode" -- "${cur}") )
    elif [[ ${prev} == "--model" || ${prev} == "-m" ]]; then
        # Model completion
        COMPREPLY=( $(compgen -W "claude-opus-4-20250514 claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022" -- "${cur}") )
    elif [[ ${prev} == "--mode" ]]; then
        # Mode completion
        COMPREPLY=( $(compgen -W "code architect" -- "${cur}") )
    else
        # Default to file completion
        COMPREPLY=( $(compgen -f -- "${cur}") )
    fi
}

complete -F _claude_completions claude

# Auto-attach to zellij session on login (SSH only)
if [ -n "$SSH_CONNECTION" ] && command -v zellij &> /dev/null; then
    if ! zellij list-sessions | grep -q "claude-session"; then
        echo "🚀 Starting zellij claude session..."
        zellij --session claude-session
    else
        echo "📋 Attaching to existing zellij claude session..."
        zellij attach claude-session
    fi
fi