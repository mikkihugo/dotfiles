#!/bin/bash

# Unified host synchronization for Warp, Termius, and SSH config
# Maintains a single source of truth in private gist

set -e

HOSTS_GIST_ID="${UNIFIED_HOSTS_GIST_ID:-$SSH_HOSTS_GIST_ID}"
HOSTS_FILE="$HOME/.ssh/unified-hosts.json"
SSH_CONFIG="$HOME/.ssh/config"
WARP_HOSTS="$HOME/.warp/ssh_config.yml"

# Ensure directories exist
mkdir -p "$HOME/.ssh" "$HOME/.warp"

# Pull latest hosts from gist
pull_hosts() {
    echo "📥 Pulling hosts from gist..."
    
    if [ -z "$HOSTS_GIST_ID" ]; then
        echo "❌ Error: UNIFIED_HOSTS_GIST_ID not set in ~/.env_tokens"
        exit 1
    fi
    
    gh gist view "$HOSTS_GIST_ID" > "$HOSTS_FILE.tmp" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
        echo "✅ Hosts pulled successfully"
    else
        echo "❌ Failed to pull hosts"
        exit 1
    fi
}

# Generate SSH config
generate_ssh_config() {
    echo "🔧 Generating SSH config..."
    
    # Backup existing
    [ -f "$SSH_CONFIG" ] && cp "$SSH_CONFIG" "$SSH_CONFIG.bak"
    
    cat > "$SSH_CONFIG.new" << 'EOF'
# Auto-generated SSH config - DO NOT EDIT DIRECTLY
# Edit unified-hosts.json and run: unified-hosts-sync
# Generated: $(date)

# Global defaults
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    Compression yes
    
EOF
    
    # Parse JSON and generate config
    jq -r '.hosts[] | 
        "Host \(.alias)\n" +
        "  HostName \(.hostname)\n" +
        "  User \(.user // "root")\n" +
        "  Port \(.port // 22)\n" +
        (if .identity_file then "  IdentityFile ~/.ssh/\(.identity_file)\n" else "" end) +
        (if .forward_agent then "  ForwardAgent yes\n" else "" end) +
        (if .proxy_jump then "  ProxyJump \(.proxy_jump)\n" else "" end) +
        (if .local_forward then "  LocalForward \(.local_forward)\n" else "" end) +
        (if .startup_command then "  # Startup: \(.startup_command)\n" else "" end) +
        "\n"' "$HOSTS_FILE" >> "$SSH_CONFIG.new"
    
    # Add any custom config
    if [ -f "$SSH_CONFIG.custom" ]; then
        echo "# Custom configuration" >> "$SSH_CONFIG.new"
        cat "$SSH_CONFIG.custom" >> "$SSH_CONFIG.new"
    fi
    
    mv "$SSH_CONFIG.new" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "✅ SSH config generated"
}

# Generate Warp hosts
generate_warp_config() {
    echo "🚀 Generating Warp config..."
    
    cat > "$WARP_HOSTS" << 'EOF'
# Warp SSH configuration
# Auto-generated from unified hosts
name: SSH Hosts
hosts:
EOF
    
    jq -r '.hosts[] | 
        "  - name: \(.alias)\n" +
        "    hostname: \(.hostname)\n" +
        "    user: \(.user // "root")\n" +
        "    port: \(.port // 22)\n" +
        (if .tags then "    tags: [\(.tags | join(", "))]" else "" end) +
        (if .startup_command then "    startup_command: \(.startup_command)" else "    startup_command: tmux attach || tmux new -s main" end)' \
        "$HOSTS_FILE" >> "$WARP_HOSTS"
    
    echo "✅ Warp config generated"
}

