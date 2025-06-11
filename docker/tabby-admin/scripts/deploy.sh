#!/bin/bash
#
# Deploy Tabby Admin Stack
# Purpose: One-command deployment with Cloudflare integration
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 Deploying Tabby Admin Stack${NC}"

# Check if running on designated ops host
if ! /home/mhugo/.dotfiles/.system/scripts/ops-host-manager.sh status | grep -q "SHOULD run"; then
    echo -e "${YELLOW}Warning: This host is not the designated ops server${NC}"
    read -p "Deploy anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Load environment
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens"
    set +a
fi

# Check Docker
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Please log out and back in for Docker permissions"
    exit 1
fi

# Navigate to docker directory
cd "$(dirname "$0")/.."

# Build containers
echo -e "${GREEN}Building containers...${NC}"
make build

# Start stack
echo -e "${GREEN}Starting stack...${NC}"
make up

# Wait for services
echo "Waiting for services to be ready..."
sleep 10

# Setup Cloudflare tunnel if tokens exist
if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CF_DOMAIN:-}" ]; then
    echo -e "${GREEN}Setting up Cloudflare tunnel...${NC}"
    make tunnel
else
    echo -e "${YELLOW}Skipping Cloudflare tunnel (no tokens found)${NC}"
fi

# Show status
make status

echo -e "${GREEN}✅ Tabby Admin Stack deployed successfully!${NC}"

# Create admin shell alias
echo ""
echo "To manage the stack, use:"
echo "  cd ~/.dotfiles/docker/tabby-admin && make help"
echo ""
echo "Or add this alias:"
echo "  alias tabby-admin='cd ~/.dotfiles/docker/tabby-admin && make'"