#!/bin/bash
set -euo pipefail

if command -v nix >/dev/null 2>&1; then
	echo "   ✅ Nix already installed: $(nix --version)"
	exit 0
fi

echo "==> Nix not found — installing (multi-user daemon)..."

# Detect OS for correct install flags
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "   Platform: ${OS}/${ARCH}"

# Download and run the official Nix installer (multi-user, daemon mode)
curl -sSL https://nixos.org/nix/install | sh -s -- --daemon --yes

# Source nix into current shell so the rest of bootstrap can use it
NIX_DAEMON_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
NIX_SINGLE_PROFILE="$HOME/.nix-profile/etc/profile.d/nix.sh"

if [ -f "$NIX_DAEMON_PROFILE" ]; then
	# shellcheck source=/dev/null
	. "$NIX_DAEMON_PROFILE"
elif [ -f "$NIX_SINGLE_PROFILE" ]; then
	# shellcheck source=/dev/null
	. "$NIX_SINGLE_PROFILE"
else
	echo "   ⚠️  Nix installed but profile script not found — open a new shell and re-run install.sh" >&2
	exit 1
fi

echo "   ✅ Nix installed: $(nix --version)"
