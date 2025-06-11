# Minimal Failsafe Module
# This module provides the absolute minimum environment needed to recover from crashes

# Check if running in guardian failsafe mode
if [ -n "$SHELL_GUARDIAN_ACTIVE" ]; then
  echo "🔒 Running in Guardian FAILSAFE mode"
  echo "💡 Edit modules safely in ~/.dotfiles/config/bash.d/"
  echo "💡 Return to normal mode with: exit"
  
  # Provide essential tools for recovery
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
  
  # Simple prompt indicating failsafe mode
  export PS1="\[\033[1;31m\][FAILSAFE]\[\033[0m\] \w \$ "
  
  # Enable command completion
  if [ -f /etc/bash_completion ]; then
    source /etc/bash_completion
  fi
  
  # Failsafe aliases for recovery
  alias edit-bashrc="nano ~/.dotfiles/config/bashrc"
  alias edit-module="nano ~/.dotfiles/config/bash.d/"
  alias list-modules="ls -la ~/.dotfiles/config/bash.d/"
  alias test-module="bash -n"
  
  # Instructions function
  shell_help() {
    echo -e "\033[1;34mShell Guardian - Failsafe Mode\033[0m"
    echo -e "\033[1;33mUseful commands:\033[0m"
    echo "  edit-bashrc         - Edit core bashrc file"
    echo "  edit-module MODULE  - Edit a specific module"
    echo "  list-modules        - List all available modules"
    echo "  test-module FILE    - Check module for syntax errors"
    echo "  shell_help          - Show this help message"
    echo -e "\033[1;33mTo exit failsafe mode:\033[0m"
    echo "  exit                - Exit to login shell"
  }
  
  # Display help on startup
  shell_help
  
  # Nothing more to load in failsafe mode
  return 0
fi

# Install shell guardian if not already installed
if [ ! -f "$HOME/.local/bin/shell-guardian" ] && [ -f "$HOME/.dotfiles/.scripts/install-shell-guardian.sh" ]; then
  echo "🔒 Shell Guardian not found, would you like to install it? (y/n)"
  read -r install_guardian
  if [[ "$install_guardian" =~ ^[Yy]$ ]]; then
    "$HOME/.dotfiles/.scripts/install-shell-guardian.sh"
  else
    echo "🔒 Skipping Shell Guardian installation"
  fi
fi

# Schedule failsafe integrity checks via mise on every login
if command -v mise &>/dev/null; then
  # Run failsafe check on login (once per session)
  if [ -z "$FAILSAFE_CHECK_DONE" ] && [ -f "$HOME/.dotfiles/.mise/tasks/failsafe-check.sh" ]; then
    export FAILSAFE_CHECK_DONE=1
    "$HOME/.dotfiles/.mise/tasks/failsafe-check.sh" &
  fi
fi