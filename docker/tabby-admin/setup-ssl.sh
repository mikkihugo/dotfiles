#!/bin/bash
#
# Setup SSL with Let's Encrypt via Cloudflare DNS
# Purpose: Automatic HTTPS for all services
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔒 Setting up SSL with Let's Encrypt${NC}"
echo ""

# Check for required environment variables
check_env() {
    if [ -z "${CF_DNS_API_TOKEN:-}" ]; then
        echo -e "${YELLOW}Cloudflare DNS API Token not found${NC}"
        echo "Enter your Cloudflare API Token (with DNS edit permissions):"
        read -s CF_DNS_API_TOKEN
        export CF_DNS_API_TOKEN
        
        # Save to .env
        echo "CF_DNS_API_TOKEN=$CF_DNS_API_TOKEN" >> .env
    fi
    
    if [ -z "${CF_API_EMAIL:-}" ]; then
        echo "Enter your Cloudflare account email:"
        read -r CF_API_EMAIL
        export CF_API_EMAIL
        echo "CF_API_EMAIL=$CF_API_EMAIL" >> .env
    fi
}

# Create acme.json with correct permissions
setup_acme() {
    echo -e "${YELLOW}Setting up ACME storage...${NC}"
    
    touch ./traefik/acme.json
    chmod 600 ./traefik/acme.json
    
    echo -e "${GREEN}✓ ACME storage configured${NC}"
}

# Generate basic auth for Traefik dashboard
setup_auth() {
    echo -e "${YELLOW}Setting up dashboard authentication...${NC}"
    
    if ! command -v htpasswd &>/dev/null; then
        echo "Installing apache2-utils for htpasswd..."
        sudo apt-get update && sudo apt-get install -y apache2-utils
    fi
    
    echo "Enter username for Traefik dashboard (default: admin):"
    read -r username
    username=${username:-admin}
    
    echo "Enter password:"
    read -s password
    
    # Generate bcrypt hash
    auth_string=$(htpasswd -nbB "$username" "$password" | sed -e s/\\$/\\$\\$/g)
    
    # Update docker-compose
    sed -i "s|traefik.http.middlewares.auth.basicauth.users=.*|traefik.http.middlewares.auth.basicauth.users=$auth_string|" docker-compose-nexus.yml
    
    echo -e "${GREEN}✓ Dashboard auth configured${NC}"
}

# Request wildcard certificate
request_wildcard() {
    echo -e "${YELLOW}Requesting wildcard certificate for *.nexus.hugo.dk...${NC}"
    
    # Start Traefik to request certs
    docker compose -f docker-compose-simple.yml up -d traefik
    
    echo "Waiting for certificate generation..."
    sleep 30
    
    # Check if cert was obtained
    if docker compose -f docker-compose-simple.yml exec traefik cat /acme.json | grep -q "nexus.hugo.dk"; then
        echo -e "${GREEN}✓ SSL certificate obtained!${NC}"
    else
        echo -e "${YELLOW}⚠ Certificate pending. Check Traefik logs:${NC}"
        echo "docker compose -f docker-compose-simple.yml logs traefik"
    fi
}

# Create DNS records in Cloudflare
setup_dns() {
    echo -e "${YELLOW}Setting up DNS records in Cloudflare...${NC}"
    
    # Get server IP
    SERVER_IP=$(curl -s https://ifconfig.me)
    echo "Server IP: $SERVER_IP"
    
    # Get Zone ID
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=hugo.dk" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')
    
    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
        echo -e "${RED}Failed to get Cloudflare Zone ID${NC}"
        exit 1
    fi
    
    # Create/update DNS records
    declare -a subdomains=("nexus" "*.nexus" "code.nexus" "vault.nexus" "tabby.nexus" "jupyter.nexus" "traefik.nexus")
    
    for subdomain in "${subdomains[@]}"; do
        echo "Creating DNS record for $subdomain.hugo.dk..."
        
        # Check if record exists
        existing=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$subdomain.hugo.dk" \
            -H "Authorization: Bearer $CF_DNS_API_TOKEN" | jq -r '.result[0].id')
        
        if [ "$existing" != "null" ] && [ -n "$existing" ]; then
            # Update existing
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$existing" \
                -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$SERVER_IP\",\"ttl\":1,\"proxied\":false}" \
                > /dev/null
        else
            # Create new
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
                -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"$subdomain\",\"content\":\"$SERVER_IP\",\"ttl\":1,\"proxied\":false}" \
                > /dev/null
        fi
    done
    
    echo -e "${GREEN}✓ DNS records configured${NC}"
}

# Main setup
main() {
    echo -e "${BLUE}Nexus Admin Stack SSL Setup${NC}"
    echo "This will configure:"
    echo "  • Let's Encrypt SSL via Cloudflare DNS"
    echo "  • Wildcard certificate for *.nexus.hugo.dk"
    echo "  • Automatic HTTPS for all services"
    echo ""
    
    # Check environment
    check_env
    
    # Setup components
    setup_acme
    setup_auth
    setup_dns
    request_wildcard
    
    echo ""
    echo -e "${GREEN}✅ SSL setup complete!${NC}"
    echo ""
    echo "Services will be available at:"
    echo "  • https://code.nexus.hugo.dk    - VS Code"
    echo "  • https://vault.nexus.hugo.dk   - Vault" 
    echo "  • https://tabby.nexus.hugo.dk   - Tabby"
    echo "  • https://jupyter.nexus.hugo.dk - Jupyter"
    echo "  • https://traefik.nexus.hugo.dk - Traefik Dashboard"
    echo ""
    echo "Start all services with:"
    echo "  docker compose -f docker-compose-simple.yml up -d"
}

# Run main or specific function
case "${1:-main}" in
    main)
        main
        ;;
    dns)
        check_env
        setup_dns
        ;;
    cert)
        check_env
        request_wildcard
        ;;
    *)
        echo "Usage: $0 {main|dns|cert}"
        exit 1
        ;;
esac