#!/bin/bash
set -euo pipefail

echo "==> Setting up SOPS age key"

# sops and ssh-to-age are installed by home-manager (step 20).
if ! command -v sops >/dev/null 2>&1; then
	echo "❌ sops not found — home-manager step should have installed it" >&2
	exit 1
fi

# SSH key is required to derive the age key.
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
	echo "⚠️  SSH key not found at ~/.ssh/id_ed25519 — skipping SOPS key setup"
	echo "   Copy your SSH key then run: bash ~/.dotfiles/bootstrap/steps/25-sops-setup.sh"
	exit 0
fi

# Set up SOPS age key directory
SOPS_KEY_DIR="$HOME/.config/sops/age"
SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"

mkdir -p "$SOPS_KEY_DIR"

# Generate age key from SSH key if it doesn't exist
if [[ ! -f "$SOPS_KEY_FILE" ]]; then
	echo "   Generating SOPS age key from SSH key..."
	ssh-to-age -private-key -i ~/.ssh/id_ed25519 >"$SOPS_KEY_FILE"
	chmod 600 "$SOPS_KEY_FILE"
	echo "   ✅ SOPS key created at $SOPS_KEY_FILE"
else
	echo "   ✅ SOPS key already exists at $SOPS_KEY_FILE"
fi

# Test decryption
SECRETS_FILE="$DOTFILES_ROOT/secrets/api-keys.yaml"
if [[ -f "$SECRETS_FILE" ]]; then
	if sops -d "$SECRETS_FILE" >/dev/null 2>&1; then
		echo "   ✅ SOPS decryption test successful"
	else
		echo "   ⚠️  SOPS decryption test failed — age key may not be authorised"
		echo "      Ask the repo owner to add your pubkey: ssh-to-age -i ~/.ssh/id_ed25519.pub"
	fi
fi
