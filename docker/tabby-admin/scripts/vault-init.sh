#!/bin/bash
#
# One-time vault initialization for admin stack
# Purpose: Securely unlock services with master key
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 Admin Stack Vault Initialization${NC}"
echo ""

# Check if already initialized
if [ -f "$HOME/.dotfiles/docker/tabby-admin/.vault-initialized" ]; then
    echo -e "${YELLOW}Already initialized. To re-initialize, delete .vault-initialized${NC}"
    exit 0
fi

# Create secure vault directory
VAULT_DIR="$HOME/.dotfiles/docker/tabby-admin/.vault"
mkdir -p "$VAULT_DIR"
chmod 700 "$VAULT_DIR"

# Get master unlock key (one-time)
echo -e "${YELLOW}Enter master unlock key (or generate new):${NC}"
echo "1) Enter existing key"
echo "2) Generate new key"
read -p "Choice: " choice

case $choice in
    1)
        read -s -p "Master key: " MASTER_KEY
        echo
        ;;
    2)
        MASTER_KEY=$(openssl rand -base64 32)
        echo -e "${GREEN}Generated master key:${NC}"
        echo "$MASTER_KEY"
        echo -e "${YELLOW}SAVE THIS KEY! You'll need it to unlock on other servers${NC}"
        read -p "Press enter when saved..."
        ;;
esac

# Derive service keys from master
echo -e "${BLUE}Deriving service keys...${NC}"

# Function to derive key
derive_key() {
    echo -n "$1" | openssl dgst -sha256 -hmac "$MASTER_KEY" -binary | base64
}

# Generate all service keys
CF_API_KEY=$(derive_key "cloudflare-api")
CF_TUNNEL_KEY=$(derive_key "cloudflare-tunnel")
GITHUB_KEY=$(derive_key "github-ssh")
WARPGATE_KEY=$(derive_key "warpgate-admin")
BACKUP_KEY=$(derive_key "backup-encryption")

# Store encrypted keys
cat > "$VAULT_DIR/services.enc" << EOF
# Auto-generated service keys - DO NOT EDIT
export CF_API_TOKEN="$CF_API_KEY"
export CF_TUNNEL_TOKEN="$CF_TUNNEL_KEY"
export GITHUB_SSH_KEY="$GITHUB_KEY"
export WARPGATE_ADMIN_KEY="$WARPGATE_KEY"
export BACKUP_ENCRYPTION_KEY="$BACKUP_KEY"
EOF

# Encrypt vault with master key
openssl enc -aes-256-cbc -salt -pbkdf2 \
    -in "$VAULT_DIR/services.enc" \
    -out "$VAULT_DIR/services.vault" \
    -k "$MASTER_KEY"

rm "$VAULT_DIR/services.enc"

# Create unlock script
cat > "$VAULT_DIR/unlock.sh" << 'EOF'
#!/bin/bash
# Unlock vault for service startup

VAULT_DIR="$(dirname "$0")"

if [ -f "$VAULT_DIR/.unlocked" ]; then
    source "$VAULT_DIR/.unlocked"
    return 0
fi

read -s -p "Enter master key: " MASTER_KEY
echo

openssl enc -aes-256-cbc -d -pbkdf2 \
    -in "$VAULT_DIR/services.vault" \
    -out "$VAULT_DIR/.unlocked" \
    -k "$MASTER_KEY" 2>/dev/null

if [ $? -eq 0 ]; then
    chmod 600 "$VAULT_DIR/.unlocked"
    source "$VAULT_DIR/.unlocked"
    echo "✅ Vault unlocked"
    
    # Auto-lock after 1 hour
    (sleep 3600 && rm -f "$VAULT_DIR/.unlocked") &
else
    echo "❌ Invalid key"
    exit 1
fi
EOF

chmod +x "$VAULT_DIR/unlock.sh"

# Create systemd dropin for vault
mkdir -p "$HOME/.config/systemd/user/tabby-admin.service.d"
cat > "$HOME/.config/systemd/user/tabby-admin.service.d/vault.conf" << EOF
[Service]
ExecStartPre=$VAULT_DIR/unlock.sh
EnvironmentFile=-$VAULT_DIR/.unlocked
EOF

# Mark as initialized
touch "$HOME/.dotfiles/docker/tabby-admin/.vault-initialized"

echo -e "${GREEN}✅ Vault initialized!${NC}"
echo ""
echo "Next steps:"
echo "1. The vault will auto-unlock on service start"
echo "2. Keys are derived from your master key"
echo "3. Vault auto-locks after 1 hour"
echo ""
echo "To unlock manually: $VAULT_DIR/unlock.sh"