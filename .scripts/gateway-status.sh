#!/bin/bash

# Gateway Status Script - Check and update gateway deployment status
# This ensures mise tasks know the gateway is running on this server

set -e

CONTAINER_NAME="tabby-gateway"
STATUS_FILE="$HOME/.dotfiles/.gateway-status"
SERVER_IP=$(hostname -I | awk '{print $1}')

# Function to check if gateway is running
check_gateway_status() {
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "✅ Gateway is running"
        
        # Get container details
        CONTAINER_ID=$(docker ps -q -f name=$CONTAINER_NAME)
        GATEWAY_PORT=$(docker port $CONTAINER_NAME 9000 | cut -d: -f2)
        
        # Update status file
        cat > "$STATUS_FILE" << EOF
# Tabby Gateway Status
GATEWAY_DEPLOYED=true
GATEWAY_SERVER=$(hostname)
GATEWAY_IP=$SERVER_IP
GATEWAY_URL=ws://$SERVER_IP:${GATEWAY_PORT:-9000}
GATEWAY_CONTAINER_ID=$CONTAINER_ID
LAST_CHECK=$(date)
EOF
        
        # Also update .env_tokens if URL changed
        if [ -f ~/.env_tokens ]; then
            source ~/.env_tokens
            NEW_URL="ws://$SERVER_IP:${GATEWAY_PORT:-9000}"
            if [ "$TABBY_GATEWAY_URL" != "$NEW_URL" ]; then
                echo "📝 Updating gateway URL: $NEW_URL"
                sed -i "s|export TABBY_GATEWAY_URL=.*|export TABBY_GATEWAY_URL=\"$NEW_URL\"|" ~/.env_tokens
                
                # Update gist
                gh gist edit "$TABBY_GIST_ID" ~/.env_tokens
            fi
        fi
        
        return 0
    else
        echo "❌ Gateway is not running"
        cat > "$STATUS_FILE" << EOF
# Tabby Gateway Status
GATEWAY_DEPLOYED=false
GATEWAY_SERVER=$(hostname)
LAST_CHECK=$(date)
EOF
        return 1
    fi
}

# Function to ensure gateway is running
ensure_gateway() {
    if ! check_gateway_status; then
        echo "🚀 Starting gateway..."
        ~/.dotfiles/.scripts/deploy-tabby-gateway.sh
        sleep 5
        check_gateway_status
    fi
}

# Main
case "${1:-status}" in
    status)
        check_gateway_status
        if [ -f "$STATUS_FILE" ]; then
            echo ""
            cat "$STATUS_FILE"
        fi
        ;;
    ensure)
        ensure_gateway
        ;;
    update)
        # Force update status and sync
        check_gateway_status
        echo "📤 Syncing to gist..."
        ~/.dotfiles/.scripts/backup-tabby-gateway.sh
        ;;
    *)
        echo "Usage: $0 {status|ensure|update}"
        exit 1
        ;;
esac