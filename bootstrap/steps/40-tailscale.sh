#!/usr/bin/env bash
# 40-tailscale.sh — install tailscaled and join vpn.hugo.dk's headscale
#
# Runs after 25-sops-setup.sh, so the age key is present and we can
# sops-decrypt the pre-auth key directly from secrets/api-keys.yaml.
#
# Idempotent — safe to re-run. Skips install if tailscaled is active, and
# skips `tailscale up` if this node is already online on our login-server.
set -euo pipefail

SECRETS_FILE="${DOTFILES_ROOT:-$HOME/.dotfiles}/secrets/api-keys.yaml"
SOPS_CFG="${DOTFILES_ROOT:-$HOME/.dotfiles}/.sops.yaml"

if ! command -v tailscale >/dev/null 2>&1; then
	echo "[40-tailscale] installing tailscale via official script…"
	# Upstream script handles Ubuntu/Debian apt repo setup and GPG keys,
	# including WSL2 (laptop). On bunker it's a straight apt install.
	curl -fsSL https://tailscale.com/install.sh | sudo sh
fi

if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
	echo "[40-tailscale] enabling tailscaled…"
	sudo systemctl enable --now tailscaled
	for _ in 1 2 3 4 5; do
		[ -S /var/run/tailscale/tailscaled.sock ] && break
		sleep 1
	done
fi

# Already joined on our login-server? Skip.
_backend_state=$(sudo tailscale status --json 2>/dev/null | jq -r '.BackendState // ""')
if [ "$_backend_state" = "Running" ]; then
	echo "[40-tailscale] already online — $(sudo tailscale status --self=true --peers=false | head -1)"
	exit 0
fi

# Need authkey + login_server from SOPS. sops-nix has already materialized
# these into ~/.config/sops-nix/secrets/ via home-manager — use those if
# present to avoid a second sops-decrypt invocation. Fall back to direct
# decrypt so first-boot (before any hms) also works.
_authkey=""
_login_server=""
if [ -r "$HOME/.config/sops-nix/secrets/tailscale_authkey" ]; then
	_authkey=$(cat "$HOME/.config/sops-nix/secrets/tailscale_authkey")
	_login_server=$(cat "$HOME/.config/sops-nix/secrets/tailscale_login_server")
elif [ -r "$SECRETS_FILE" ]; then
	_authkey=$(sops --config "$SOPS_CFG" -d --extract '["tailscale"]["authkey"]' "$SECRETS_FILE")
	_login_server=$(sops --config "$SOPS_CFG" -d --extract '["tailscale"]["login_server"]' "$SECRETS_FILE")
fi

if [ -z "$_authkey" ] || [ -z "$_login_server" ]; then
	echo "[40-tailscale] secrets unavailable — run \`hms\` first, then re-run this step" >&2
	exit 1
fi

echo "[40-tailscale] joining $_login_server as $(hostname)…"
# --operator so future `tailscale up/down/set` don't require sudo.
sudo tailscale up \
	--login-server="$_login_server" \
	--authkey="$_authkey" \
	--hostname="$(hostname)" \
	--operator="$(whoami)" \
	--accept-routes

echo "[40-tailscale] done"
sudo tailscale status --self=true --peers=false | head -3
