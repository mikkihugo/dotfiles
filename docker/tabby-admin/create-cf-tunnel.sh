#!/bin/bash
#
# Create Cloudflare Tunnel for Nexus
# Purpose: Set up CF Tunnel for remote access
# Version: 1.0.0

set -euo pipefail

source ~/.dotfiles/.env_tokens

echo "🚇 Creating Cloudflare Tunnel for Nexus"
echo ""

# Create tunnel
TUNNEL_NAME="nexus-$(hostname)-$(date +%s)"
TUNNEL_SECRET=$(openssl rand -base64 32)

echo "Creating tunnel: $TUNNEL_NAME"

# Create tunnel via API (single line to avoid bash issues)
TUNNEL_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" --data "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$TUNNEL_SECRET\"}")

# Extract tunnel ID
TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.id')
TUNNEL_TOKEN=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.token')

if [ "$TUNNEL_ID" = "null" ]; then
    echo "❌ Failed to create tunnel:"
    echo "$TUNNEL_RESPONSE" | jq '.errors'
    exit 1
fi

echo "✅ Tunnel created: $TUNNEL_ID"

# Save tunnel config
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: ~/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: code.nexus.hugo.dk
    service: http://localhost:10080
  - hostname: jupyter.nexus.hugo.dk  
    service: http://localhost:10888
  - hostname: vault.nexus.hugo.dk
    service: http://localhost:10200
  - service: http_status:404
EOF

# Create credentials file
echo "$TUNNEL_RESPONSE" | jq '.result' > ~/.cloudflared/$TUNNEL_ID.json

# Get zone ID for hugo.dk
ZONE_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones?name=hugo.dk" -H "Authorization: Bearer $CF_API_TOKEN" | jq -r '.result[0].id')

echo "Zone ID: $ZONE_ID"

# Create DNS records
for subdomain in code jupyter vault; do
    echo "Creating DNS record for $subdomain.nexus.hugo.dk..."
    
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\":\"CNAME\",
            \"name\":\"$subdomain.nexus\",
            \"content\":\"$TUNNEL_ID.cfargotunnel.com\",
            \"proxied\":true
        }" > /dev/null
done

echo ""
echo "✅ Tunnel configured!"
echo ""
echo "Your services will be available at:"
echo "• https://code.nexus.hugo.dk"
echo "• https://jupyter.nexus.hugo.dk"  
echo "• https://vault.nexus.hugo.dk"
echo ""
echo "To start the tunnel:"
echo "  ~/.local/bin/cloudflared tunnel run $TUNNEL_ID"
echo ""
echo "Or save this for later:"
echo "  export TUNNEL_ID=$TUNNEL_ID"