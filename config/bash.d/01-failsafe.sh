# Ultra-Minimal Failsafe Module
# Provides absolute minimum environment for shell recovery

# Check if running in guardian failsafe mode
if [ -n "$SHELL_GUARDIAN_ACTIVE" ]; then
  # We are in failsafe mode
  echo "🔒 Guardian FAILSAFE mode active"
  
  # Provide essential tools for recovery
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
  
  # Simple prompt indicating failsafe mode
  export PS1="\[\033[1;31m\][FAILSAFE]\[\033[0m\] \w \$ "
  
  # Essential recovery commands
  shell_help() {
    echo -e "\033[1;34mRecovery Commands:\033[0m"
    echo "  e FILE     - Edit file with nano"
    echo "  fix-rc     - Fix bashrc with nano"
    echo "  check-rc   - Check bashrc for syntax errors"
    echo "  modules    - List bash modules"
    echo "  fix-all    - Run integrity check and repair"
    echo "  restart    - Exit failsafe and restart shell"
  }
  
  # Simple recovery aliases
  alias e="nano"
  alias fix-rc="nano ~/.dotfiles/config/bashrc"
  alias check-rc="bash -n ~/.dotfiles/config/bashrc && echo 'Syntax OK'"
  alias modules="ls -la ~/.dotfiles/config/bash.d/"
  alias fix-all="~/.dotfiles/.scripts/verify-failsafe-integrity.sh"
  alias restart="exit"
  
  # Show help on startup
  shell_help
  
  # Nothing more to load in failsafe mode
  return 0
fi

# Run failsafe check on login (once per session)
if command -v mise &>/dev/null && [ -z "$FAILSAFE_CHECK_DONE" ] && [ -f "$HOME/.dotfiles/.mise/tasks/failsafe-check.sh" ]; then
  export FAILSAFE_CHECK_DONE=1
  "$HOME/.dotfiles/.mise/tasks/failsafe-check.sh" &
fi

# Guardian is currently disabled to prevent interference
# To enable guardian protection, set ENABLE_SHELL_GUARDIAN=1
if [ "$ENABLE_SHELL_GUARDIAN" = "1" ] && [ ! -f "$HOME/.local/bin/shell-guardian" ]; then
  # Protected directory for critical files
  GUARDIAN_DIR="$HOME/.dotfiles/.guardian-shell"
  
  # Try using pre-compiled binary first
  if [ -f "${GUARDIAN_DIR}/shell-guardian" ]; then
    mkdir -p "$HOME/.local/bin"
    cp "${GUARDIAN_DIR}/shell-guardian" "$HOME/.local/bin/shell-guardian"
    chmod +x "$HOME/.local/bin/shell-guardian"
    echo "✅ Shell Guardian activated"
  fi
fi