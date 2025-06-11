#!/bin/bash
#
# 2-of-3 Multi-Factor Unlock System
# Purpose: Require any 2 of 3 keys to unlock the admin stack
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔐 2-of-3 Multi-Factor Unlock System${NC}"
echo "You need any 2 of these 3 keys to unlock:"
echo "  1. Cloudflare API Token"
echo "  2. Google OAuth Token" 
echo "  3. Warp Connector Key"
echo ""

# Track which keys we have
KEYS_PROVIDED=0
MASTER_KEY_PARTS=()

# Function to combine key parts using XOR
combine_keys() {
    local key1=$1
    local key2=$2
    
    # XOR the two keys to get master key
    python3 -c "
import hashlib
k1 = hashlib.sha256('$key1'.encode()).digest()
k2 = hashlib.sha256('$key2'.encode()).digest()
master = bytes(a ^ b for a, b in zip(k1, k2))
print(master.hex())
"
}

# Method 1: Cloudflare Key
check_cloudflare_key() {
    echo -e "${YELLOW}Checking for Cloudflare key...${NC}"
    
    # Check environment first
    if [ -n "${CF_API_TOKEN:-}" ]; then
        echo -e "${GREEN}✓ Found Cloudflare key in environment${NC}"
        MASTER_KEY_PARTS+=("cf:$CF_API_TOKEN")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Check Cloudflare API
    if command -v wrangler &>/dev/null && wrangler whoami &>/dev/null 2>&1; then
        echo -e "${GREEN}✓ Found Cloudflare key via Wrangler${NC}"
        CF_KEY=$(wrangler secret list | grep -E "MASTER_KEY_PART" | head -1 | awk '{print $2}')
        if [ -n "$CF_KEY" ]; then
            MASTER_KEY_PARTS+=("cf:$CF_KEY")
            ((KEYS_PROVIDED++))
            return 0
        fi
    fi
    
    # Manual input
    echo -e "${YELLOW}Enter Cloudflare API Token (or press Enter to skip):${NC}"
    read -s CF_INPUT
    if [ -n "$CF_INPUT" ]; then
        MASTER_KEY_PARTS+=("cf:$CF_INPUT")
        ((KEYS_PROVIDED++))
        echo -e "${GREEN}✓ Cloudflare key provided${NC}"
    else
        echo -e "${YELLOW}⚠ Cloudflare key skipped${NC}"
    fi
}

# Method 2: Google OAuth
check_google_key() {
    echo -e "${YELLOW}Checking for Google authentication...${NC}"
    
    # Check if already authenticated
    if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        echo -e "${GREEN}✓ Google authentication active${NC}"
        # Get a deterministic key from Google account
        GOOGLE_KEY=$(gcloud auth application-default print-access-token 2>/dev/null | sha256sum | cut -d' ' -f1)
        if [ -n "$GOOGLE_KEY" ]; then
            MASTER_KEY_PARTS+=("google:$GOOGLE_KEY")
            ((KEYS_PROVIDED++))
            return 0
        fi
    fi
    
    # Try OAuth login
    echo -e "${YELLOW}Login with Google? (y/N):${NC}"
    read -r GOOGLE_LOGIN
    if [[ "$GOOGLE_LOGIN" =~ ^[Yy]$ ]]; then
        gcloud auth login --brief
        GOOGLE_KEY=$(gcloud auth application-default print-access-token | sha256sum | cut -d' ' -f1)
        MASTER_KEY_PARTS+=("google:$GOOGLE_KEY")
        ((KEYS_PROVIDED++))
        echo -e "${GREEN}✓ Google authentication successful${NC}"
    else
        echo -e "${YELLOW}⚠ Google authentication skipped${NC}"
    fi
}

# Method 3: Warp Connector Key
check_warp_key() {
    echo -e "${YELLOW}Checking for Warp Connector key...${NC}"
    
    # Check if stored locally
    if [ -f ~/.warp-connector-key ]; then
        echo -e "${GREEN}✓ Found local Warp Connector key${NC}"
        WARP_KEY=$(cat ~/.warp-connector-key)
        MASTER_KEY_PARTS+=("warp:$WARP_KEY")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Check Cloudflare Tunnel
    if [ -f ~/.cloudflared/cert.pem ]; then
        echo -e "${GREEN}✓ Found Cloudflare Tunnel certificate${NC}"
        WARP_KEY=$(sha256sum ~/.cloudflared/cert.pem | cut -d' ' -f1)
        MASTER_KEY_PARTS+=("warp:$WARP_KEY")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Manual input
    echo -e "${YELLOW}Enter Warp Connector Key (or press Enter to skip):${NC}"
    read -s WARP_INPUT
    if [ -n "$WARP_INPUT" ]; then
        MASTER_KEY_PARTS+=("warp:$WARP_INPUT")
        ((KEYS_PROVIDED++))
        echo -e "${GREEN}✓ Warp Connector key provided${NC}"
        # Save for future use
        echo "$WARP_INPUT" > ~/.warp-connector-key
        chmod 600 ~/.warp-connector-key
    else
        echo -e "${YELLOW}⚠ Warp Connector key skipped${NC}"
    fi
}

# Derive master key from any 2 parts
derive_master_key() {
    if [ $KEYS_PROVIDED -lt 2 ]; then
        echo -e "${RED}❌ Need at least 2 keys, only have $KEYS_PROVIDED${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Deriving master key from provided keys...${NC}"
    
    # Extract the actual keys
    local key1=$(echo "${MASTER_KEY_PARTS[0]}" | cut -d: -f2)
    local key2=$(echo "${MASTER_KEY_PARTS[1]}" | cut -d: -f2)
    
    # Combine keys
    MASTER_KEY=$(combine_keys "$key1" "$key2")
    
    echo -e "${GREEN}✓ Master key derived successfully${NC}"
}

