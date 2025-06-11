#!/bin/bash
# Minimal emergency script
# This is a self-contained script that can restore the guardian

# Emergency paths
LOCATIONS=(
  "$HOME/.local/bin/shell-guardian"
  "$HOME/.dotfiles/.guardian-shell/shell-guardian.bin"
  "$HOME/.config/.guardian"
)

# Check for existing guardian
for loc in "${LOCATIONS[@]}"; do
  if [ -f "$loc" ] && [ -x "$loc" ]; then
    echo "✅ Found guardian at: $loc"
    
    # Copy to all locations
    for target in "${LOCATIONS[@]}"; do
      if [ "$target" != "$loc" ]; then
        mkdir -p "$(dirname "$target")"
        cp "$loc" "$target"
        chmod +x "$target"
        echo "✅ Restored to: $target"
      fi
    done
    
    echo "✅ Guardian restored to all locations"
    echo "🚀 Try running: shell-guardian bash"
    exit 0
  fi
done

# No guardian found, show error
echo "❌ No guardian found in any location"
echo "💡 You need to recompile the guardian"
echo "💡 Run: ~/.dotfiles/.scripts/guardian/minimal-compile.sh"