# Export Termius format
export_termius_format() {
    echo "📱 Generating Termius import file..."
    
    local termius_file="$HOME/.termius-import.json"
    
    jq '{
        version: "1.0",
        hosts: [.hosts[] | {
            label: .alias,
            address: .hostname,
            username: (.user // "root"),
            port: (.port // 22),
            ssh_key: (if .identity_file then "~/.ssh/\(.identity_file)" else null end),
            startup_script: (.startup_command // "tmux attach || tmux new -s main"),
            terminal_type: "xterm-256color",
            tags: (.tags // [])
        }]
    }' "$HOSTS_FILE" > "$termius_file"
    
    echo "✅ Termius import file: $termius_file"
    echo "   Import with: termius import --input $termius_file"
}

# Add new host
add_host() {
    local alias="$1"
    local hostname="$2"
    local user="${3:-root}"
    local port="${4:-22}"
    
    if [ -z "$alias" ] || [ -z "$hostname" ]; then
        echo "Usage: unified-hosts-sync add <alias> <hostname> [user] [port]"
        exit 1
    fi
    
    # Pull latest
    pull_hosts
    
    # Add host
    jq --arg alias "$alias" \
       --arg hostname "$hostname" \
       --arg user "$user" \
       --arg port "$port" \
       '.hosts += [{
           alias: $alias,
           hostname: $hostname,
           user: $user,
           port: ($port | tonumber),
           tags: ["manual"],
           startup_command: "tmux attach || tmux new -s main"
       }]' "$HOSTS_FILE" > "$HOSTS_FILE.tmp"
    
    mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
    
    # Push back
    push_hosts
    
    echo "✅ Host $alias added"
}

# Push hosts to gist
push_hosts() {
    echo "📤 Pushing hosts to gist..."
    
    # Validate JSON
    if ! jq empty "$HOSTS_FILE" 2>/dev/null; then
        echo "❌ Invalid JSON in hosts file"
        exit 1
    fi
    
    gh gist edit "$HOSTS_GIST_ID" "$HOSTS_FILE"
    echo "✅ Hosts pushed to gist"
}

# Interactive host selector with fzf
select_host() {
    if ! command -v fzf &>/dev/null; then
        echo "❌ fzf not found. Install with: mise install fzf"
        exit 1
    fi
    
    local selected=$(jq -r '.hosts[] | "\(.alias)|\(.hostname)|\(.user // "root")|\(.tags // [] | join(","))"' "$HOSTS_FILE" | \
        column -t -s'|' | \
        fzf --header="Select host to connect" \
            --preview='echo "Connecting to: {1}"' \
            --height=50% \
            --reverse)
    
    if [ ! -z "$selected" ]; then
        local host=$(echo "$selected" | awk '{print $1}')
        echo "🔗 Connecting to $host..."
        ssh "$host"
    fi
}

# Sync all
sync_all() {
    pull_hosts
    generate_ssh_config
    generate_warp_config
    export_termius_format
    
    echo "
✅ All configurations synced!

📁 Files generated:
  - SSH config: $SSH_CONFIG
  - Warp hosts: $WARP_HOSTS  
  - Termius import: ~/.termius-import.json

🚀 Next steps:
  - SSH: Your SSH config is ready
  - Warp: Restart Warp to load new hosts
  - Termius: Run 'termius import --input ~/.termius-import.json'
"
}

# Show usage
usage() {
    cat << EOF
🔄 Unified Hosts Sync Manager

Synchronizes SSH hosts across Warp, Termius, and SSH config.

Usage: unified-hosts-sync <command> [options]

Commands:
  sync       Pull from gist and regenerate all configs (default)
  add        Add new host: add <alias> <hostname> [user] [port]
  edit       Edit hosts file directly in gist
  push       Push local changes to gist
  pull       Pull latest from gist
  connect    Interactive host selector with fzf
  
Environment:
  UNIFIED_HOSTS_GIST_ID - Gist ID for hosts storage
  
Examples:
  unified-hosts-sync                    # Sync everything
  unified-hosts-sync add prod server.com ubuntu 2222
  unified-hosts-sync connect            # Interactive SSH
  
Host file format (JSON):
{
  "hosts": [{
    "alias": "prod",
    "hostname": "server.com",
    "user": "ubuntu",
    "port": 22,
    "identity_file": "id_rsa",
    "startup_command": "tmux attach || tmux new",
    "tags": ["production", "web"],
    "proxy_jump": "bastion",
    "forward_agent": true
  }]
}
EOF
}

# Main
case "${1:-sync}" in
    sync)
        sync_all
        ;;
    add)
        shift
        add_host "$@"
        sync_all
        ;;
    edit)
        gh gist edit "$HOSTS_GIST_ID"
        ;;
    push)
        push_hosts
        ;;
    pull)
        pull_hosts
        ;;
    connect)
        pull_hosts
        select_host
        ;;
    *)
        usage
        ;;
esac