#!/bin/bash
#
# Flexible M-of-N Unlock System
# Purpose: Require M keys out of N possible unlock methods
# Version: 3.0.0

set -euo pipefail

# Configuration
REQUIRED_KEYS=2  # How many keys needed (can be changed to 3)
TOTAL_METHODS=10  # Total number of possible unlock methods

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}🔐 Flexible Unlock System${NC}"
echo -e "${PURPLE}Require $REQUIRED_KEYS out of $TOTAL_METHODS possible methods${NC}"
echo ""

# Track collected keys
COLLECTED_KEYS=()
COLLECTED_COUNT=0

# Add a key to collection
add_key() {
    local method=$1
    local value=$2
    COLLECTED_KEYS+=("$method:$value")
    ((COLLECTED_COUNT++))
    echo -e "${GREEN}✓ Added $method key ($COLLECTED_COUNT/$REQUIRED_KEYS)${NC}"
}

# 1. Paper Backup Codes (can have multiple)
check_paper_codes() {
    echo -e "${YELLOW}📄 Paper Backup Codes${NC}"
    
    for i in {1..3}; do
        if [ -f ~/.config/admin-stack/paper-$i.hash ]; then
            echo "Enter Paper Code #$i (or press Enter to skip):"
            read -s code
            if [ -n "$code" ]; then
                local hash=$(echo -n "$code" | openssl sha256 -binary | base64)
                local stored=$(cat ~/.config/admin-stack/paper-$i.hash)
                if [ "$hash" = "$stored" ]; then
                    add_key "paper-$i" "$code"
                    return 0
                fi
            fi
        fi
    done
    
    echo "Enter any paper backup code (or Enter to skip):"
    read -s code
    [ -n "$code" ] && add_key "paper-manual" "$code"
}

# 2. Google Account
check_google() {
    echo -e "${YELLOW}🔑 Google Account${NC}"
    
    if command -v gcloud &>/dev/null && gcloud auth list 2>/dev/null | grep -q ACTIVE; then
        local email=$(gcloud config get-value account 2>/dev/null)
        add_key "google" "$email"
        return 0
    fi
    
    echo "Google OAuth code (or Enter to skip):"
    read -s code
    [ -n "$code" ] && add_key "google-oauth" "$code"
}

# 3. GitHub Account  
check_github() {
    echo -e "${YELLOW}🐙 GitHub Account${NC}"
    
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        local user=$(gh api user --jq .login)
        add_key "github" "$user"
        return 0
    fi
    
    echo "GitHub token (or Enter to skip):"
    read -s token
    [ -n "$token" ] && add_key "github-token" "$token"
}

# 4. Cloudflare API
check_cloudflare() {
    echo -e "${YELLOW}☁️  Cloudflare${NC}"
    
    if [ -n "${CF_API_TOKEN:-}" ]; then
        add_key "cloudflare-env" "$CF_API_TOKEN"
        return 0
    fi
    
    if command -v wrangler &>/dev/null && wrangler whoami &>/dev/null 2>&1; then
        local email=$(wrangler whoami 2>&1 | grep -oE "[^[:space:]]+@[^[:space:]]+")
        add_key "cloudflare-wrangler" "$email"
        return 0
    fi
    
    echo "Cloudflare API token (or Enter to skip):"
    read -s token
    [ -n "$token" ] && add_key "cloudflare-manual" "$token"
}

# 5. SSH Key
check_ssh_key() {
    echo -e "${YELLOW}🔑 SSH Key${NC}"
    
    if [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_rsa ]; then
        echo "Use SSH key for unlock? (y/N):"
        read -r use_ssh
        if [[ "$use_ssh" =~ ^[Yy]$ ]]; then
            # Create challenge
            local challenge=$(openssl rand -hex 32)
            echo "$challenge" > /tmp/unlock-challenge
            
            # Sign with SSH key
            if ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n unlock /tmp/unlock-challenge 2>/dev/null; then
                local sig=$(cat /tmp/unlock-challenge.sig | base64 -w0)
                add_key "ssh-ed25519" "$sig"
                rm -f /tmp/unlock-challenge*
                return 0
            fi
        fi
    fi
}

# 6. Biometric (Touch ID / Windows Hello via simulated)
check_biometric() {
    echo -e "${YELLOW}👆 Biometric${NC}"
    
    # On Mac with Touch ID
    if [[ "$OSTYPE" == "darwin"* ]] && command -v sudo &>/dev/null; then
        echo "Authenticate with Touch ID..."
        if sudo -k && sudo -v 2>/dev/null; then
            add_key "biometric-touchid" "$(date +%s)"
            return 0
        fi
    fi
    
    # Fallback PIN
    echo "Enter PIN (or Enter to skip):"
    read -s pin
    [ -n "$pin" ] && add_key "biometric-pin" "$pin"
}

