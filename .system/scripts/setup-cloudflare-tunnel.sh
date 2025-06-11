#!/bin/bash
#
# Setup Cloudflare Tunnel for Tabby Gateway
# Purpose: Secure external access to Tabby services
# Version: 1.0.0

set -euo pipefail

# Load tokens
source "$HOME/.env_tokens"

# Check required vars
if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ZONE_ID:-}" ]; then
    echo "Error: Set CF_API_TOKEN and CF_ZONE_ID in ~/.env_tokens"
    exit 1
fi

echo "🌐 Setting up Cloudflare Tunnel for Tabby..."

# Install cloudflared if needed
if ! command -v cloudflared &>/dev/null; then
    echo "Installing cloudflared..."
    curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
        -o "$HOME/.local/bin/cloudflared"
    chmod +x "$HOME/.local/bin/cloudflared"
fi

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
TUNNEL_NAME="tabby-gateway-$(hostname -s)"
cloudflared tunnel create "$TUNNEL_NAME"

# Get tunnel ID
TUNNEL_ID=$(cloudflared tunnel list --name "$TUNNEL_NAME" --output json | jq -r '.[0].id')

# Create config
cat > "$HOME/.cloudflared/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: $HOME/.cloudflared/$TUNNEL_ID.json

ingress:
  # Tabby Web UI
  - hostname: tabby.${CF_DOMAIN}
    service: http://localhost:9090
    originRequest:
      noTLSVerify: true
      
  # Tabby API
  - hostname: api.tabby.${CF_DOMAIN}
    service: http://localhost:9091
    originRequest:
      noTLSVerify: true
      
  # SSH over WebSocket
  - hostname: ssh.tabby.${CF_DOMAIN}
    service: ssh://localhost:22
    
  # Catch-all
  - service: http_status:404
EOF

# Create DNS records
echo "Creating DNS records..."
cloudflared tunnel route dns "$TUNNEL_NAME" "tabby.${CF_DOMAIN}"
cloudflared tunnel route dns "$TUNNEL_NAME" "api.tabby.${CF_DOMAIN}"
cloudflared tunnel route dns "$TUNNEL_NAME" "ssh.tabby.${CF_DOMAIN}"

# Create systemd service
cat > "$HOME/.config/systemd/user/cloudflared.service" << EOF
[Unit]
Description=Cloudflare Tunnel for Tabby Gateway
After=network-online.target

[Service]
Type=simple
ExecStart=$HOME/.local/bin/cloudflared tunnel run
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF

# Enable and start
systemctl --user daemon-reload
systemctl --user enable cloudflared
systemctl --user start cloudflared

echo "✅ Cloudflare Tunnel configured!"
echo ""
echo "Access your Tabby at:"
echo "  https://tabby.${CF_DOMAIN}"
echo "  https://api.tabby.${CF_DOMAIN}"
echo "  https://ssh.tabby.${CF_DOMAIN}"