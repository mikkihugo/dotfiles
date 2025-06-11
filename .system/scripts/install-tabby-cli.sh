#!/bin/bash
#
# Install Tabby CLI for Linux servers
# Purpose: Headless Tabby client for persistent ops management
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Installing Tabby CLI for Linux...${NC}"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        TABBY_ARCH="x64"
        ;;
    aarch64)
        TABBY_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download latest Tabby CLI
TABBY_VERSION="latest"
DOWNLOAD_URL="https://github.com/Eugeny/tabby/releases/download/${TABBY_VERSION}/tabby-${TABBY_VERSION}-linux-${TABBY_ARCH}.tar.gz"

# Install to ~/.local
mkdir -p "$HOME/.local/bin"
cd /tmp

echo "Downloading Tabby CLI..."
curl -L "$DOWNLOAD_URL" -o tabby-cli.tar.gz

echo "Extracting..."
tar -xzf tabby-cli.tar.gz

# Move binary
mv tabby "$HOME/.local/bin/tabby-cli"
chmod +x "$HOME/.local/bin/tabby-cli"

# Create config directory
mkdir -p "$HOME/.config/tabby-cli"

# Create systemd service for headless operation
cat > "$HOME/.config/systemd/user/tabby-cli.service" << 'EOF'
[Unit]
Description=Tabby CLI Persistent Session Manager
After=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/bin/tabby-cli server --headless --config %h/.config/tabby-cli/config.yaml
Restart=on-failure
RestartSec=30
Environment="HOME=%h"

[Install]
WantedBy=default.target
EOF

echo -e "${GREEN}✓ Tabby CLI installed${NC}"
echo ""
echo "Commands:"
echo "  tabby-cli connect <host>     - Connect to host"
echo "  tabby-cli list              - List sessions"
echo "  tabby-cli attach <session>  - Attach to session"
echo "  tabby-cli server            - Run persistent server"
echo ""
echo "To run as service:"
echo "  systemctl --user enable tabby-cli"
echo "  systemctl --user start tabby-cli"