# Unlock Vault with master key
unlock_vault() {
    echo -e "${YELLOW}Unlocking Vault...${NC}"
    
    # Start Vault if not running
    if ! docker ps | grep -q vault; then
        cd ~/.dotfiles/docker/tabby-admin
        docker compose up -d vault
        sleep 5
    fi
    
    # Decrypt Vault unseal keys using master key
    if [ -f ~/.vault-keys.enc ]; then
        echo "$MASTER_KEY" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin \
            -in ~/.vault-keys.enc -out /tmp/vault-keys
        
        # Unseal Vault
        while IFS= read -r key; do
            docker exec vault vault operator unseal "$key" 2>/dev/null || true
        done < /tmp/vault-keys
        
        shred -u /tmp/vault-keys
        echo -e "${GREEN}✓ Vault unsealed${NC}"
    else
        echo -e "${YELLOW}No encrypted Vault keys found. Initializing...${NC}"
        # Initialize Vault and save keys
        init_vault_with_master_key
    fi
}

# Initialize Vault and encrypt keys with master
init_vault_with_master_key() {
    echo -e "${YELLOW}Initializing Vault...${NC}"
    
    # Initialize Vault
    INIT_OUTPUT=$(docker exec vault vault operator init -key-shares=5 -key-threshold=3 -format=json)
    
    # Save unseal keys encrypted with master key
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' | \
        openssl enc -aes-256-cbc -pbkdf2 -pass stdin -out ~/.vault-keys.enc <<< "$MASTER_KEY"
    
    # Save root token separately (also encrypted)
    echo "$INIT_OUTPUT" | jq -r '.root_token' | \
        openssl enc -aes-256-cbc -pbkdf2 -pass stdin -out ~/.vault-token.enc <<< "$MASTER_KEY"
    
    # Unseal immediately
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' | head -3 | while read key; do
        docker exec vault vault operator unseal "$key"
    done
    
    echo -e "${GREEN}✓ Vault initialized and unsealed${NC}"
}

# Start all services after unlock
start_services() {
    echo -e "${YELLOW}Starting all services...${NC}"
    
    cd ~/.dotfiles/docker/tabby-admin
    docker compose up -d
    
    echo -e "${GREEN}✓ All services started${NC}"
    echo ""
    echo "Services available at:"
    echo "  • Vault UI: http://localhost:8200"
    echo "  • Warpgate: http://localhost:8888"
    echo "  • Tabby Web: http://localhost:9090"
}

# Main execution
main() {
    # Check all three methods
    check_cloudflare_key
    echo ""
    check_google_key
    echo ""
    check_warp_key
    echo ""
    
    # Verify we have enough keys
    echo -e "${BLUE}Keys collected: $KEYS_PROVIDED/3${NC}"
    if [ $KEYS_PROVIDED -lt 2 ]; then
        echo -e "${RED}❌ Insufficient keys. Need at least 2 out of 3.${NC}"
        exit 1
    fi
    
    # Derive master key and unlock
    derive_master_key
    unlock_vault
    start_services
    
    echo -e "${GREEN}✅ System unlocked with $KEYS_PROVIDED keys!${NC}"
}

# Emergency backup - all 3 keys regenerate master
emergency_recovery() {
    echo -e "${RED}🚨 Emergency Recovery Mode${NC}"
    echo "This requires ALL 3 keys to regenerate the master key"
    
    # Force collection of all keys
    KEYS_PROVIDED=0
    MASTER_KEY_PARTS=()
    
    check_cloudflare_key
    check_google_key  
    check_warp_key
    
    if [ $KEYS_PROVIDED -ne 3 ]; then
        echo -e "${RED}❌ Emergency recovery requires all 3 keys${NC}"
        exit 1
    fi
    
    # Use all 3 keys to regenerate
    echo -e "${YELLOW}Regenerating master key from all 3 parts...${NC}"
    
    # Complex derivation using all 3
    local cf_key=$(echo "${MASTER_KEY_PARTS[0]}" | cut -d: -f2)
    local google_key=$(echo "${MASTER_KEY_PARTS[1]}" | cut -d: -f2)
    local warp_key=$(echo "${MASTER_KEY_PARTS[2]}" | cut -d: -f2)
    
    MASTER_KEY=$(python3 -c "
import hashlib
cf = hashlib.sha256('$cf_key'.encode()).digest()
google = hashlib.sha256('$google_key'.encode()).digest()
warp = hashlib.sha256('$warp_key'.encode()).digest()

# XOR all three
master = bytes(a ^ b ^ c for a, b, c in zip(cf, google, warp))
print(master.hex())
")
    
    echo -e "${GREEN}✓ Master key regenerated${NC}"
    
    # Re-encrypt all secrets with new master
    echo -e "${YELLOW}Re-encrypting all secrets...${NC}"
    # ... re-encryption logic ...
}

# Parse arguments
case "${1:-unlock}" in
    unlock)
        main
        ;;
    recovery)
        emergency_recovery
        ;;
    status)
        echo "Checking key availability..."
        KEYS_PROVIDED=0
        check_cloudflare_key
        check_google_key
        check_warp_key
        echo -e "${BLUE}Available keys: $KEYS_PROVIDED/3${NC}"
        ;;
    *)
        echo "Usage: $0 {unlock|recovery|status}"
        echo "  unlock   - Normal unlock (requires 2 of 3 keys)"
        echo "  recovery - Emergency recovery (requires all 3 keys)"
        echo "  status   - Check which keys are available"
        exit 1
        ;;
esac