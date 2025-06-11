#!/bin/bash

# Simple Tabby Sync - Just Tabby ↔ Gist ↔ SSH Config
# No migration tools, clean and simple

set -e

GIST_ID="${TABBY_GIST_ID:-$UNIFIED_HOSTS_GIST_ID}"
TABBY_CONFIG="$HOME/.config/tabby/config.yaml"
HOSTS_JSON="$HOME/.tabby-hosts.json"

# Check essentials
check_setup() {
    if [ -z "$GIST_ID" ]; then
        echo "❌ Set TABBY_GIST_ID in ~/.env_tokens"
        exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo "❌ Install jq: mise install jq"
        exit 1
    fi
    
    if ! command -v yq &>/dev/null; then
        echo "❌ Install yq: mise install yq"
        exit 1
    fi
    
    mkdir -p "$HOME/.config/tabby"
}

# Pull hosts from gist → Update Tabby
pull() {
    echo "📥 Syncing from gist to Tabby..."
    
    # Get hosts from gist
    gh gist view "$GIST_ID" > "$HOSTS_JSON"
    
    # Create/update Tabby config
    if [ ! -f "$TABBY_CONFIG" ]; then
        create_base_config
    fi
    
    # Update SSH connections in Tabby config
    update_tabby_connections
    
    echo "✅ Tabby updated with $(jq '.hosts | length' "$HOSTS_JSON") hosts"
}

# Push Tabby hosts → Gist
push() {
    echo "📤 Syncing from Tabby to gist..."
    
    if [ ! -f "$TABBY_CONFIG" ]; then
        echo "❌ No Tabby config found"
        exit 1
    fi
    
    # Extract hosts from Tabby
    extract_tabby_hosts
    
    # Push to gist
    gh gist edit "$GIST_ID" "$HOSTS_JSON"
    
    echo "✅ Pushed $(jq '.hosts | length' "$HOSTS_JSON") hosts to gist"
}

# Generate SSH config from current hosts
ssh_config() {
    echo "🔧 Generating SSH config..."
    
    if [ ! -f "$HOSTS_JSON" ]; then
        echo "❌ No hosts file. Run 'pull' first."
        exit 1
    fi
    
    cat > ~/.ssh/config << 'EOF'
# Generated from Tabby sync
# Last update: $(date)

Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3

EOF
    
    jq -r '.hosts[]? | 
        "Host \(.alias)\n" +
        "  HostName \(.hostname)\n" +
        "  User \(.user)\n" +
        "  Port \(.port)\n" +
        (if .identity_file then "  IdentityFile ~/.ssh/\(.identity_file)\n" else "" end) +
        "\n"' "$HOSTS_JSON" >> ~/.ssh/config
    
    chmod 600 ~/.ssh/config
    echo "✅ SSH config updated"
}

# Create base Tabby config
create_base_config() {
    cat > "$TABBY_CONFIG" << 'EOF'
version: 3
hotkeys:
  new-tab: [Ctrl-Shift-T]
  split-right: [Ctrl-Shift-D]
  split-down: [Ctrl-D]
terminal:
  fontSize: 14
  colorScheme:
    name: Material Dark
ssh:
  connections: []
EOF
}

# Update Tabby SSH connections
update_tabby_connections() {
    # Remove existing SSH connections
    yq eval 'del(.ssh.connections[])' -i "$TABBY_CONFIG"
    
    # Add each host as Tabby connection
    jq -r '.hosts[]? | @base64' "$HOSTS_JSON" | while read -r host; do
        local decoded=$(echo "$host" | base64 -d)
        local name=$(echo "$decoded" | jq -r '.alias')
        local hostname=$(echo "$decoded" | jq -r '.hostname')
        local user=$(echo "$decoded" | jq -r '.user // "root"')
        local port=$(echo "$decoded" | jq -r '.port // 22')
        
        # Add to Tabby config
        yq eval ".ssh.connections += [{
            \"type\": \"ssh\",
            \"name\": \"$name\",
            \"group\": \"Synced\",
            \"options\": {
                \"host\": \"$hostname\",
                \"port\": $port,
                \"user\": \"$user\",
                \"algorithms\": {
                    \"serverHostKey\": [\"ssh-rsa\", \"ssh-ed25519\"]
                }
            }
        }]" -i "$TABBY_CONFIG"
    done
}

# Extract hosts from Tabby config
extract_tabby_hosts() {
    yq eval -o=json '.ssh.connections[]?' "$TABBY_CONFIG" | jq -s '{
        version: "1.0",
        updated: now | strftime("%Y-%m-%d %H:%M:%S"),
        hosts: map({
            alias: .name,
            hostname: .options.host,
            user: .options.user,
            port: .options.port
        })
    }' > "$HOSTS_JSON"
}

# Show current hosts
list() {
    if [ -f "$HOSTS_JSON" ]; then
        echo "📋 Current hosts:"
        jq -r '.hosts[] | "  \(.alias) → \(.user)@\(.hostname):\(.port)"' "$HOSTS_JSON"
    else
        echo "❌ No hosts found. Run 'pull' first."
    fi
}

# Usage
usage() {
    cat << EOF
🔄 Simple Tabby Sync

Commands:
  pull      Get hosts from gist → Update Tabby
  push      Save Tabby hosts → Update gist  
  ssh       Generate SSH config from hosts
  list      Show current hosts
  
Examples:
  tabby-simple-sync pull     # Get latest hosts
  tabby-simple-sync push     # Save current hosts
  tabby-simple-sync ssh      # Update SSH config
EOF
}

# Main
check_setup

case "${1:-help}" in
    pull)
        pull
        ssh_config
        ;;
    push)
        push
        ssh_config
        ;;
    ssh)
        ssh_config
        ;;
    list)
        list
        ;;
    *)
        usage
        ;;
esac