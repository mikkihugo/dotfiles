#!/bin/bash
#
# Remote unlock via Cloudflare Worker
# Purpose: Unlock vault without entering key on server
# Version: 1.0.0

set -euo pipefail

# Cloudflare Worker endpoint for secure unlock
UNLOCK_ENDPOINT="https://unlock.hugo.dk/vault"

echo "🔐 Remote Vault Unlock"
echo ""

# Get unlock token (expires in 5 minutes)
echo "Getting unlock token..."
UNLOCK_URL=$(curl -s -X POST "$UNLOCK_ENDPOINT/request" \
    -H "Content-Type: application/json" \
    -d "{\"host\": \"$(hostname)\", \"timestamp\": \"$(date -u +%s)\"}" \
    | jq -r '.unlock_url')

echo "Unlock URL: $UNLOCK_URL"
echo ""
echo "Options:"
echo "1. Open URL in browser and authenticate"
echo "2. Use mobile app to scan QR code"
echo "3. Enter master key manually"
echo ""

# Wait for unlock
echo "Waiting for unlock..."
for i in {1..60}; do
    if curl -s "$UNLOCK_ENDPOINT/status/$(hostname)" | grep -q "unlocked"; then
        echo "✅ Vault unlocked remotely!"
        
        # Fetch encrypted key
        ENCRYPTED_KEY=$(curl -s "$UNLOCK_ENDPOINT/key/$(hostname)")
        
        # Decrypt with local identity
        MASTER_KEY=$(echo "$ENCRYPTED_KEY" | openssl rsautl -decrypt -inkey ~/.ssh/id_rsa)
        
        # Unlock local vault
        echo "$MASTER_KEY" | "$HOME/.dotfiles/docker/tabby-admin/.vault/unlock.sh"
        
        exit 0
    fi
    
    sleep 5
    echo -n "."
done

echo ""
echo "❌ Timeout - no unlock received"
exit 1