# 7. TOTP/2FA Code
check_totp() {
    echo -e "${YELLOW}📱 TOTP/2FA Code${NC}"
    
    if [ -f ~/.config/admin-stack/totp-secret ]; then
        echo "Enter current TOTP code:"
        read -r totp_code
        
        if [ -n "$totp_code" ]; then
            # In real implementation, verify against secret
            add_key "totp" "$totp_code"
            return 0
        fi
    else
        echo "No TOTP configured. Setup? (y/N):"
        read -r setup_totp
        if [[ "$setup_totp" =~ ^[Yy]$ ]]; then
            # Generate TOTP secret
            local secret=$(openssl rand -base32 32 | head -c 32)
            echo "$secret" > ~/.config/admin-stack/totp-secret
            chmod 600 ~/.config/admin-stack/totp-secret
            
            echo "Add this to your authenticator app:"
            echo "Secret: $secret"
            echo "Or scan QR at: https://api.qrserver.com/v1/create-qr-code/?data=otpauth://totp/AdminStack:$USER@$(hostname)?secret=$secret"
        fi
    fi
}

# 8. Hardware Token (YubiKey simulation)
check_hardware_token() {
    echo -e "${YELLOW}🔐 Hardware Token${NC}"
    
    # Check for YubiKey
    if command -v ykman &>/dev/null && ykman list 2>/dev/null | grep -q "YubiKey"; then
        echo "Touch YubiKey..."
        local challenge=$(openssl rand -hex 32)
        if ykman oath accounts code "admin-stack" 2>/dev/null; then
            add_key "yubikey" "$challenge"
            return 0
        fi
    fi
    
    echo "Hardware token code (or Enter to skip):"
    read -s code
    [ -n "$code" ] && add_key "hardware-manual" "$code"
}

# 9. Recovery Email
check_recovery_email() {
    echo -e "${YELLOW}📧 Recovery Email${NC}"
    
    if [ -f ~/.config/admin-stack/recovery-email ]; then
        local stored_email=$(cat ~/.config/admin-stack/recovery-email)
        echo "Send code to $stored_email? (y/N):"
        read -r send_code
        
        if [[ "$send_code" =~ ^[Yy]$ ]]; then
            # In real implementation, send email
            local code=$(openssl rand -hex 4)
            echo -e "${BLUE}Code sent to email (simulated): $code${NC}"
            echo "Enter code from email:"
            read -r entered_code
            
            if [ "$entered_code" = "$code" ]; then
                add_key "email" "$stored_email"
                return 0
            fi
        fi
    else
        echo "Setup recovery email? (y/N):"
        read -r setup_email
        if [[ "$setup_email" =~ ^[Yy]$ ]]; then
            echo "Enter recovery email:"
            read -r email
            echo "$email" > ~/.config/admin-stack/recovery-email
            chmod 600 ~/.config/admin-stack/recovery-email
        fi
    fi
}

# 10. Security Questions
check_security_questions() {
    echo -e "${YELLOW}❓ Security Questions${NC}"
    
    if [ -f ~/.config/admin-stack/security-qa.enc ]; then
        echo "Answer security question:"
        echo "Q: What was your first computer?"
        read -s answer
        
        if [ -n "$answer" ]; then
            # Hash and compare
            local hash=$(echo -n "$answer" | tr '[:upper:]' '[:lower:]' | openssl sha256 -binary | base64)
            # In real implementation, decrypt and compare
            add_key "security-qa" "$hash"
            return 0
        fi
    else
        echo "No security questions configured"
    fi
}

