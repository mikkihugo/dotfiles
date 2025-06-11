#!/bin/bash
#
# Layered Security Unlock System
# Purpose: CF + Google + Vault master secret management
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔐 Layered Security Unlock${NC}"
echo ""

# Step 1: Google Authentication
echo -e "${YELLOW}Step 1: Google Authentication${NC}"
if ! gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    echo "Authenticating with Google..."
    gcloud auth login --brief
else
    echo -e "${GREEN}✓ Already authenticated with Google${NC}"
fi

# Step 2: Get Cloudflare unlock key from Google Secret Manager
echo -e "${YELLOW}Step 2: Fetching CF unlock key from Google${NC}"
CF_UNLOCK_KEY=$(gcloud secrets versions access latest --secret="cf-unlock-key" 2>/dev/null)

if [ -z "$CF_UNLOCK_KEY" ]; then
    echo -e "${RED}❌ No CF unlock key in Google Secret Manager${NC}"
    echo "First-time setup needed. Enter Cloudflare unlock key:"
    read -s CF_UNLOCK_KEY
    echo "$CF_UNLOCK_KEY" | gcloud secrets create cf-unlock-key --data-file=-
fi

# Step 3: Use CF key to get Vault unseal keys
echo -e "${YELLOW}Step 3: Fetching Vault keys from Cloudflare${NC}"
VAULT_UNSEAL_KEYS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/kv/namespaces/${CF_KV_NAMESPACE}/values/vault-unseal-keys" \
    -H "Authorization: Bearer ${CF_UNLOCK_KEY}" | jq -r '.result')

# Step 4: Start Vault if not running
if ! docker-compose ps vault | grep -q "Up"; then
    echo -e "${YELLOW}Starting Vault...${NC}"
    docker-compose up -d vault
    sleep 5
fi

# Step 5: Initialize Vault if needed
VAULT_ADDR="http://localhost:8200"
export VAULT_ADDR

if ! curl -s $VAULT_ADDR/v1/sys/health | grep -q "initialized\":true"; then
    echo -e "${YELLOW}Initializing Vault...${NC}"
    
    # Initialize with 5 keys, threshold 3
    INIT_OUTPUT=$(docker exec vault vault operator init -key-shares=5 -key-threshold=3 -format=json)
    
    # Save unseal keys to both CF and Google
    echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]' > /tmp/vault-keys
    echo "$INIT_OUTPUT" | jq -r '.root_token' > /tmp/vault-root-token
    
    # Store in Cloudflare KV
    curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/kv/namespaces/${CF_KV_NAMESPACE}/values/vault-unseal-keys" \
        -H "Authorization: Bearer ${CF_UNLOCK_KEY}" \
        --data-binary @/tmp/vault-keys
    
    # Backup to Google Secret Manager
    gcloud secrets create vault-unseal-keys --data-file=/tmp/vault-keys
    gcloud secrets create vault-root-token --data-file=/tmp/vault-root-token
    
    # Clean up
    shred -u /tmp/vault-keys /tmp/vault-root-token
    
    VAULT_UNSEAL_KEYS=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[]')
    ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
else
    echo -e "${GREEN}✓ Vault already initialized${NC}"
fi

# Step 6: Unseal Vault
if curl -s $VAULT_ADDR/v1/sys/health | grep -q "sealed\":true"; then
    echo -e "${YELLOW}Unsealing Vault...${NC}"
    
    # Use first 3 keys to unseal
    echo "$VAULT_UNSEAL_KEYS" | head -3 | while read key; do
        docker exec vault vault operator unseal "$key"
    done
    
    echo -e "${GREEN}✓ Vault unsealed${NC}"
else
    echo -e "${GREEN}✓ Vault already unsealed${NC}"
fi

# Step 7: Login to Vault
if [ -z "${ROOT_TOKEN:-}" ]; then
    ROOT_TOKEN=$(gcloud secrets versions access latest --secret="vault-root-token" 2>/dev/null)
fi

docker exec vault vault login "$ROOT_TOKEN"

# Step 8: Populate all service secrets in Vault
echo -e "${YELLOW}Step 4: Loading secrets into Vault...${NC}"

# Enable KV v2 secret engine
docker exec vault vault secrets enable -version=2 -path=secret kv 2>/dev/null || true

# Load all secrets
cat > /tmp/vault-secrets.sh << 'EOF'
#!/bin/sh
vault kv put secret/cloudflare \
    api_token="$CF_API_TOKEN" \
    zone_id="$CF_ZONE_ID" \
    account_id="$CF_ACCOUNT_ID"

vault kv put secret/github \
    token="$GITHUB_TOKEN" \
    client_id="$GITHUB_CLIENT_ID" \
    client_secret="$GITHUB_CLIENT_SECRET"

vault kv put secret/services \
    warpgate_admin_pass="$WARPGATE_ADMIN_PASS" \
    drone_rpc_secret="$DRONE_RPC_SECRET" \
    backup_key="$BACKUP_ENCRYPTION_KEY"
EOF

# Get secrets from Google and load into Vault
source <(gcloud secrets versions access latest --secret="service-env")
docker cp /tmp/vault-secrets.sh vault:/tmp/
docker exec vault sh /tmp/vault-secrets.sh
rm /tmp/vault-secrets.sh

# Step 9: Configure Vault for services
echo -e "${YELLOW}Configuring Vault policies...${NC}"

# Create policy for services
cat > /tmp/service-policy.hcl << 'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
EOF

docker cp /tmp/service-policy.hcl vault:/tmp/
docker exec vault vault policy write service-policy /tmp/service-policy.hcl

# Enable AppRole auth
docker exec vault vault auth enable approle 2>/dev/null || true

# Create role for services
docker exec vault vault write auth/approle/role/services \
    token_policies="service-policy" \
    token_ttl=1h \
    token_max_ttl=4h

# Step 10: Start all services
echo -e "${YELLOW}Starting all services...${NC}"
docker-compose up -d

echo -e "${GREEN}✅ All services unlocked and running!${NC}"
echo ""
echo "Vault UI: http://localhost:8200"
echo "Use root token to manage secrets"