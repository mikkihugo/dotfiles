#!/bin/bash
#
# Google OAuth Interactive Unlock
# Purpose: Login to Google account to unlock everything
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔐 Google Account Unlock${NC}"
echo ""

# Check if already authenticated
if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)
    echo -e "${GREEN}✓ Already authenticated as: $CURRENT_ACCOUNT${NC}"
    
    # Verify it's the right account
    if [[ "$CURRENT_ACCOUNT" != *"hugo.dk"* ]] && [[ "$CURRENT_ACCOUNT" != "mikki@"* ]]; then
        echo -e "${YELLOW}Warning: Not your expected account${NC}"
        read -p "Re-authenticate? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud auth revoke --all
        else
            exit 1
        fi
    fi
else
    echo "Not authenticated. Starting login..."
fi

# Interactive Google login
echo -e "${YELLOW}Opening browser for Google login...${NC}"
gcloud auth login --update-adc --enable-gdrive-access

# Set project
gcloud config set project hugo-admin-stack 2>/dev/null || true

# Verify authentication worked
if ! gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    echo -e "❌ Authentication failed"
    exit 1
fi

echo -e "${GREEN}✅ Google authentication successful!${NC}"
echo ""

# Now pull all secrets using authenticated gcloud
echo -e "${BLUE}Fetching secrets from Google Secret Manager...${NC}"

# Function to get secret
get_secret() {
    gcloud secrets versions access latest --secret="$1" 2>/dev/null || echo ""
}

# Create .env file
cat > "$HOME/.dotfiles/docker/tabby-admin/.env" << EOF
# Auto-generated from Google Secret Manager
# Authenticated as: $(gcloud config get-value account)
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Cloudflare
CF_API_TOKEN=$(get_secret "cf-api-token")
CF_ZONE_ID=$(get_secret "cf-zone-id")
CF_DOMAIN=$(get_secret "cf-domain")

# GitHub
GITHUB_TOKEN=$(get_secret "github-token")

# Backup
BACKUP_ENCRYPTION_KEY=$(get_secret "backup-key")

# Services
WARPGATE_ADMIN_PASS=$(get_secret "warpgate-pass")
DRONE_RPC_SECRET=$(get_secret "drone-secret")
EOF

chmod 600 "$HOME/.dotfiles/docker/tabby-admin/.env"

echo -e "${GREEN}✅ All secrets loaded!${NC}"
echo ""

# Optional: Setup Application Default Credentials for services
echo -e "${BLUE}Setting up Application Default Credentials...${NC}"
gcloud auth application-default login

echo -e "${GREEN}✅ Complete! Your admin stack is unlocked.${NC}"
echo ""
echo "The authentication will remain active until you:"
echo "  - Run: gcloud auth revoke"
echo "  - Reboot the server"
echo "  - Explicitly logout"