#!/bin/bash

# Direct sync with Termius cloud database
# Keeps SSH config in sync with Termius hosts automatically

set -e

# Check if termius CLI is logged in
check_termius_auth() {
    if ! termius account 2>/dev/null | grep -q "Email:"; then
        echo "❌ Not logged into Termius"
        echo "Run: termius login"
        exit 1
    fi
}

# Auto-sync from Termius to SSH config AND Warp
termius_to_ssh_and_warp() {
    echo "📥 Syncing from Termius cloud to SSH config and Warp..."
    
    # Create temp file
    local temp_file="/tmp/termius-export-$$.json"
    
    # Export all Termius data
    termius export --output "$temp_file"
    
    # Backup existing SSH config
    [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak
    
    # Generate new SSH config
    cat > ~/.ssh/config << 'EOF'
# Auto-generated from Termius cloud
# DO NOT EDIT - Changes will be overwritten
# Last sync: $(date)
# To edit hosts, use Termius app or 'termius host add'

Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
EOF
    
    # Process hosts
    echo "# Individual hosts" >> ~/.ssh/config
    jq -r '.hosts[]? | 
        "\nHost \(.label // .address)\n" +
        "  HostName \(.address)\n" +
        "  User \(.username // "root")\n" +
        "  Port \(.port // 22)\n" +
        (if .ssh_key then "  IdentityFile \(.ssh_key)\n" else "" end) +
        (if .startup_script then "  # Startup: \(.startup_script)\n" else "" end)' \
        "$temp_file" >> ~/.ssh/config 2>/dev/null || true
    
    # Process groups and their hosts
    echo -e "\n# Hosts from groups" >> ~/.ssh/config
    jq -r '.groups[]? as $group | $group.hosts[]? | 
        "\nHost \(.label // .address)\n" +
        "  HostName \(.address)\n" +
        "  User \(.username // "root")\n" +
        "  Port \(.port // 22)\n" +
        "  # Group: \($group.label)\n"' \
        "$temp_file" >> ~/.ssh/config 2>/dev/null || true
    
    # Set permissions
    chmod 600 ~/.ssh/config
    
    # Count hosts
    local host_count=$(jq -r '(.hosts[]?.label // .hosts[]?.address // empty)' "$temp_file" 2>/dev/null | wc -l)
    
    echo "✅ Synced $host_count hosts from Termius to ~/.ssh/config"
    
    # Also generate Warp config
    generate_warp_config "$temp_file"
    
    # Cleanup
    rm -f "$temp_file"
}

# Generate Warp configuration
generate_warp_config() {
    local termius_file="$1"
    local warp_dir="$HOME/.warp"
    
    echo "🚀 Generating Warp configuration..."
    
    # Create Warp directory
    mkdir -p "$warp_dir"
    
    # Generate Warp SSH hosts file
    cat > "$warp_dir/ssh_hosts.yml" << 'EOF'
# Auto-generated from Termius cloud
# DO NOT EDIT - Changes will be overwritten
# Last sync: $(date)

name: Termius Hosts
version: 1.0
hosts:
EOF
    
    # Process hosts for Warp
    jq -r '.hosts[]? | 
        "  - name: \"\(.label // .address)\"\n" +
        "    hostname: \(.address)\n" +
        "    username: \(.username // "root")\n" +
        "    port: \(.port // 22)\n" +
        (if .startup_script then "    startup_command: \"\(.startup_script)\"\n" else "    startup_command: \"tmux attach || tmux new -s main\"\n" end) +
        (if .ssh_key then "    identity_file: \"\(.ssh_key)\"\n" else "" end) +
        "    tags: [\"termius-sync\"]\n"' \
        "$termius_file" >> "$warp_dir/ssh_hosts.yml" 2>/dev/null || true
    
    # Generate Warp workflows
    cat > "$warp_dir/termius_workflows.yml" << 'EOF'
# Warp workflows from Termius
name: Termius Workflows
workflows:
  - name: SSH with tmux
    command: ssh {{host}} -t "tmux attach || tmux new -s main"
    description: Connect via Termius host
    placeholders:
      - name: host
        description: Termius hostname
        
  - name: Quick connect
    command: ~/.dotfiles/.scripts/termius-cloud-sync.sh connect
    description: Use fzf to select Termius host
EOF
    
    echo "✅ Warp configuration generated at $warp_dir/"
}

# Watch for Termius changes and auto-sync
watch_and_sync() {
    echo "👁️  Watching Termius for changes..."
    echo "Press Ctrl+C to stop"
    
    # Initial sync
    termius_to_ssh
    
    # Create state file
    local state_file="$HOME/.termius-sync-state"
    termius hosts list --format json > "$state_file"
    
    while true; do
        sleep 30  # Check every 30 seconds
        
        # Get current state
        local current_state="/tmp/termius-current-state-$$.json"
        termius hosts list --format json > "$current_state" 2>/dev/null || continue
        
        # Compare with previous state
        if ! cmp -s "$state_file" "$current_state"; then
            echo "🔄 Changes detected, syncing..."
            termius_to_ssh_and_warp
            cp "$current_state" "$state_file"
        fi
        
        rm -f "$current_state"
    done
}

# Add host via Termius and sync
add_host() {
    local label="$1"
    local address="$2"
    local user="${3:-root}"
    local port="${4:-22}"
    
    if [ -z "$label" ] || [ -z "$address" ]; then
        echo "Usage: termius-cloud-sync add <label> <address> [user] [port]"
        exit 1
    fi
    
    echo "➕ Adding host to Termius..."
    
    # Add to Termius
    termius host create \
        --label "$label" \
        --address "$address" \
        --username "$user" \
        --port "$port" \
        --startup-script "tmux attach || tmux new -s main"
    
    # Sync to SSH config and Warp
    termius_to_ssh_and_warp
    
    echo "✅ Host added and synced"
}

# Quick connect using fzf
quick_connect() {
    if ! command -v fzf &>/dev/null; then
        echo "fzf not found. Install with: mise install fzf"
        exit 1
    fi
    
    # Get hosts from Termius
    local selected=$(termius hosts list --format table | tail -n +2 | \
        fzf --header="Select Termius host" \
            --preview='echo "Connecting to: {2}"' \
            --height=50% \
            --reverse | \
        awk '{print $2}')
    
    if [ ! -z "$selected" ]; then
        echo "🔗 Connecting to $selected..."
        termius connect "$selected"
    fi
}

# Setup auto-sync on login
setup_auto_sync() {
    local bashrc_addon='
# Auto-sync Termius hosts on login
if command -v termius &>/dev/null && termius account 2>/dev/null | grep -q "Email:"; then
    # Check if sync needed (every 6 hours)
    SYNC_FILE="$HOME/.termius-last-sync"
    if [ ! -f "$SYNC_FILE" ] || [ $(find "$SYNC_FILE" -mmin +360 2>/dev/null | wc -l) -gt 0 ]; then
        echo "🔄 Syncing Termius hosts..."
        ~/.dotfiles/.scripts/termius-cloud-sync.sh sync
        touch "$SYNC_FILE"
    fi
fi'
    
    echo "$bashrc_addon" >> ~/.bashrc
    echo "✅ Auto-sync added to ~/.bashrc"
}

# Main menu
usage() {
    cat << EOF
☁️  Termius Cloud Sync

Automatically syncs Termius cloud hosts to SSH config.

Usage: termius-cloud-sync <command>

Commands:
  sync       Sync Termius hosts to ~/.ssh/config (default)
  watch      Watch for changes and auto-sync
  add        Add new host: add <label> <address> [user] [port]
  connect    Quick connect with fzf
  setup      Add auto-sync to bashrc
  
Examples:
  termius-cloud-sync                    # One-time sync
  termius-cloud-sync watch              # Keep syncing
  termius-cloud-sync add prod server.com ubuntu
  
Note: Requires 'termius login' first
EOF
}

# Check auth first
check_termius_auth

# Main command handler
case "${1:-sync}" in
    sync)
        termius_to_ssh_and_warp
        ;;
    watch)
        watch_and_sync
        ;;
    add)
        shift
        add_host "$@"
        ;;
    connect)
        quick_connect
        ;;
    setup)
        setup_auto_sync
        ;;
    *)
        usage
        ;;
esac