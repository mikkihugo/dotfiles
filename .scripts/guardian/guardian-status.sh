#!/bin/bash
# Guardian status indicator
# This script provides a simple status indicator for shell prompts
# Usage: source ~/.dotfiles/.scripts/guardian/guardian-status.sh

# Guardian binary path
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"

# Get guardian status - returns an emoji indicator
guardian_status() {
  # Check if binary exists
  if [ ! -f "$GUARDIAN_BIN" ]; then
    echo "❌" # Missing
    return
  fi
  
  # Check if verify-guardian exists
  if ! command -v verify-guardian &>/dev/null; then
    echo "⚠️" # No verification tool
    return
  fi
  
  # Run quick verification (exit status only)
  if verify-guardian &>/dev/null; then
    echo "🔒" # Verified
  else
    echo "🔓" # Failed verification
  fi
}

# Add to PS1 if requested
if [ "$1" = "prompt" ]; then
  # For bash
  if [ -n "$BASH_VERSION" ]; then
    PS1_OLD="$PS1"
    PS1="\$(guardian_status) $PS1"
  # For zsh
  elif [ -n "$ZSH_VERSION" ]; then
    setopt PROMPT_SUBST
    PS1="\$(guardian_status) $PS1"
  fi
fi

# If run directly, just output the status
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  guardian_status
fi