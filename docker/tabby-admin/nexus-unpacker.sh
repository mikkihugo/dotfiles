#!/bin/bash
#
# Nexus Unpacker - Single-key bootstrap system
# Purpose: Use one Cloudflare API key to unlock and setup everything
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}🔓 Nexus Unpacker${NC}"
echo "One key to rule them all..."
echo ""

# Step 1: Get initial Cloudflare API key
get_cf_key() {
    echo -e "${YELLOW}Step 1: Initial Authentication${NC}"
    
    # Check if we have it in environment
    if [ -n "${CF_API_TOKEN:-}" ]; then
        echo -e "${GREEN}✓ Found Cloudflare API token in environment${NC}"
        return 0
    fi
    
    # Check if we have it stored
    if [ -f ~/.config/nexus/cf-token.enc ] && [ -f ~/.config/nexus/unlock-hash ]; then
        echo "Enter unlock passphrase:"
        read -s passphrase
        
        # Verify passphrase
        hash=$(echo -n "$passphrase" | openssl sha256 -binary | base64)
        stored_hash=$(cat ~/.config/nexus/unlock-hash)
        
        if [ "$hash" = "$stored_hash" ]; then
            CF_API_TOKEN=$(openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:"$passphrase" -in ~/.config/nexus/cf-token.enc)
            export CF_API_TOKEN
            echo -e "${GREEN}✓ Cloudflare token decrypted${NC}"
            return 0
        else
            echo -e "${RED}✗ Invalid passphrase${NC}"
        fi
    fi
    
    # Manual input
    echo "Enter Cloudflare API Token (with Zone:Read, DNS:Edit permissions):"
    read -s CF_API_TOKEN
    export CF_API_TOKEN
    
    # Optionally save encrypted
    echo "Save encrypted for future use? (y/N):"
    read -r save_token
    if [[ "$save_token" =~ ^[Yy]$ ]]; then
        echo "Create a passphrase to encrypt the token:"
        read -s passphrase
        
        mkdir -p ~/.config/nexus
        echo "$CF_API_TOKEN" | openssl enc -aes-256-cbc -pbkdf2 -pass pass:"$passphrase" -out ~/.config/nexus/cf-token.enc
        echo -n "$passphrase" | openssl sha256 -binary | base64 > ~/.config/nexus/unlock-hash
        chmod 600 ~/.config/nexus/*
        
        echo -e "${GREEN}✓ Token saved (encrypted)${NC}"
    fi
}

# Step 2: Fetch all secrets from Cloudflare KV
fetch_from_cf_kv() {
    echo -e "${YELLOW}Step 2: Fetching configuration from Cloudflare KV...${NC}"
    
    # Get account ID
    CF_ACCOUNT_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user" \
        -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result.id')
    
    # Get KV namespace
    KV_NAMESPACE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces" \
        -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[] | select(.title=="nexus-config") | .id')
    
    if [ -z "$KV_NAMESPACE" ] || [ "$KV_NAMESPACE" = "null" ]; then
        echo -e "${YELLOW}No existing config found. Creating new...${NC}"
        create_initial_config
        return
    fi
    
    # Fetch all keys
    echo "Fetching stored configuration..."
    
    # Get Vault keys
    VAULT_KEYS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/vault-keys" \
        -H "Authorization: Bearer $CF_API_TOKEN")
    
    # Get service configs
    SERVICE_CONFIG=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/service-config" \
        -H "Authorization: Bearer $CF_API_TOKEN")
    
    # Get Warp/Tunnel config
    TUNNEL_CONFIG=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/tunnel-config" \
        -H "Authorization: Bearer $CF_API_TOKEN")
    
    echo -e "${GREEN}✓ Configuration retrieved${NC}"
}

# Step 3: Setup Cloudflare Tunnel (Warp)
setup_cf_tunnel() {
    echo -e "${YELLOW}Step 3: Setting up Cloudflare Tunnel...${NC}"
    
    # Check if tunnel exists
    TUNNEL_ID=$(echo "$TUNNEL_CONFIG" | jq -r '.tunnel_id // empty')
    
    if [ -z "$TUNNEL_ID" ]; then
        echo "Creating new Cloudflare Tunnel..."
        
        # Create tunnel
        TUNNEL_NAME="nexus-$(hostname)-$(date +%s)"
        TUNNEL_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/tunnels" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$(openssl rand -base64 32)\"}")
        
        TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.id')
        TUNNEL_TOKEN=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.token')
        
        # Save tunnel config
        echo "$TUNNEL_RESPONSE" > ~/.config/nexus/tunnel.json
        
        # Store in KV
        curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/tunnel-config" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            --data "{\"tunnel_id\":\"$TUNNEL_ID\",\"tunnel_token\":\"$TUNNEL_TOKEN\"}"
    else
        echo -e "${GREEN}✓ Using existing tunnel${NC}"
        TUNNEL_TOKEN=$(echo "$TUNNEL_CONFIG" | jq -r '.tunnel_token')
    fi
    
    # Configure tunnel routes
    configure_tunnel_routes
}

# Step 4: Configure DNS and routes
configure_tunnel_routes() {
    echo -e "${YELLOW}Configuring tunnel routes...${NC}"
    
    # Get zone ID
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=hugo.dk" \
        -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[0].id')
    
    # Services to expose
    declare -A services=(
        ["code"]="ai-dev:8080"
        ["vault"]="vault:8200"
        ["tabby"]="tabby-web:9090"
        ["jupyter"]="ai-dev:8888"
        ["traefik"]="traefik:8080"
    )
    
    # Create DNS records and tunnel config
    for subdomain in "${!services[@]}"; do
        # Create CNAME to tunnel
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\":\"CNAME\",
                \"name\":\"$subdomain.nexus\",
                \"content\":\"$TUNNEL_ID.cfargotunnel.com\",
                \"proxied\":true
            }" > /dev/null || true
    done
    
    # Create tunnel config file
    cat > ~/.config/nexus/tunnel-config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: /etc/cloudflared/creds.json

ingress:
EOF
    
    for subdomain in "${!services[@]}"; do
        cat >> ~/.config/nexus/tunnel-config.yml << EOF
  - hostname: $subdomain.nexus.hugo.dk
    service: http://${services[$subdomain]}
EOF
    done
    
    cat >> ~/.config/nexus/tunnel-config.yml << EOF
  - service: http_status:404
EOF
    
    echo -e "${GREEN}✓ Tunnel routes configured${NC}"
}

# Step 5: Deploy everything
deploy_nexus() {
    echo -e "${YELLOW}Step 4: Deploying Nexus stack...${NC}"
    
    # Create .env file
    cat > .env << EOF
# Generated by Nexus Unpacker
CF_API_TOKEN=$CF_API_TOKEN
CF_ACCOUNT_ID=$CF_ACCOUNT_ID
CF_ZONE_ID=$ZONE_ID
TUNNEL_TOKEN=$TUNNEL_TOKEN

# API Keys (will be fetched from Vault)
OPENAI_API_KEY=\${OPENAI_API_KEY:-placeholder}
ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-placeholder}
GITHUB_TOKEN=\${GITHUB_TOKEN:-placeholder}
EOF
    
    # Add tunnel service to docker-compose
    cat >> docker-compose-nexus.yml << EOF

  # Cloudflare Tunnel
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    volumes:
      - ~/.config/nexus/tunnel-config.yml:/etc/cloudflared/config.yml:ro
      - ~/.config/nexus/tunnel.json:/etc/cloudflared/creds.json:ro
    networks:
      - default
EOF
    
    # Start services
    docker compose -f docker-compose-nexus.yml up -d
    
    echo -e "${GREEN}✓ Nexus stack deployed${NC}"
}

# Step 6: Initialize Vault if needed
init_vault() {
    echo -e "${YELLOW}Step 5: Initializing Vault...${NC}"
    
    # Wait for Vault
    sleep 5
    
    if [ -z "$VAULT_KEYS" ] || [ "$VAULT_KEYS" = "null" ]; then
        echo "Initializing new Vault..."
        
        # Initialize
        INIT_RESPONSE=$(docker exec vault vault operator init -key-shares=3 -key-threshold=2 -format=json)
        
        # Store in Cloudflare KV
        curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/vault-keys" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            --data "$INIT_RESPONSE"
        
        # Unseal
        echo "$INIT_RESPONSE" | jq -r '.unseal_keys_b64[]' | head -2 | while read key; do
            docker exec vault vault operator unseal "$key"
        done
        
        # Login
        ROOT_TOKEN=$(echo "$INIT_RESPONSE" | jq -r '.root_token')
        docker exec vault vault login "$ROOT_TOKEN"
        
        echo -e "${GREEN}✓ Vault initialized${NC}"
    else
        echo "Unsealing existing Vault..."
        echo "$VAULT_KEYS" | jq -r '.unseal_keys_b64[]' | head -2 | while read key; do
            docker exec vault vault operator unseal "$key"
        done
        echo -e "${GREEN}✓ Vault unsealed${NC}"
    fi
}

# Create initial configuration
create_initial_config() {
    echo -e "${BLUE}Creating initial Nexus configuration...${NC}"
    
    # Create KV namespace
    KV_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"title":"nexus-config"}')
    
    KV_NAMESPACE=$(echo "$KV_RESPONSE" | jq -r '.result.id')
    
    # Store initial config
    curl -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/storage/kv/namespaces/$KV_NAMESPACE/values/service-config" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        --data '{
            "created": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "hostname": "'$(hostname)'",
            "version": "1.0.0"
        }'
    
    echo -e "${GREEN}✓ Initial configuration created${NC}"
}

# Show summary
show_summary() {
    echo ""
    echo -e "${GREEN}✅ Nexus deployment complete!${NC}"
    echo ""
    echo "Your services are available at:"
    echo "  • https://code.nexus.hugo.dk    - AI Development Environment"
    echo "  • https://vault.nexus.hugo.dk   - Secret Management"
    echo "  • https://tabby.nexus.hugo.dk   - Tabby Terminal"
    echo "  • https://jupyter.nexus.hugo.dk - Jupyter Notebooks"
    echo ""
    echo "Everything is secured through Cloudflare Tunnel - no ports exposed!"
    echo ""
    echo "To access Vault UI, get the root token:"
    echo "  docker exec vault cat /root/.vault-token"
}

# Main execution
main() {
    echo -e "${BLUE}Starting Nexus deployment...${NC}"
    echo "This will:"
    echo "  1. Use your Cloudflare API key to fetch/create config"
    echo "  2. Setup Cloudflare Tunnel (Warp) automatically"
    echo "  3. Deploy all services behind the tunnel"
    echo "  4. Configure DNS and SSL automatically"
    echo ""
    
    # Execute steps
    get_cf_key
    fetch_from_cf_kv
    setup_cf_tunnel
    deploy_nexus
    init_vault
    show_summary
}

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up Nexus deployment...${NC}"
    
    # Remove services
    docker compose -f docker-compose-nexus.yml down
    
    # Optionally remove data
    echo "Remove all data? (y/N):"
    read -r remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        docker volume rm $(docker volume ls -q | grep nexus) 2>/dev/null || true
        rm -rf ~/.config/nexus
    fi
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Parse command
case "${1:-deploy}" in
    deploy)
        main
        ;;
    cleanup)
        cleanup
        ;;
    status)
        docker compose -f docker-compose-nexus.yml ps
        ;;
    *)
        echo "Usage: $0 {deploy|cleanup|status}"
        echo ""
        echo "  deploy  - Deploy Nexus stack with one key"
        echo "  cleanup - Remove Nexus deployment"
        echo "  status  - Show service status"
        exit 1
        ;;
esac