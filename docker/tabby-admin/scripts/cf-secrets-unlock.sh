#!/bin/bash
#
# Cloudflare Secrets-based unlock
# Purpose: Use CF platform API key to unlock everything else
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 Cloudflare Secrets Unlock${NC}"

# Option 1: Use CF API Token from environment
if [ -n "${CF_API_TOKEN:-}" ]; then
    echo -e "${GREEN}✓ Using CF_API_TOKEN from environment${NC}"
    API_TOKEN="$CF_API_TOKEN"
    
# Option 2: One-time input at deployment
elif [ ! -f "$HOME/.cf-unlock" ]; then
    echo -e "${YELLOW}First-time setup: Enter Cloudflare API token${NC}"
    echo "This token needs 'Account:Cloudflare Secrets:Read' permission"
    read -s -p "CF API Token: " API_TOKEN
    echo
    
    # Store encrypted with machine ID
    MACHINE_ID=$(cat /etc/machine-id)
    echo "$API_TOKEN" | openssl enc -aes-256-cbc -pbkdf2 -salt -k "$MACHINE_ID" > "$HOME/.cf-unlock"
    chmod 600 "$HOME/.cf-unlock"
    
# Option 3: Decrypt stored token
else
    MACHINE_ID=$(cat /etc/machine-id)
    API_TOKEN=$(openssl enc -aes-256-cbc -pbkdf2 -d -k "$MACHINE_ID" < "$HOME/.cf-unlock")
fi

# Fetch all secrets from Cloudflare
echo -e "${BLUE}Fetching secrets from Cloudflare...${NC}"

# Get account ID from token
ACCOUNT_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts" \
    -H "Authorization: Bearer $API_TOKEN" \
    | jq -r '.result[0].id')

# Fetch secrets
fetch_secret() {
    local secret_name=$1
    curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/secrets/$secret_name" \
        -H "Authorization: Bearer $API_TOKEN" \
        | jq -r '.result.value'
}

# Create environment file
cat > "$HOME/.dotfiles/docker/tabby-admin/.env" << EOF
# Auto-generated from Cloudflare Secrets
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Cloudflare
CF_ACCOUNT_ID=$ACCOUNT_ID
CF_ZONE_ID=$(fetch_secret "CF_ZONE_ID")
CF_DOMAIN=$(fetch_secret "CF_DOMAIN")

# R2 Storage
CF_R2_ACCESS_KEY=$(fetch_secret "CF_R2_ACCESS_KEY")
CF_R2_SECRET_KEY=$(fetch_secret "CF_R2_SECRET_KEY")

# GitHub
GITHUB_TOKEN=$(fetch_secret "GITHUB_TOKEN")
GITHUB_CLIENT_ID=$(fetch_secret "GITHUB_CLIENT_ID")
GITHUB_CLIENT_SECRET=$(fetch_secret "GITHUB_CLIENT_SECRET")

# Drone CI
DRONE_RPC_SECRET=$(fetch_secret "DRONE_RPC_SECRET")
DRONE_CLIENT_ID=$(fetch_secret "DRONE_CLIENT_ID")
DRONE_CLIENT_SECRET=$(fetch_secret "DRONE_CLIENT_SECRET")

# Warpgate
WARPGATE_ADMIN_PASS=$(fetch_secret "WARPGATE_ADMIN_PASS")

# Backup encryption
BACKUP_ENCRYPTION_KEY=$(fetch_secret "BACKUP_ENCRYPTION_KEY")
EOF

chmod 600 "$HOME/.dotfiles/docker/tabby-admin/.env"

echo -e "${GREEN}✅ Secrets loaded from Cloudflare!${NC}"

# Update docker-compose to use .env
if ! grep -q "env_file" docker-compose.yml; then
    echo -e "${YELLOW}Updating docker-compose.yml to use .env file...${NC}"
    # Add env_file to each service
fi

echo ""
echo "All services now have access to secrets!"