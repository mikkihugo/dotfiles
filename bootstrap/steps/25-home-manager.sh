#!/bin/bash
set -euo pipefail

# ── Step 25: Apply home-manager configuration ────────────────────────────────
#
# Detects the correct profile based on hostname and applies it.
# Also enables systemd linger so user services survive logout.
#
# Profiles:
#   mikki-bunker  — x86_64 WSL2 desktop (GPU/CUDA worker)
#   mikki-laptop  — aarch64 laptop (no GPU)
#   mhugo         — fallback: auto-detects current system arch

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"

# ── 1. Install home-manager if missing ───────────────────────────────────────
if ! command -v home-manager >/dev/null 2>&1; then
	echo "==> Installing home-manager..."
	nix run home-manager/master -- init --switch || {
		# Fallback: install via nix profile
		nix profile install "github:nix-community/home-manager"
	}
fi

# ── 2. Detect profile by hostname ────────────────────────────────────────────
HOSTNAME="$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null | tr -d '[:space:]')"
case "$HOSTNAME" in
mikki-bunker) PROFILE="mikki-bunker" ;;
Mikki-Laptop) PROFILE="mikki-laptop" ;;
*) PROFILE="mhugo" ;; # auto-detects arch via builtins.currentSystem
esac

echo "==> Applying home-manager profile: $PROFILE (hostname: $HOSTNAME)"

home-manager switch \
	--flake "${ROOT_DIR}#${PROFILE}" \
	--impure \
	--extra-experimental-features 'nix-command flakes' \
	-b backup

echo "   ✅ home-manager applied"

# ── 3. Enable systemd linger so user services survive logout ─────────────────
if command -v loginctl >/dev/null 2>&1; then
	loginctl enable-linger "$(whoami)" 2>/dev/null &&
		echo "   ✅ systemd linger enabled" ||
		echo "   ⚠️  loginctl not available (non-systemd system?)"
fi
