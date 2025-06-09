#!/bin/bash

# Tabby Gist Sync - Complete sync solution for Tabby terminal
# Uses your existing gist infrastructure

set -e

# Configuration
TABBY_GIST_ID="${TABBY_GIST_ID:-$UNIFIED_HOSTS_GIST_ID}"
TABBY_CONFIG_DIR="${TABBY_CONFIG_DIR:-$HOME/.config/tabby}"
TABBY_CONFIG="$TABBY_CONFIG_DIR/config.yaml"
HOSTS_JSON="$HOME/.tabby-hosts.json"

# Ensure directories exist
mkdir -p "$TABBY_CONFIG_DIR"

# Check dependencies
check_deps() {
    local missing=()
    
    command -v jq &>/dev/null || missing+=("jq")
    command -v yq &>/dev/null || missing+=("yq")
    command -v gh &>/dev/null || missing+=("gh")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ Missing dependencies: ${missing[*]}"
        echo "Install with: mise install jq yq gh"
        exit 1
    fi
    
    if [ -z "$TABBY_GIST_ID" ]; then
        echo "❌ TABBY_GIST_ID not set in ~/.env_tokens"
        exit 1
    fi
}

# Initialize Tabby config
init_tabby_config() {
    if [ ! -f "$TABBY_CONFIG" ]; then
        echo "🔧 Creating initial Tabby config..."
        cat > "$TABBY_CONFIG" << 'EOF'
version: 3
hotkeys:
  new-tab:
    - Ctrl-Shift-T
  split-right:
    - Ctrl-Shift-D
  split-down:
    - Ctrl-D
  close-pane:
    - Ctrl-W
terminal:
  fontSize: 14
  fontFamily: "MesloLGS NF, Consolas, monospace"
  environment: {}
  shell: default
  profile: local
  customShell: {}
  colorScheme:
    name: Material Dark
    foreground: '#eceff1'
    background: '#263238'
    cursor: '#ffcc00'
ssh:
  connections: []
pluginBlacklist: []
clickableLinks:
  modifier: ctrl
EOF
    fi
}

# Pull hosts from gist
pull_from_gist() {
    echo "📥 Pulling hosts from gist..."
    
    gh gist view "$TABBY_GIST_ID" > "$HOSTS_JSON.tmp" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        mv "$HOSTS_JSON.tmp" "$HOSTS_JSON"
        echo "✅ Hosts pulled from gist"
    else
        echo "❌ Failed to pull from gist"
        exit 1
    fi
}

# Convert JSON hosts to Tabby YAML format
update_tabby_config() {
    echo "🔄 Updating Tabby config..."
    
    # Backup current config
    cp "$TABBY_CONFIG" "$TABBY_CONFIG.bak"
    
    # Extract non-SSH parts of config
    yq eval 'del(.ssh.connections)' "$TABBY_CONFIG" > "$TABBY_CONFIG.tmp"
    
    # Generate SSH connections from JSON
    echo "ssh:" >> "$TABBY_CONFIG.tmp"
    echo "  connections:" >> "$TABBY_CONFIG.tmp"
    
    # Convert each host
    jq -r '.hosts[]? | 
        "  - type: ssh\n" +
        "    name: \"\(.alias)\"\n" +
        "    group: \"\(.tags[0] // "imported")\"\n" +
        "    options:\n" +
        "      host: \"\(.hostname)\"\n" +
        "      port: \(.port // 22)\n" +
        "      user: \"\(.user // "root")\"\n" +
        (if .identity_file then "      privateKey: \"~/.ssh/\(.identity_file)\"\n" else "" end) +
        (if .proxy_jump then "      jumpHost: \"\(.proxy_jump)\"\n" else "" end) +
        (if .forward_agent then "      agentForward: true\n" else "" end) +
        "      algorithms:\n" +
        "        serverHostKey:\n" +
        "          - ssh-rsa\n" +
        "          - ssh-ed25519\n" +
        (if .startup_command then 
            "      scripts:\n" +
            "        - expect: \"\\\\$\"\n" +
            "          send: \"\(.startup_command)\\\\n\"\n" 
        else "" end)' \
        "$HOSTS_JSON" >> "$TABBY_CONFIG.tmp" 2>/dev/null || true
    
    # Move temp to actual config
    mv "$TABBY_CONFIG.tmp" "$TABBY_CONFIG"
    
    echo "✅ Tabby config updated"
}

