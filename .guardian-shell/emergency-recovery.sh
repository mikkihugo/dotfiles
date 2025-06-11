#!/bin/bash
# EMERGENCY RECOVERY SCRIPT - ULTRA MINIMAL
# This script provides absolute minimal recovery in case all else fails
# To use: bash ~/.dotfiles/.guardian-shell/emergency-recovery.sh
# This will give you a minimal shell to fix your environment

# Ensure script runs even if sourced
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0
if [ "$SOURCED" -eq 1 ]; then
  echo "⚠️ EMERGENCY RECOVERY must be executed, not sourced"
  echo "💡 Run: bash ~/.dotfiles/.guardian-shell/emergency-recovery.sh"
  return 1
fi

# Minimal environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
export TERM="xterm-256color"
export PS1="\[\033[31m\][EMERGENCY]\[\033[0m\] \w \$ "
export EMERGENCY_RECOVERY=1

# Safety function to restore broken .bashrc
fix_bashrc() {
  cat > "$HOME/.bashrc" << 'EOF'
# EMERGENCY MINIMAL .bashrc
# Created by emergency recovery script

# Exit early if not running interactively
[[ $- != *i* ]] && return

# Basic prompt and environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
EOF
  echo "✅ Created minimal .bashrc"
}

# Safety function to restore broken .bash_profile
fix_profile() {
  cat > "$HOME/.bash_profile" << 'EOF'
# EMERGENCY MINIMAL .bash_profile
# Created by emergency recovery script

# Source bashrc
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi
EOF
  echo "✅ Created minimal .bash_profile"
}

# Function to create a minimal shell guardian
create_guardian() {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/shell-guardian" << 'EOF'
#!/bin/bash
# Minimal emergency guardian

# Run the requested shell with minimal environment
exec "$@"
EOF
  chmod +x "$HOME/.local/bin/shell-guardian"
  echo "✅ Created minimal shell guardian"
}

# Create a basic help command
help() {
  echo -e "\033[1;34mEMERGENCY RECOVERY - HELP\033[0m"
  echo -e "\033[1;33mAvailable commands:\033[0m"
  echo "  fix_bashrc    - Create minimal .bashrc"
  echo "  fix_profile   - Create minimal .bash_profile"
  echo "  create_guardian - Create minimal shell guardian"
  echo "  fix_all       - Fix all critical files"
  echo "  help          - Show this help"
}

# Fix everything at once
fix_all() {
  fix_bashrc
  fix_profile
  create_guardian
  echo "✅ Critical files restored"
  echo "💡 Log out and back in to use restored environment"
}

# Main function
main() {
  echo -e "\033[31m⚠️ EMERGENCY RECOVERY MODE\033[0m"
  echo -e "\033[33m💡 Type 'help' for available commands\033[0m"
  echo -e "\033[33m💡 Type 'fix_all' to restore critical files\033[0m"
  
  # Start bash in this environment
  /bin/bash --norc
}

# Run main function
main