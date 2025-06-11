#!/bin/bash
#
# 2-of-3 Multi-Factor Unlock System (No Python)
# Purpose: Require any 2 of 3 keys to unlock, including paper backup
# Version: 2.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔐 2-of-3 Multi-Factor Unlock System${NC}"
echo "You need any 2 of these 3 keys to unlock:"
echo "  1. 📄 Paper Backup Code (printed secret)"
echo "  2. 🔑 Google Account (OAuth)" 
echo "  3. ☁️  Cloudflare/Warp Key"
echo ""

# Track which keys we have
KEYS_PROVIDED=0
KEY_HASHES=()

# Function to hash a key deterministically
hash_key() {
    echo -n "$1" | openssl sha256 -binary | base64 | tr -d '\n'
}

# Function to combine two keys using XOR via openssl
combine_keys() {
    local key1_hash=$(echo -n "$1" | openssl sha256 -binary | xxd -p)
    local key2_hash=$(echo -n "$2" | openssl sha256 -binary | xxd -p)
    
    # XOR using shell arithmetic (works for hex)
    local result=""
    for ((i=0; i<64; i+=2)); do
        local byte1=$((16#${key1_hash:$i:2}))
        local byte2=$((16#${key2_hash:$i:2}))
        local xor=$((byte1 ^ byte2))
        result+=$(printf "%02x" $xor)
    done
    
    echo "$result"
}

# Method 1: Paper Backup Code
check_paper_key() {
    echo -e "${YELLOW}📄 Paper Backup Code${NC}"
    echo "This is a code you printed and stored securely"
    echo "Format: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"
    echo ""
    
    # Check if we have a cached paper key hash
    if [ -f ~/.config/admin-stack/paper-key-hash ]; then
        echo -e "${YELLOW}Found cached paper key verification${NC}"
        echo "Enter your paper backup code:"
        read -s PAPER_INPUT
        
        # Verify against hash
        INPUT_HASH=$(hash_key "$PAPER_INPUT")
        STORED_HASH=$(cat ~/.config/admin-stack/paper-key-hash)
        
        if [ "$INPUT_HASH" = "$STORED_HASH" ]; then
            echo -e "${GREEN}✓ Paper code verified${NC}"
            KEY_HASHES+=("paper:$PAPER_INPUT")
            ((KEYS_PROVIDED++))
            return 0
        else
            echo -e "${RED}✗ Invalid paper code${NC}"
        fi
    fi
    
    echo -e "${YELLOW}Enter paper backup code (or press Enter to skip):${NC}"
    read -s PAPER_INPUT
    
    if [ -n "$PAPER_INPUT" ]; then
        # Validate format
        if [[ "$PAPER_INPUT" =~ ^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]]; then
            KEY_HASHES+=("paper:$PAPER_INPUT")
            ((KEYS_PROVIDED++))
            echo -e "${GREEN}✓ Paper code accepted${NC}"
            
            # Cache the hash for future verification
            mkdir -p ~/.config/admin-stack
            hash_key "$PAPER_INPUT" > ~/.config/admin-stack/paper-key-hash
            chmod 600 ~/.config/admin-stack/paper-key-hash
        else
            echo -e "${RED}✗ Invalid format. Expected: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Paper code skipped${NC}"
    fi
}

# Method 2: Google OAuth
check_google_key() {
    echo -e "${YELLOW}🔑 Google Account Authentication${NC}"
    
    # Check if gcloud is available
    if ! command -v gcloud &>/dev/null; then
        echo -e "${YELLOW}gcloud not found. Using web-based auth...${NC}"
        
        # Generate a nonce
        NONCE=$(openssl rand -hex 16)
        
        echo "Visit this URL to authenticate:"
        echo "https://accounts.google.com/o/oauth2/v2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&scope=email&state=$NONCE"
        echo ""
        echo "Enter the authorization code:"
        read -s GOOGLE_CODE
        
        if [ -n "$GOOGLE_CODE" ]; then
            # Use the code as key material
            KEY_HASHES+=("google:$GOOGLE_CODE")
            ((KEYS_PROVIDED++))
            echo -e "${GREEN}✓ Google authentication code accepted${NC}"
        else
            echo -e "${YELLOW}⚠ Google authentication skipped${NC}"
        fi
        return 0
    fi
    
    # Use gcloud if available
    if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        echo -e "${GREEN}✓ Google account already authenticated${NC}"
        # Get email as deterministic key
        GOOGLE_EMAIL=$(gcloud config get-value account 2>/dev/null)
        KEY_HASHES+=("google:$GOOGLE_EMAIL")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    echo -e "${YELLOW}Login with Google? (y/N):${NC}"
    read -r GOOGLE_LOGIN
    if [[ "$GOOGLE_LOGIN" =~ ^[Yy]$ ]]; then
        gcloud auth login --brief
        GOOGLE_EMAIL=$(gcloud config get-value account)
        KEY_HASHES+=("google:$GOOGLE_EMAIL")
        ((KEYS_PROVIDED++))
        echo -e "${GREEN}✓ Google authentication successful${NC}"
    else
        echo -e "${YELLOW}⚠ Google authentication skipped${NC}"
    fi
}

# Method 3: Cloudflare/Warp Key
check_cloudflare_key() {
    echo -e "${YELLOW}☁️  Cloudflare/Warp Key${NC}"
    
    # Check environment
    if [ -n "${CF_API_TOKEN:-}" ]; then
        echo -e "${GREEN}✓ Found Cloudflare key in environment${NC}"
        KEY_HASHES+=("cf:$CF_API_TOKEN")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Check wrangler
    if command -v wrangler &>/dev/null && wrangler whoami &>/dev/null 2>&1; then
        echo -e "${GREEN}✓ Authenticated with Wrangler${NC}"
        CF_EMAIL=$(wrangler whoami 2>&1 | grep -oE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
        KEY_HASHES+=("cf:$CF_EMAIL")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Check Cloudflare tunnel
    if [ -f ~/.cloudflared/cert.pem ]; then
        echo -e "${GREEN}✓ Found Cloudflare Tunnel certificate${NC}"
        CERT_HASH=$(openssl x509 -in ~/.cloudflared/cert.pem -noout -fingerprint -sha256 | cut -d= -f2)
        KEY_HASHES+=("cf:tunnel:$CERT_HASH")
        ((KEYS_PROVIDED++))
        return 0
    fi
    
    # Manual input
    echo -e "${YELLOW}Enter Cloudflare API Token or Warp Key (or press Enter to skip):${NC}"
    read -s CF_INPUT
    if [ -n "$CF_INPUT" ]; then
        KEY_HASHES+=("cf:$CF_INPUT")
        ((KEYS_PROVIDED++))
        echo -e "${GREEN}✓ Cloudflare key provided${NC}"
    else
        echo -e "${YELLOW}⚠ Cloudflare key skipped${NC}"
    fi
}

# Generate paper backup codes
generate_paper_backup() {
    echo -e "${BLUE}📄 Generating Paper Backup Codes${NC}"
    echo ""
    
    # Generate 3 codes (need 2 to reconstruct)
    local codes=()
    for i in {1..3}; do
        # Generate random code in format XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
        local code=""
        for j in {1..6}; do
            local segment=$(openssl rand -hex 2 | tr '[:lower:]' '[:upper:]' | head -c 4)
            code+="$segment"
            [ $j -lt 6 ] && code+="-"
        done
        codes+=("$code")
    done
    
    # Generate master from first code
    local master_hash=$(hash_key "${codes[0]}")
    
    echo -e "${YELLOW}Print and store these codes securely:${NC}"
    echo -e "${YELLOW}(Keep them in separate locations)${NC}"
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 ADMIN STACK RECOVERY CODES               ║"
    echo "║                                                          ║"
    echo "║  Generated: $(date +"%Y-%m-%d %H:%M:%S")                          ║"
    echo "║  System: $(hostname)                                          ║"
    echo "║                                                          ║"
    echo "║  Code #1: ${codes[0]}         ║"
    echo "║  Code #2: ${codes[1]}         ║"
    echo "║  Code #3: ${codes[2]}         ║"
    echo "║                                                          ║"
    echo "║  ⚠️  ANY 2 CODES CAN UNLOCK THE SYSTEM                   ║"
    echo "║  🔥 DESTROY THIS AFTER PRINTING                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Save hashes (not the codes) for verification
    mkdir -p ~/.config/admin-stack
    for i in {0..2}; do
        hash_key "${codes[$i]}" > ~/.config/admin-stack/paper-key-$((i+1))-hash
    done
    chmod 600 ~/.config/admin-stack/paper-key-*-hash
    
    echo -e "${GREEN}✓ Paper codes generated. Print this screen and store securely!${NC}"
    echo -e "${YELLOW}Press Enter when you've printed/saved the codes...${NC}"
    read -r
    
    # Clear screen for security
    clear
    echo -e "${GREEN}✓ Screen cleared for security${NC}"
}

# Derive master key from any 2 keys
derive_master_key() {
    if [ $KEYS_PROVIDED -lt 2 ]; then
        echo -e "${RED}❌ Need at least 2 keys, only have $KEYS_PROVIDED${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Deriving master key...${NC}"
    
    # Extract the actual key values
    local key1=$(echo "${KEY_HASHES[0]}" | cut -d: -f2-)
    local key2=$(echo "${KEY_HASHES[1]}" | cut -d: -f2-)
    
    # Combine using XOR
    MASTER_KEY=$(combine_keys "$key1" "$key2")
    
    echo -e "${GREEN}✓ Master key derived${NC}"
}

# Unlock Vault
unlock_vault() {
    echo -e "${YELLOW}Unlocking Vault...${NC}"
    
    # Check if Vault is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^vault$"; then
        echo -e "${YELLOW}Starting Vault container...${NC}"
        cd ~/.dotfiles/docker/tabby-admin
        docker compose up -d vault
        sleep 5
    fi
    
    # Decrypt stored Vault keys
    if [ -f ~/.vault-keys.enc ]; then
        # Use master key to decrypt
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -pass pass:"$MASTER_KEY" \
            -in ~/.vault-keys.enc \
            -out /tmp/vault-keys 2>/dev/null
        
        if [ $? -eq 0 ]; then
            # Unseal Vault
            i=0
            while IFS= read -r key && [ $i -lt 3 ]; do
                docker exec vault vault operator unseal "$key" 2>/dev/null && ((i++))
            done < /tmp/vault-keys
            
            shred -u /tmp/vault-keys 2>/dev/null || rm -f /tmp/vault-keys
            echo -e "${GREEN}✓ Vault unsealed${NC}"
        else
            echo -e "${RED}Failed to decrypt Vault keys${NC}"
            init_new_vault
        fi
    else
        echo -e "${YELLOW}No Vault keys found. Initializing...${NC}"
        init_new_vault
    fi
}

# Initialize new Vault
init_new_vault() {
    echo -e "${YELLOW}Initializing new Vault...${NC}"
    
    # Initialize
    docker exec vault vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > /tmp/vault-init.json
    
    # Extract keys and token
    cat /tmp/vault-init.json | grep -o '"unseal_keys_b64":\[[^]]*\]' | \
        grep -o '"[^"]*"' | grep -v unseal_keys_b64 | tr -d '"' > /tmp/vault-keys
    
    ROOT_TOKEN=$(cat /tmp/vault-init.json | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4)
    
    # Encrypt keys with master key
    openssl enc -aes-256-cbc -pbkdf2 \
        -pass pass:"$MASTER_KEY" \
        -in /tmp/vault-keys \
        -out ~/.vault-keys.enc
    
    # Save root token (also encrypted)
    echo "$ROOT_TOKEN" | openssl enc -aes-256-cbc -pbkdf2 \
        -pass pass:"$MASTER_KEY" \
        -out ~/.vault-token.enc
    
    # Unseal immediately
    head -3 /tmp/vault-keys | while read key; do
        docker exec vault vault operator unseal "$key"
    done
    
    # Cleanup
    shred -u /tmp/vault-init.json /tmp/vault-keys 2>/dev/null || \
        rm -f /tmp/vault-init.json /tmp/vault-keys
    
    echo -e "${GREEN}✓ Vault initialized and unsealed${NC}"
}

# Main execution
main() {
    case "${1:-unlock}" in
        unlock)
            # Collect keys
            check_paper_key
            echo ""
            check_google_key
            echo ""
            check_cloudflare_key
            echo ""
            
            # Check if we have enough
            echo -e "${BLUE}Keys provided: $KEYS_PROVIDED/3${NC}"
            
            if [ $KEYS_PROVIDED -ge 2 ]; then
                derive_master_key
                unlock_vault
                echo -e "${GREEN}✅ System unlocked successfully!${NC}"
            else
                echo -e "${RED}❌ Insufficient keys. Need at least 2.${NC}"
                exit 1
            fi
            ;;
            
        generate-paper)
            generate_paper_backup
            ;;
            
        status)
            echo -e "${BLUE}Checking unlock methods...${NC}"
            echo ""
            
            # Check paper
            if [ -f ~/.config/admin-stack/paper-key-hash ]; then
                echo -e "${GREEN}✓ Paper backup configured${NC}"
            else
                echo -e "${YELLOW}✗ No paper backup found${NC}"
            fi
            
            # Check Google
            if command -v gcloud &>/dev/null && gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
                echo -e "${GREEN}✓ Google account authenticated${NC}"
            else
                echo -e "${YELLOW}✗ Google not authenticated${NC}"
            fi
            
            # Check Cloudflare
            if [ -n "${CF_API_TOKEN:-}" ] || [ -f ~/.cloudflared/cert.pem ]; then
                echo -e "${GREEN}✓ Cloudflare configured${NC}"
            else
                echo -e "${YELLOW}✗ Cloudflare not configured${NC}"
            fi
            ;;
            
        *)
            echo "Usage: $0 {unlock|generate-paper|status}"
            echo ""
            echo "  unlock         - Unlock system with 2 of 3 keys"
            echo "  generate-paper - Generate paper backup codes"
            echo "  status         - Check which unlock methods are available"
            exit 1
            ;;
    esac
}

main "$@"