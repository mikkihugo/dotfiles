#!/bin/bash
# Cloudflare Tunnel Management with Wrangler
# Handles tunnel creation, configuration, and Zero Trust setup

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-hugo-services}"
CONFIG_FILE="$(dirname "$0")/wrangler-config.json"

# Check if wrangler is installed
check_wrangler() {
    if ! command -v wrangler &> /dev/null; then
        warn "Wrangler not found. Installing..."
        npm install -g wrangler
        success "Wrangler installed"
    fi
}

# Authenticate with Cloudflare
authenticate() {
    log "Authenticating with Cloudflare..."
    
    if [[ -n "$WRANGLER_CF_API_TOKEN" ]]; then
        export CLOUDFLARE_API_TOKEN="$WRANGLER_CF_API_TOKEN"
        success "Using API token authentication"
    else
        warn "No API token found, using interactive login..."
        wrangler auth login
    fi
}

# Create tunnel if it doesn't exist
create_tunnel() {
    log "Checking tunnel '$TUNNEL_NAME'..."
    
    if wrangler tunnel list | grep -q "$TUNNEL_NAME"; then
        success "Tunnel '$TUNNEL_NAME' already exists"
        return 0
    fi
    
    log "Creating tunnel '$TUNNEL_NAME'..."
    wrangler tunnel create "$TUNNEL_NAME"
    success "Tunnel created"
}

# Configure tunnel routing
configure_tunnel() {
    log "Configuring tunnel routes..."
    
    # Set up DNS records for each service
    declare -A SERVICES=(
        ["ai"]="10001"
        ["terminal"]="10002"
        ["ssh"]="10022"
        ["monitor"]="10004"
    )
    
    for service in "${!SERVICES[@]}"; do
        port="${SERVICES[$service]}"
        subdomain="${service}.se.hugo.dk"
        
        log "Setting up route: $subdomain -> localhost:$port"
        
        # Create DNS record
        wrangler tunnel route dns "$TUNNEL_NAME" "$subdomain" || {
            warn "DNS record may already exist for $subdomain"
        }
    done
    
    success "Tunnel routes configured"
}

# Set up Zero Trust Access policies
setup_zero_trust() {
    log "Setting up Cloudflare Zero Trust policies..."
    
    # Note: This would typically be done via Cloudflare API or dashboard
    # For now, just log the required setup
    
    cat << EOF
📋 Zero Trust Setup Required:

1. Go to Cloudflare Zero Trust Dashboard
2. Create Application for each service:
   - ai.se.hugo.dk (AI Gateway)
   - terminal.se.hugo.dk (Warp Terminal)  
   - ssh.se.hugo.dk (SSH Access)
   - monitor.se.hugo.dk (Monitoring)

3. Set up policies:
   - Email: mikki@hugo.dk
   - Identity Provider: Google OAuth
   - Session Duration: 24h

4. Configure in tunnel authentication mode
EOF

    warn "Zero Trust policies need manual setup in CF dashboard"
}

# Get tunnel token
get_tunnel_token() {
    log "Getting tunnel token..."
    
    TOKEN=$(wrangler tunnel token "$TUNNEL_NAME" 2>/dev/null || echo "")
    
    if [[ -n "$TOKEN" ]]; then
        success "Tunnel token retrieved"
        echo "Add this to your .env_docker file:"
        echo "export CLOUDFLARE_TUNNEL_TOKEN=\"$TOKEN\""
    else
        error "Failed to get tunnel token"
    fi
}

# Start tunnel locally for testing
test_tunnel() {
    log "Testing tunnel locally..."
    
    log "Starting services first..."
    docker-compose up -d
    
    sleep 5
    
    log "Running tunnel..."
    wrangler tunnel run --config "$CONFIG_FILE" "$TUNNEL_NAME"
}

# Main execution
case "${1:-help}" in
    "setup")
        check_wrangler
        authenticate
        create_tunnel
        configure_tunnel
        setup_zero_trust
        get_tunnel_token
        ;;
    "start")
        docker-compose up -d
        success "Services started"
        ;;
    "stop")
        docker-compose down
        success "Services stopped"
        ;;
    "test")
        test_tunnel
        ;;
    "token")
        get_tunnel_token
        ;;
    "status")
        wrangler tunnel list
        docker-compose ps
        ;;
    "help"|*)
        echo "Cloudflare Tunnel Management"
        echo "=========================="
        echo ""
        echo "Commands:"
        echo "  setup  - Initial tunnel setup with Zero Trust"
        echo "  start  - Start all services"  
        echo "  stop   - Stop all services"
        echo "  test   - Test tunnel locally"
        echo "  token  - Get tunnel token"
        echo "  status - Show tunnel and service status"
        ;;
esac