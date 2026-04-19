#!/usr/bin/env bash
# 40-tailscale.sh — install tailscaled system daemon (one-time per machine)
#
# home-manager can't provision system services on non-NixOS, so this step
# handles the part that needs root: installing the apt package and enabling
# the system systemd service. Joining the tailnet (`tailscale up --authkey ...`)
# is handled by home/modules/tailscale.nix on every `hms`.
#
# Idempotent — safe to re-run. Skips install if tailscaled is already active.
set -euo pipefail

if systemctl is-active --quiet tailscaled 2>/dev/null; then
	echo "[40-tailscale] tailscaled already running — skipping install"
	exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
	echo "[40-tailscale] installing tailscale via official script…"
	# The upstream script handles Ubuntu/Debian apt repo setup and GPG keys,
	# including WSL2 (laptop). On bunker it's a straight apt install.
	curl -fsSL https://tailscale.com/install.sh | sudo sh
fi

echo "[40-tailscale] enabling tailscaled…"
sudo systemctl enable --now tailscaled

# Wait briefly for the daemon socket so subsequent `tailscale up` during
# home-manager activation finds it.
for _ in 1 2 3 4 5; do
	[ -S /var/run/tailscale/tailscaled.sock ] && break
	sleep 1
done

echo "[40-tailscale] done — run \`hms\` next to join the tailnet"
