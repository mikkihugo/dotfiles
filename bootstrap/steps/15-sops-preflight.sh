#!/bin/bash
set -euo pipefail

echo "==> Preflighting SOPS age key before Home Manager"

if [[ ! -f ~/.ssh/id_ed25519 ]]; then
	echo "   ⚠️  SSH key not found at ~/.ssh/id_ed25519 — skipping SOPS bootstrap"
	echo "      Copy your SSH key, then re-run install.sh"
	exit 0
fi

SOPS_KEY_DIR="$HOME/.config/sops/age"
SOPS_KEY_FILE="$SOPS_KEY_DIR/keys.txt"
SECRETS_FILE="$DOTFILES_ROOT/secrets/api-keys.yaml"

mkdir -p "$SOPS_KEY_DIR"

if [[ -f "$SOPS_KEY_FILE" ]]; then
	echo "   ✅ SOPS key already exists at $SOPS_KEY_FILE"
else
	echo "   Generating SOPS key from SSH key via nix shell..."
	nix --extra-experimental-features 'nix-command flakes' \
		shell nixpkgs#ssh-to-age nixpkgs#sops \
		--command bash -lc '
			set -euo pipefail
			ssh-to-age -private-key -i ~/.ssh/id_ed25519 > "$1"
			chmod 600 "$1"
		' bash "$SOPS_KEY_FILE"
	echo "   ✅ SOPS key created at $SOPS_KEY_FILE"
fi

if [[ -f "$SECRETS_FILE" ]]; then
	if nix --extra-experimental-features 'nix-command flakes' \
		shell nixpkgs#sops \
		--command bash -lc 'sops -d "$1" >/dev/null' bash "$SECRETS_FILE"; then
		echo "   ✅ SOPS decryption test successful"
	else
		echo "   ⚠️  SOPS decryption test failed — this machine key is not authorized yet"
		echo "      Add this recipient to .sops.yaml: $(nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age --command bash -lc 'ssh-to-age -i ~/.ssh/id_ed25519.pub')"
	fi
fi
