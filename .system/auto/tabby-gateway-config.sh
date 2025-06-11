#!/bin/bash

# Tabby Gateway Auto-Configuration Script
# Syncs gateway config from gist and updates Tabby config

set -e

# Source tokens
if [ -f ~/.env_tokens ]; then
    source ~/.env_tokens
else
    echo "❌ ~/.env_tokens not found"
    exit 1
fi

# Function to update Tabby config with gateway settings
update_tabby_gateway() {
    local config_file="$HOME/.config/tabby/config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ Tabby config not found at $config_file"
        return 1
    fi
    
    # Backup current config
    cp "$config_file" "$config_file.bak"
    
    # Check if gateway config exists
    if grep -q "connectionGateway:" "$config_file"; then
        echo "📝 Updating existing gateway config..."
        # Update existing config using yq or sed
        sed -i.tmp '/connectionGateway:/,/^[^ ]/{
            s|url:.*|url: '"$TABBY_GATEWAY_URL"'|
            s|token:.*|token: '"$TABBY_GATEWAY_TOKEN"'|
        }' "$config_file"
        rm "$config_file.tmp"
    else
        echo "➕ Adding gateway config..."
        # Add gateway config
        cat >> "$config_file" << EOF
connectionGateway:
  enabled: true
  url: $TABBY_GATEWAY_URL
  token: $TABBY_GATEWAY_TOKEN
EOF
    fi
    
    echo "✅ Gateway config updated"
}

# Function to sync from gist
sync_from_gist() {
    echo "🔄 Syncing gateway config from gist..."
    
    # Download tokens from gist
    gh gist view "$TABBY_GIST_ID" -f .env_tokens > ~/.env_tokens.tmp
    
    if [ -s ~/.env_tokens.tmp ]; then
        mv ~/.env_tokens.tmp ~/.env_tokens
        source ~/.env_tokens
        echo "✅ Tokens synced from gist"
    else
        rm -f ~/.env_tokens.tmp
        echo "❌ Failed to sync from gist"
        return 1
    fi
}

# Main
case "${1:-sync}" in
    sync)
        sync_from_gist
        update_tabby_gateway
        ;;
    update)
        update_tabby_gateway
        ;;
    backup)
        # Backup gateway config to gist
        echo "📤 Backing up gateway config to gist..."
        gh gist edit "$TABBY_GIST_ID" ~/.env_tokens
        
        # Also create a dedicated gateway config gist
        if [ -z "$TABBY_GATEWAY_GIST_ID" ]; then
            echo "Creating new gateway config gist..."
            cat > /tmp/tabby-gateway.yaml << EOF
# Tabby Gateway Configuration
gateway:
  url: $TABBY_GATEWAY_URL
  token: $TABBY_GATEWAY_TOKEN
  deployed: $(date)
  server: $(hostname)
EOF
            GATEWAY_GIST_ID=$(gh gist create /tmp/tabby-gateway.yaml --desc "Tabby Gateway Config" | grep -oE '[a-f0-9]{32}')
            echo "export TABBY_GATEWAY_GIST_ID=$GATEWAY_GIST_ID" >> ~/.env_tokens
            rm /tmp/tabby-gateway.yaml
        fi
        ;;
    *)
        echo "Usage: $0 {sync|update|backup}"
        exit 1
        ;;
esac