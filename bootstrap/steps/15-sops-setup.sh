#!/bin/bash
set -euo pipefail

PROFILE="$1"

echo "==> Setting up SOPS age key"

# Check if we're in nix develop (has SOPS tools)
if ! command -v sops >/dev/null 2>&1; then
  echo "⚠️  SOPS not available - make sure you're running in 'nix develop'"
  exit 0
fi

# Check if SSH key exists
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  echo "⚠️  SSH key not found at ~/.ssh/id_ed25519"
  echo "   Copy your SSH key to this machine first"
  exit 0
fi

# Set up SOPS age key directory
SOPS_KEY_DIR="$HOME/.config/sops/age"
SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"

mkdir -p "$SOPS_KEY_DIR"

# Generate age key from SSH key if it doesn't exist
if [[ ! -f "$SOPS_KEY_FILE" ]]; then
  echo "   Generating SOPS age key from SSH key..."
  ssh-to-age -private-key -i ~/.ssh/id_ed25519 > "$SOPS_KEY_FILE"
  chmod 600 "$SOPS_KEY_FILE"
  echo "   ✅ SOPS key created at $SOPS_KEY_FILE"
else
  echo "   ✅ SOPS key already exists at $SOPS_KEY_FILE"
fi

# Test decryption if secrets file exists
if [[ -f "$DOTFILES_ROOT/secrets/shared.yaml" ]]; then
  if sops -d "$DOTFILES_ROOT/secrets/shared.yaml" >/dev/null 2>&1; then
    echo "   ✅ SOPS decryption test successful"
  else
    echo "   ⚠️  SOPS decryption test failed - check your age key configuration"
  fi
else
  echo "   ℹ️  No secrets file found yet (secrets/shared.yaml)"
  echo "      Create one with: sops secrets/shared.yaml"
fi