# Extract hosts from Tabby config to JSON
extract_tabby_hosts() {
    echo "📤 Extracting hosts from Tabby..."
    
    # Convert YAML to JSON and extract SSH connections
    yq eval -o=json '.ssh.connections[]?' "$TABBY_CONFIG" | jq -s '
        {
            version: "1.0",
            updated: now | strftime("%Y-%m-%d %H:%M:%S"),
            source: "tabby",
            hosts: map({
                alias: .name,
                hostname: .options.host,
                user: (.options.user // "root"),
                port: (.options.port // 22),
                identity_file: (.options.privateKey | gsub("^~/.ssh/"; "")),
                startup_command: (if .options.scripts then .options.scripts[0].send | gsub("\\\\n$"; "") else null end),
                proxy_jump: .options.jumpHost,
                forward_agent: .options.agentForward,
                tags: [(.group // "default")]
            })
        }' > "$HOSTS_JSON"
    
    echo "✅ Extracted $(jq '.hosts | length' "$HOSTS_JSON") hosts"
}

# Push to gist
push_to_gist() {
    echo "📤 Pushing hosts to gist..."
    
    gh gist edit "$TABBY_GIST_ID" "$HOSTS_JSON"
    
    echo "✅ Pushed to gist: $TABBY_GIST_ID"
}

# Generate SSH config from hosts
generate_ssh_config() {
    echo "🔧 Generating SSH config..."
    
    cat > ~/.ssh/config.tabby << 'EOF'
# Generated from Tabby hosts
# Last sync: $(date)

EOF
    
    jq -r '.hosts[]? | 
        "Host \(.alias)\n" +
        "  HostName \(.hostname)\n" +
        "  User \(.user)\n" +
        "  Port \(.port)\n" +
        (if .identity_file then "  IdentityFile ~/.ssh/\(.identity_file)\n" else "" end) +
        (if .proxy_jump then "  ProxyJump \(.proxy_jump)\n" else "" end) +
        (if .forward_agent then "  ForwardAgent yes\n" else "" end) +
        "\n"' "$HOSTS_JSON" >> ~/.ssh/config.tabby
    
    echo "✅ SSH config generated at ~/.ssh/config.tabby"
}

# Setup Tabby plugin config
setup_plugin_config() {
    echo "📦 Setting up Tabby cloud sync plugin..."
    
    cat > "$TABBY_CONFIG_DIR/cloud-sync-settings.json" << EOF
{
    "provider": "github-gist",
    "gistId": "$TABBY_GIST_ID",
    "githubToken": "\${GITHUB_TOKEN}",
    "syncInterval": 300,
    "autoSync": true,
    "syncOnStartup": true,
    "syncOnChange": true,
    "encryption": {
        "enabled": false
    }
}
EOF
    
    echo "✅ Plugin config created"
    echo "   Make sure to set GITHUB_TOKEN in Tabby settings"
}

# Interactive sync menu
interactive_menu() {
    echo "
🔄 Tabby Gist Sync Manager

1) Pull from gist → Update Tabby
2) Push from Tabby → Update gist  
3) Setup plugin config
4) Generate SSH config
5) Show current hosts
6) Exit

"
    read -p "Choose option: " choice
    
    case $choice in
        1)
            pull_from_gist
            update_tabby_config
            generate_ssh_config
            ;;
        2)
            extract_tabby_hosts
            push_to_gist
            generate_ssh_config
            ;;
        3)
            setup_plugin_config
            ;;
        4)
            generate_ssh_config
            ;;
        5)
            if [ -f "$HOSTS_JSON" ]; then
                jq -r '.hosts[] | "\(.alias) → \(.user)@\(.hostname):\(.port)"' "$HOSTS_JSON"
            else
                echo "No hosts file found. Pull from gist first."
            fi
            ;;
        6)
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac
}

# Main command handler
main() {
    check_deps
    init_tabby_config
    
    case "${1:-menu}" in
        pull)
            pull_from_gist
            update_tabby_config
            generate_ssh_config
            ;;
        push)
            extract_tabby_hosts
            push_to_gist
            ;;
        sync)
            # Bidirectional sync - pull then push
            pull_from_gist
            update_tabby_config
            extract_tabby_hosts
            push_to_gist
            generate_ssh_config
            ;;
        setup)
            setup_plugin_config
            ;;
        menu|*)
            interactive_menu
            ;;
    esac
}

# Show usage if --help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
Tabby Gist Sync - Sync Tabby SSH hosts with GitHub Gist

Usage: tabby-gist-sync [command]

Commands:
  pull    Pull from gist and update Tabby
  push    Push Tabby hosts to gist
  sync    Bidirectional sync
  setup   Setup Tabby plugin config
  menu    Interactive menu (default)

Environment:
  TABBY_GIST_ID - Gist ID for hosts (uses UNIFIED_HOSTS_GIST_ID if not set)
  
Example:
  tabby-gist-sync pull    # Get latest from gist
  tabby-gist-sync push    # Save current to gist
EOF
    exit 0
fi

main "$@"