# Generate master key from collected keys
derive_master_key() {
    echo -e "${YELLOW}Deriving master key from $COLLECTED_COUNT keys...${NC}"
    
    # Sort keys for deterministic output
    IFS=$'\n' sorted=($(sort <<<"${COLLECTED_KEYS[*]}"))
    
    # Use first N keys (where N = REQUIRED_KEYS)
    local combined=""
    for ((i=0; i<REQUIRED_KEYS && i<${#sorted[@]}; i++)); do
        local key_data=$(echo "${sorted[$i]}" | cut -d: -f2-)
        combined+="$key_data"
    done
    
    # Generate master key
    MASTER_KEY=$(echo -n "$combined" | openssl sha256 -binary | xxd -p)
    echo -e "${GREEN}✓ Master key derived${NC}"
}

# Unlock the system
perform_unlock() {
    echo -e "${BLUE}Unlocking system...${NC}"
    
    # Start services
    cd ~/.dotfiles/docker/tabby-admin
    
    # Decrypt vault keys with master
    if [ -f ~/.vault-keys.enc ]; then
        openssl enc -d -aes-256-cbc -pbkdf2 \
            -pass pass:"$MASTER_KEY" \
            -in ~/.vault-keys.enc \
            -out /tmp/vault-keys 2>/dev/null
        
        # Start and unseal Vault
        docker compose up -d vault
        sleep 3
        
        head -3 /tmp/vault-keys | while read key; do
            docker exec vault vault operator unseal "$key" 2>/dev/null
        done
        
        shred -u /tmp/vault-keys 2>/dev/null || rm -f /tmp/vault-keys
    fi
    
    # Start all services
    docker compose up -d
    
    echo -e "${GREEN}✅ System unlocked!${NC}"
}

# Show status
show_status() {
    echo -e "${BLUE}Available Unlock Methods:${NC}"
    echo ""
    
    local available=0
    
    # Check each method
    [ -f ~/.config/admin-stack/paper-1.hash ] && echo -e "${GREEN}✓ Paper codes${NC}" && ((available++))
    command -v gcloud &>/dev/null && gcloud auth list 2>/dev/null | grep -q ACTIVE && echo -e "${GREEN}✓ Google${NC}" && ((available++))
    command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1 && echo -e "${GREEN}✓ GitHub${NC}" && ((available++))
    [ -n "${CF_API_TOKEN:-}" ] && echo -e "${GREEN}✓ Cloudflare${NC}" && ((available++))
    [ -f ~/.ssh/id_ed25519 ] || [ -f ~/.ssh/id_rsa ] && echo -e "${GREEN}✓ SSH key${NC}" && ((available++))
    [ -f ~/.config/admin-stack/totp-secret ] && echo -e "${GREEN}✓ TOTP configured${NC}" && ((available++))
    [ -f ~/.config/admin-stack/recovery-email ] && echo -e "${GREEN}✓ Recovery email${NC}" && ((available++))
    [ -f ~/.config/admin-stack/security-qa.enc ] && echo -e "${GREEN}✓ Security questions${NC}" && ((available++))
    
    echo ""
    echo -e "${BLUE}Total available: $available/$TOTAL_METHODS${NC}"
    echo -e "${PURPLE}Required for unlock: $REQUIRED_KEYS${NC}"
}

# Main menu
main() {
    case "${1:-unlock}" in
        unlock)
            # Try each method
            local methods=(
                check_paper_codes
                check_google
                check_github
                check_cloudflare
                check_ssh_key
                check_biometric
                check_totp
                check_hardware_token
                check_recovery_email
                check_security_questions
            )
            
            for method in "${methods[@]}"; do
                if [ $COLLECTED_COUNT -ge $REQUIRED_KEYS ]; then
                    echo -e "${GREEN}Sufficient keys collected!${NC}"
                    break
                fi
                echo ""
                $method
            done
            
            echo ""
            echo -e "${BLUE}Collected: $COLLECTED_COUNT/$REQUIRED_KEYS keys${NC}"
            
            if [ $COLLECTED_COUNT -ge $REQUIRED_KEYS ]; then
                derive_master_key
                perform_unlock
            else
                echo -e "${RED}❌ Insufficient keys${NC}"
                exit 1
            fi
            ;;
            
        status)
            show_status
            ;;
            
        setup)
            echo -e "${BLUE}Setup Wizard${NC}"
            echo "This will help you configure multiple unlock methods"
            # ... setup wizard implementation
            ;;
            
        config)
            echo "Current configuration:"
            echo "Required keys: $REQUIRED_KEYS"
            echo "Total methods: $TOTAL_METHODS"
            echo ""
            echo "Change required keys? (current: $REQUIRED_KEYS)"
            read -r new_required
            if [[ "$new_required" =~ ^[0-9]+$ ]]; then
                sed -i "s/^REQUIRED_KEYS=.*/REQUIRED_KEYS=$new_required/" "$0"
                echo "Updated to require $new_required keys"
            fi
            ;;
            
        *)
            echo "Usage: $0 {unlock|status|setup|config}"
            exit 1
            ;;
    esac
}

main "$@"