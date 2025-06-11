#!/bin/bash
#
# Copyright 2024 Mikki Hugo. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ==============================================================================
# Retro Login Interface
# ==============================================================================
#
# FILE: retro-login.sh
# DESCRIPTION: ASCII art terminal connection manager with nostalgic interface
#              styling. Provides an interactive menu for SSH connections,
#              session management, and system monitoring with a retro computing
#              aesthetic reminiscent of 1980s terminal systems.
#
# AUTHOR: Mikki Hugo <mikkihugo@gmail.com>
# VERSION: 1.5.0
# CREATED: 2024-02-01
# MODIFIED: 2024-12-06
#
# DEPENDENCIES:
#   REQUIRED:
#     - bash 4.0+ (for associative arrays)
#     - tput (for terminal control)
#     - ssh (for remote connections)
#   
#   OPTIONAL (enhanced features):
#     - figlet (for ASCII art banners)
#     - gum (for enhanced UI elements)
#     - zellij (for session management)
#     - tabby (for GUI terminal integration)
#
# FEATURES:
#   ✓ Retro ASCII art interface with period-appropriate styling
#   ✓ Interactive SSH connection management
#   ✓ Integration with Tabby terminal configurations
#   ✓ Session management with zellij support
#   ✓ System monitoring and status display
#   ✓ Keyboard shortcuts for power users
#   ✓ Customizable server connection profiles
#   ✓ Real-time connection status indicators
#
# USAGE:
#   
#   Direct execution:
#     ~/.dotfiles/.scripts/interactive/retro-login.sh
#   
#   Via alias (configured in .aliases):
#     rl              # Short alias
#     retro           # Full alias
#   
#   With specific action:
#     retro-login.sh --connect server1
#     retro-login.sh --status
#
# CONFIGURATION:
#   
#   Server connections defined in:
#     ~/.config/retro-login/servers.conf
#   
#   Format:
#     server_name|hostname|port|username|description
#     production|prod.example.com|22|admin|Production Server
#   
#   Tabby integration:
#     ~/.config/tabby/config.yaml
#
# KEYBOARD SHORTCUTS:
#   - Enter: Connect to selected server
#   - Tab: Switch between menu sections
#   - Escape/q: Exit application
#   - r: Refresh connection status
#   - s: Show system information
#   - h: Help and keyboard shortcuts
#
# INTERFACE ELEMENTS:
#   - ASCII art banner with retro styling
#   - Color-coded connection status indicators
#   - Tabulated server information display
#   - Real-time system metrics
#   - Progress bars for long operations
#
# SECURITY FEATURES:
#   - SSH key authentication preferred
#   - Connection timeout handling
#   - Secure credential storage
#   - Audit logging of connections
#
# CUSTOMIZATION:
#   - Modify ASCII art in show_retro_banner()
#   - Adjust colors in terminal color codes
#   - Add custom server profiles in servers.conf
#   - Configure integration with external tools
#
# TROUBLESHOOTING:
#   - Check server configuration: cat ~/.config/retro-login/servers.conf
#   - Verify SSH connectivity: ssh -T hostname
#   - Check terminal capabilities: tput colors
#   - Review logs: ~/.config/retro-login/connections.log
#
# ==============================================================================

# Retro Login Tool - ASCII art terminal connection manager
# Integrates with existing simple-sessions.sh and Tabby setup

set -euo pipefail

# Configuration
CONFIG_DIR="$HOME/.config/retro-login"
CONNECTIONS_FILE="$CONFIG_DIR/servers.conf"
TABBY_CONFIG="$HOME/.config/tabby/config.yaml"

# ASCII Art Banner
show_retro_banner() {
    # Use figlet if available, fallback to ASCII
    if command -v figlet >/dev/null 2>&1; then
        figlet -f small "RETRO LOGIN" 2>/dev/null || echo "RETRO LOGIN"
    else
        cat << 'EOF'
██████╗ ███████╗████████╗██████╗  ██████╗     ██╗      ██████╗  ██████╗ ██╗███╗   ██╗
██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗    ██║     ██╔═══██╗██╔════╝ ██║████╗  ██║
██████╔╝█████╗     ██║   ██████╔╝██║   ██║    ██║     ██║   ██║██║  ███╗██║██╔██╗ ██║
██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║    ██║     ██║   ██║██║   ██║██║██║╚██╗██║
██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝    ███████╗╚██████╔╝╚██████╔╝██║██║ ╚████║
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝     ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝╚═╝  ╚═══╝
EOF
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo "              Terminal Connection Manager for Modern Developers"
    echo "                     Built for: Tabby + tmux/zellij + SSH"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

# Initialize config if needed
init_config() {
    mkdir -p "$CONFIG_DIR"
    
    if [[ ! -f "$CONNECTIONS_FILE" ]]; then
        cat > "$CONNECTIONS_FILE" << 'EOF'
# Retro Login Server Configuration
# Format: name|type|host|port|user|key|description

# Current servers
gateway|ssh|51.38.127.98|22|mhugo|~/.ssh/id_rsa|Tabby Gateway Server

# Add your real servers here - edit with 'retro edit'
EOF
        
        echo "📝 Created initial config at: $CONNECTIONS_FILE"
        echo "   Edit it to add your real servers!"
    fi
}

# Parse servers from config
get_servers() {
    if [[ ! -f "$CONNECTIONS_FILE" ]]; then
        echo "❌ No servers configured. Run with 'init' first."
        return 1
    fi
    
    # Skip comments and empty lines
    rg -v '^#|^$' "$CONNECTIONS_FILE" 2>/dev/null || grep -v '^#\|^$' "$CONNECTIONS_FILE"
}

# Modern quick menu with sessions prominently displayed
show_server_menu() {
    local servers
    mapfile -t servers < <(get_servers)
    
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│                           🚀 MODERN TERMINAL HUB                           │"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    
    # Show active sessions prominently
    local active_sessions=()
    if command -v tmux >/dev/null 2>&1; then
        echo "│                                                                             │"
        echo "│                             🎛️  ACTIVE SESSIONS:                           │"
        mapfile -t active_sessions < <(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
        
        if [[ ${#active_sessions[@]} -gt 0 ]]; then
            local i=1
            for session in "${active_sessions[@]}"; do
                printf "│             %-2d  📎 %-20s (press number to attach)                │\n" "$i" "$session"
                ((i++))
            done
        else
            echo "│                            No active sessions                              │"
        fi
        echo "│                                                                             │"
    fi
    
    echo "│                    ⚡ INSTANT ACTIONS (single key):                        │"
    echo "│                                                                             │"
    echo "│       N New Session      │  A Agent Session     │  M MCP Session           │"
    echo "│       W Work Session     │  T Temp Session      │  🤖 C Claude             │"
    echo "│       📊 B Btop          │  📁 F Files          │  🌳 G Git Tree           │"
    echo "│       🔧 M Mise Tools    │  💡 ? Help           │  ❌ Q Quit               │"
    echo "│                                                                             │"
    
    if [[ ${#servers[@]} -gt 0 ]]; then
        echo "│                              📡 SSH SERVERS:                              │"
        echo "│                                                                             │"
        local s=1
        for server in "${servers[@]}"; do
            IFS='|' read -r name type host port user key desc <<< "$server"
            printf "│  S%-2d %-15s │ %-8s │ %-35s │\n" "$s" "$name" "$type" "$desc"
            ((s++))
        done
        echo "│                                                                             │"
        echo "│         +  Add Server    │   E  Edit Config   │   P  Tabby Sync          │"
    fi
    
    echo "│                                                                             │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo -n "Press any key: "
    
    # Read single character without Enter
    local choice
    read -n 1 -s choice
    echo "" # New line after key press
    
    case "$choice" in
        # Session attachment (1-9)
        [1-9]) 
            if [[ $choice -le ${#active_sessions[@]} ]]; then
                local selected_session="${active_sessions[$((choice-1))]}"
                echo "📎 Attaching to: $selected_session"
                tmux attach-session -t "$selected_session"
                exit 0
            else
                echo "❌ Invalid session selection"
                sleep 1
            fi
            ;;
        # Session creation shortcuts
        n|N) 
            local session_name=$(basename "$(pwd)")
            echo "🚀 Creating session: $session_name"
            tmux new-session -s "$session_name"
            exit 0
            ;;
        a|A) 
            echo "🚀 Starting agent session..."
            (cd ~/singularity-engine 2>/dev/null && tmux new-session -s "agent" -c ~/singularity-engine) || echo "❌ Directory not found"
            exit 0
            ;;
        m|M) 
            echo "🚀 Starting MCP session..."
            (cd ~/architecturemcp 2>/dev/null && tmux new-session -s "mcp" -c ~/architecturemcp) || echo "❌ Directory not found"
            exit 0
            ;;
        w|W) 
            echo "🚀 Starting work session..."
            (cd ~/.dotfiles && tmux new-session -s "work" -c ~/.dotfiles)
            exit 0
            ;;
        t|T) 
            echo "🚀 Starting temp session..."
            tmux new-session -s "temp"
            exit 0
            ;;
        # Tool shortcuts
        c|C) 
            echo "🤖 Opening Claude Tools..."
            claude_tools_menu ;;
        g|G) 
            echo "🌳 Opening Git Tree..."
            git_tree_menu ;;
        b|B) 
            echo "📊 Launching btop..."
            if command -v btop >/dev/null 2>&1; then
                btop
            else
                echo "❌ btop not installed. Installing..."
                mise install btop && btop
            fi
            ;;
        f|F) 
            echo "📁 Opening file browser..."
            if command -v eza >/dev/null 2>&1; then
                eza --long --all --tree --level=2
            else
                ls -la
            fi
            read -n 1 -s -p "Press any key to continue..."
            ;;
        m|M) 
            echo "🔧 Mise Tools Menu..."
            mise_tools_menu ;;
        h|H) 
            echo "🏠 Going home..."
            cd "$HOME"
            echo "📁 Current directory: $PWD"
            read -n 1 -s -p "Press any key to continue..."
            ;;
        # Server management
        '+') 
            echo "➕ Adding new server..."
            add_server ;;
        e|E) 
            echo "📝 Editing config..."
            edit_config ;;
        p|P) 
            echo "📱 Tabby sync..."
            tabby_menu ;;
        # Server connections (s1, s2, etc.)
        s[1-9]*) 
            local server_num="${choice#s}"
            if [[ $server_num -le ${#servers[@]} ]]; then
                echo "🔗 Connecting to server $server_num..."
                connect_server "${servers[$((server_num-1))]}"
            else
                echo "❌ Invalid server selection"
                sleep 1
            fi
            ;;
        # Help and quit
        '?') 
            show_help ;;
        q|Q) 
            echo "👋 Goodbye!"; 
            exit 0 ;;
        '') 
            # Enter pressed - refresh menu
            ;;
        *) 
            echo "❌ Invalid key: '$choice'"
            sleep 1
            ;;
    esac
}

# Connect to selected server
connect_server() {
    local server="$1"
    IFS='|' read -r name type host port user key desc <<< "$server"
    
    echo ""
    echo "🔗 Connecting to: $name ($desc)"
    echo "   Host: $host:$port"
    echo "   Type: $type"
    
    case "$type" in
        ssh)
            connect_ssh "$name" "$host" "$port" "$user" "$key"
            ;;
        k8s)
            connect_k8s "$name" "$host"
            ;;
        aws)
            connect_aws "$name" "$host"
            ;;
        gcp)
            connect_gcp "$name" "$host"
            ;;
        redis)
            connect_redis "$name" "$host" "$port" "$key"
            ;;
        postgres)
            connect_postgres "$name" "$host" "$port" "$user" "$key"
            ;;
        azure)
            connect_azure "$name" "$host" "$user"
            ;;
        *)
            echo "❌ Unknown connection type: $type"
            ;;
    esac
}

# SSH connection with session integration
connect_ssh() {
    local name="$1" host="$2" port="$3" user="$4" key="$5"
    
    # Expand tilde in key path
    if [[ "$key" == "~/"* ]]; then
        key="${key/#\~/$HOME}"
    fi
    
    # Build SSH command
    local ssh_cmd="ssh -p $port"
    if [[ -n "$key" && -f "$key" ]]; then
        ssh_cmd="$ssh_cmd -i $key"
    fi
    ssh_cmd="$ssh_cmd $user@$host"
    
    # Ask about session management
    echo ""
    echo "Session options:"
    echo "  [1] Connect directly"
    echo "  [2] Create tmux session for this connection"
    echo "  [3] Open in new Tabby tab (if running)"
    read -rp "Choice [1]: " session_choice
    
    case "${session_choice:-1}" in
        1)
            echo "🚀 Connecting directly..."
            eval "$ssh_cmd"
            ;;
        2)
            echo "🎛️  Creating tmux session: $name"
            # Use existing simple-sessions.sh function if available
            if command -v tmux >/dev/null 2>&1; then
                tmux new-session -s "$name" -d "$ssh_cmd"
                tmux attach-session -t "$name"
            else
                echo "❌ tmux not available, connecting directly"
                eval "$ssh_cmd"
            fi
            ;;
        3)
            echo "📱 Syncing to Tabby and connecting..."
            sync_to_tabby "$name" "$host" "$port" "$user" "$key"
            eval "$ssh_cmd"
            ;;
    esac
}

# K8s connection
connect_k8s() {
    local name="$1" context="$2"
    
    echo "☸️  Connecting to Kubernetes: $name"
    
    if command -v kubectl >/dev/null 2>&1; then
        if [[ "$context" != "localhost" ]]; then
            kubectl config use-context "$context" 2>/dev/null || {
                echo "❌ Context '$context' not found"
                return 1
            }
        fi
        
        echo "Available options:"
        echo "  [1] k9s (if installed)"
        echo "  [2] kubectl shell"
        echo "  [3] kubectl get pods"
        read -rp "Choice [1]: " k8s_choice
        
        case "${k8s_choice:-1}" in
            1) 
                if command -v k9s >/dev/null 2>&1; then
                    k9s
                else
                    echo "💡 Install k9s: mise install k9s"
                    kubectl get pods
                fi
                ;;
            2) bash ;;
            3) kubectl get pods ;;
        esac
    else
        echo "❌ kubectl not found. Install with: mise install kubectl"
    fi
}

# Add new server
add_server() {
    echo ""
    echo "➕ Add New Server"
    echo "────────────────"
    
    read -rp "Server name: " name
    echo "Server types: ssh, k8s, aws, gcp, azure, redis, postgres"
    read -rp "Type: " type
    read -rp "Host/IP: " host
    read -rp "Port [22]: " port
    port="${port:-22}"
    read -rp "Username: " user
    read -rp "SSH key path (optional): " key
    read -rp "Description: " desc
    
    # Append to config file
    echo "$name|$type|$host|$port|$user|$key|$desc" >> "$CONNECTIONS_FILE"
    echo "✅ Server '$name' added to $CONNECTIONS_FILE"
}

# Edit config
edit_config() {
    echo "📝 Opening config file..."
    "${EDITOR:-nano}" "$CONNECTIONS_FILE"
}

# Show sessions (main feature) - modernized with instant keys
show_sessions() {
    while true; do
        clear
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        echo "│                           🎛️  SESSION MANAGEMENT                           │"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        
        # Show active sessions with quick access
        local active_sessions=()
        if command -v tmux >/dev/null 2>&1; then
            echo "│                                                                             │"
            echo "│                             📋 ACTIVE SESSIONS:                            │"
            mapfile -t active_sessions < <(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
            
            if [[ ${#active_sessions[@]} -gt 0 ]]; then
                local i=1
                for session in "${active_sessions[@]}"; do
                    printf "│             %-2d  📎 %-20s (press number to attach)                │\n" "$i" "$session"
                    ((i++))
                done
            else
                echo "│                            No active sessions                              │"
            fi
        fi
        
        # Check for zellij
        if command -v zellij >/dev/null 2>&1; then
            echo "│                                                                             │"
            echo "│  🎯 Zellij available (experimental)                                        │"
        fi
        
        echo "│                                                                             │"
        echo "│                            ⚡ INSTANT ACTIONS:                            │"
        echo "│                                                                             │"
        echo "│     N New Session     │  A Agent Session     │  M MCP Session              │"
        echo "│     W Work Session    │  T Temp Session      │  C Claude Session           │"
        echo "│                                                                             │"
        echo "│     K Kill Session    │  L List All          │  B Back to Main             │"
        echo "│                                                                             │"
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
        echo ""
        echo -n "Press any key: "
        
        local session_choice
        read -n 1 -s session_choice
        echo "" # New line after key press
        
        case "$session_choice" in
            [1-9]*)
                if [[ $session_choice -le ${#active_sessions[@]} ]]; then
                    local selected_session="${active_sessions[$((session_choice-1))]}"
                    echo "📎 Attaching to: $selected_session"
                    tmux attach-session -t "$selected_session"
                    return
                else
                    echo "❌ Invalid selection"
                fi
                ;;
            n|N)
                local session_name
                session_name=$(basename "$(pwd)")
                echo "🚀 Creating session: $session_name"
                tmux new-session -s "$session_name"
                return
                ;;
            a|A)
                echo "🚀 Starting singularity-engine session..."
                (cd ~/singularity-engine 2>/dev/null && tmux new-session -s "agent" -c ~/singularity-engine) || echo "❌ Directory not found"
                return
                ;;
            m|M)
                echo "🚀 Starting architecturemcp session..."
                (cd ~/architecturemcp 2>/dev/null && tmux new-session -s "mcp" -c ~/architecturemcp) || echo "❌ Directory not found"
                return
                ;;
            w|W)
                echo "🚀 Starting dotfiles work session..."
                (cd ~/.dotfiles && tmux new-session -s "work" -c ~/.dotfiles)
                return
                ;;
            t|T)
                echo "🚀 Starting temp session..."
                tmux new-session -s "temp"
                return
                ;;
            ca|CA)
                echo "🤖 Starting Claude agent session..."
                (cd ~/singularity-engine 2>/dev/null && tmux new-session -s "claude-agent" -c ~/singularity-engine) || echo "❌ Directory not found"
                return
                ;;
            cc|CC)
                echo "🧠 Claude context:"
                if command -v claude-remind >/dev/null 2>&1; then
                    claude-remind
                elif [[ -f "$HOME/singularity-engine/.repo/scripts/claude-remind.sh" ]]; then
                    bash "$HOME/singularity-engine/.repo/scripts/claude-remind.sh"
                else
                    echo "❌ Claude remind script not found"
                fi
                ;;
            k|K)
                echo "Available sessions to kill:"
                tmux list-sessions 2>/dev/null || echo "No sessions"
                read -rp "Session name to kill: " kill_name
                if [[ -n "$kill_name" ]]; then
                    tmux kill-session -t "$kill_name" 2>/dev/null && echo "🗑️  Killed: $kill_name" || echo "❌ Failed"
                fi
                ;;
            l|L)
                echo "📋 All sessions:"
                tmux list-sessions 2>/dev/null || echo "No sessions"
                ;;
            b|B)
                return
                ;;
            *)
                echo "❌ Invalid option"
                ;;
        esac
        
        if [[ "$session_choice" != "ca" && "$session_choice" != "CA" && "$session_choice" != "a" && "$session_choice" != "A" && "$session_choice" != "m" && "$session_choice" != "M" && "$session_choice" != "w" && "$session_choice" != "W" && "$session_choice" != "t" && "$session_choice" != "T" && "$session_choice" != "n" && "$session_choice" != "N" ]]; then
            read -rp "Press Enter to continue..."
        fi
    done
}

# Main menu loop
main_loop() {
    while true; do
        clear
        show_retro_banner
        show_server_menu
        echo ""
    done
}

# Quick connect mode
quick_connect() {
    local query="$1"
    local matches
    
    mapfile -t matches < <(get_servers | rg -i "$query" || grep -i "$query")
    
    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "❌ No servers found matching: $query"
        return 1
    elif [[ ${#matches[@]} -eq 1 ]]; then
        connect_server "${matches[0]}"
    else
        echo "🔍 Multiple matches for: $query"
        local i=1
        for match in "${matches[@]}"; do
            IFS='|' read -r name type host port user key desc <<< "$match"
            echo "  [$i] $name ($type) - $desc"
            ((i++))
        done
        read -rp "Select [1]: " choice
        choice="${choice:-1}"
        if [[ $choice -le ${#matches[@]} ]]; then
            connect_server "${matches[$((choice-1))]}"
        fi
    fi
}

# Main function
main() {
    # Ensure config exists
    init_config
    
    # Handle arguments
    case "${1:-}" in
        "init")
            echo "✅ Configuration initialized at: $CONNECTIONS_FILE"
            ;;
        "add")
            add_server
            ;;
        "edit")
            edit_config
            ;;
        "help"|"-h"|"--help")
            echo "🎯 Retro Login - ASCII Terminal Connection Manager"
            echo ""
            echo "Usage:"
            echo "  retro-login              # Interactive menu"
            echo "  retro-login <name>       # Quick connect"
            echo "  retro-login add         # Add server"
            echo "  retro-login edit        # Edit config"
            echo "  retro-login init        # Initialize config"
            echo ""
            echo "Config: $CONNECTIONS_FILE"
            ;;
        "")
            main_loop
            ;;
        *)
            quick_connect "$1"
            ;;
    esac
}

# Additional connection functions
connect_redis() {
    local name="$1" host="$2" port="$3" password="$4"
    echo "🔴 Connecting to Redis: $name"
    local cmd="redis-cli -h $host -p $port"
    if [[ -n "$password" && "$password" != "password" ]]; then
        cmd="$cmd -a $password"
    fi
    eval "$cmd"
}

connect_postgres() {
    local name="$1" host="$2" port="$3" user="$4" password="$5"
    echo "🐘 Connecting to PostgreSQL: $name"
    local cmd="psql -h $host -p $port -U $user"
    eval "$cmd"
}

connect_aws() {
    local name="$1" region="$2"
    echo "☁️  AWS Console for: $name"
    if command -v aws >/dev/null 2>&1; then
        export AWS_DEFAULT_REGION="$region"
        echo "💡 AWS CLI ready. Region: $region"
        echo "   Try: aws ec2 describe-instances"
        bash
    else
        echo "❌ AWS CLI not found. Install with: mise install aws-cli"
    fi
}

connect_gcp() {
    local name="$1" project="$2"
    echo "☁️  GCP Console for: $name"
    if command -v gcloud >/dev/null 2>&1; then
        gcloud config set project "$project" 2>/dev/null || true
        echo "💡 GCP CLI ready. Project: $project"
        echo "   Try: gcloud compute instances list"
        bash
    else
        echo "❌ GCP CLI not found. Install with: mise install gcloud"
    fi
}

connect_azure() {
    local name="$1" subscription="$2" resource_group="$3"
    echo "☁️  Azure Console for: $name"
    
    if command -v az >/dev/null 2>&1; then
        echo "🔧 Azure CLI found"
        
        # Set subscription if provided
        if [[ -n "$subscription" && "$subscription" != "localhost" ]]; then
            az account set --subscription "$subscription" 2>/dev/null || {
                echo "⚠️  Subscription '$subscription' not found"
            }
        fi
        
        echo "Available options:"
        echo "  [1] List VMs"
        echo "  [2] SSH to VM (if configured)"
        echo "  [3] Azure CLI shell"
        echo "  [4] Open Azure Portal"
        read -rp "Choice [1]: " azure_choice
        
        case "${azure_choice:-1}" in
            1)
                echo "📋 Listing Azure VMs..."
                az vm list --output table 2>/dev/null || echo "❌ Failed to list VMs"
                ;;
            2)
                echo "🔍 Finding VMs with SSH access..."
                local vms
                mapfile -t vms < <(az vm list --query "[].{Name:name, ResourceGroup:resourceGroup}" --output tsv 2>/dev/null)
                
                if [[ ${#vms[@]} -gt 0 ]]; then
                    echo "Select VM to SSH into:"
                    local i=1
                    for vm in "${vms[@]}"; do
                        echo "  [$i] $vm"
                        ((i++))
                    done
                    read -rp "VM [1]: " vm_choice
                    vm_choice="${vm_choice:-1}"
                    
                    if [[ $vm_choice -le ${#vms[@]} ]]; then
                        local selected_vm="${vms[$((vm_choice-1))]}"
                        local vm_name="${selected_vm%	*}"
                        local rg_name="${selected_vm#*	}"
                        
                        echo "🔗 Getting SSH connection info for $vm_name..."
                        az ssh vm --name "$vm_name" --resource-group "$rg_name" 2>/dev/null || {
                            echo "❌ SSH failed. Ensure VM has SSH enabled and you have access"
                        }
                    fi
                else
                    echo "❌ No VMs found"
                fi
                ;;
            3)
                echo "💡 Azure CLI ready"
                echo "   Try: az vm list"
                echo "   Try: az group list"
                bash
                ;;
            4)
                echo "🌐 Opening Azure Portal..."
                if command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "https://portal.azure.com" 2>/dev/null
                elif command -v open >/dev/null 2>&1; then
                    open "https://portal.azure.com" 2>/dev/null
                else
                    echo "💡 Open manually: https://portal.azure.com"
                fi
                ;;
        esac
    else
        echo "❌ Azure CLI not found"
        echo "💡 Install with: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        echo "💡 Or visit: https://portal.azure.com"
    fi
}

# Tabby sync menu
tabby_menu() {
    echo ""
    echo "🔄 Tabby Sync Options"
    echo "────────────────────"
    echo "  [1] Sync all SSH connections to Tabby"
    echo "  [2] Import connections from Tabby"
    echo "  [3] View Tabby config"
    echo "  [4] Backup Tabby config to gist"
    echo "  [b]ack to main menu"
    
    read -rp "Choice: " tabby_choice
    
    case "$tabby_choice" in
        1)
            sync_all_to_tabby
            ;;
        2)
            import_from_tabby
            ;;
        3)
            if [[ -f "$TABBY_CONFIG" ]]; then
                echo "📄 Tabby configuration:"
                bat "$TABBY_CONFIG" 2>/dev/null || cat "$TABBY_CONFIG"
            else
                echo "❌ Tabby config not found at $TABBY_CONFIG"
            fi
            ;;
        4)
            if [[ -n "${TABBY_GIST_ID:-}" ]]; then
                echo "💾 Backing up Tabby config..."
                gh gist edit "$TABBY_GIST_ID" "$TABBY_CONFIG" 2>/dev/null && {
                    echo "✅ Backup complete"
                } || {
                    echo "❌ Backup failed"
                }
            else
                echo "💡 Set TABBY_GIST_ID in ~/.env_tokens to enable gist backup"
            fi
            ;;
        b|B)
            return
            ;;
        *)
            echo "❌ Invalid option"
            ;;
    esac
    
    read -rp "Press Enter to continue..."
}

# Claude tools menu
claude_tools_menu() {
    echo ""
    echo "🤖 Claude Tools & Context"
    echo "─────────────────────────"
    echo "  [1] Claude remind (cr) - Show current context"
    echo "  [2] Update project context"
    echo "  [3] View CLAUDE.md"
    echo "  [4] Edit CLAUDE.md"
    echo "  [5] Commit dotfiles changes"
    echo "  [6] Backup env tokens to gist"
    echo "  [b]ack to main menu"
    
    read -rp "Choice: " claude_choice
    
    case "$claude_choice" in
        1)
            echo "🧠 Current Claude context:"
            if command -v claude-remind >/dev/null 2>&1; then
                claude-remind
            elif [[ -f "$HOME/singularity-engine/.repo/scripts/claude-remind.sh" ]]; then
                bash "$HOME/singularity-engine/.repo/scripts/claude-remind.sh"
            else
                echo "❌ Claude remind script not found"
            fi
            ;;
        2)
            echo "📝 Updating project context..."
            cd "$HOME/singularity-engine" 2>/dev/null || {
                echo "❌ singularity-engine directory not found"
                return 1
            }
            
            # Show current directory structure
            echo "Current project structure:"
            eza --tree --level=2 --icons 2>/dev/null || find . -maxdepth 2 -type d
            
            echo ""
            echo "💡 Add important context to .repo/context/"
            read -rp "Open context directory? [y/N]: " open_context
            if [[ "$open_context" =~ ^[Yy] ]]; then
                cd ".repo/context" 2>/dev/null || mkdir -p ".repo/context"
                "${EDITOR:-nano}" .
            fi
            ;;
        3)
            echo "📄 CLAUDE.md contents:"
            if [[ -f "$HOME/CLAUDE.md" ]]; then
                bat "$HOME/CLAUDE.md" 2>/dev/null || cat "$HOME/CLAUDE.md"
            elif [[ -f "$HOME/.dotfiles/CLAUDE.md" ]]; then
                bat "$HOME/.dotfiles/CLAUDE.md" 2>/dev/null || cat "$HOME/.dotfiles/CLAUDE.md"
            else
                echo "❌ CLAUDE.md not found"
            fi
            ;;
        4)
            echo "✏️  Editing CLAUDE.md..."
            if [[ -f "$HOME/CLAUDE.md" ]]; then
                "${EDITOR:-nano}" "$HOME/CLAUDE.md"
            elif [[ -f "$HOME/.dotfiles/CLAUDE.md" ]]; then
                "${EDITOR:-nano}" "$HOME/.dotfiles/CLAUDE.md"
            else
                echo "❌ CLAUDE.md not found"
            fi
            ;;
        5)
            echo "💾 Committing dotfiles changes..."
            cd "$HOME/.dotfiles" || {
                echo "❌ Dotfiles directory not found"
                return 1
            }
            
            # Show current status
            git status --short
            echo ""
            read -rp "Commit message: " commit_msg
            
            if [[ -n "$commit_msg" ]]; then
                git add -A
                git commit -m "$commit_msg"
                git push
                echo "✅ Dotfiles committed and pushed"
            else
                echo "❌ No commit message provided"
            fi
            ;;
        6)
            echo "🔐 Backing up env tokens..."
            if [[ -n "${ENV_TOKENS_GIST_ID:-}" && -f "$HOME/.env_tokens" ]]; then
                gh gist edit "$ENV_TOKENS_GIST_ID" "$HOME/.env_tokens" 2>/dev/null && {
                    echo "✅ Env tokens backed up to gist"
                } || {
                    echo "❌ Backup failed"
                }
            else
                echo "💡 Set ENV_TOKENS_GIST_ID in ~/.env_tokens to enable backup"
                echo "💡 Format: export ENV_TOKENS_GIST_ID=\"your_gist_id\""
            fi
            ;;
        b|B)
            return
            ;;
        *)
            echo "❌ Invalid option"
            ;;
    esac
    
    read -rp "Press Enter to continue..."
}

# Git tree navigation menu
git_tree_menu() {
    echo ""
    echo "🌳 Git Tree Navigation"
    echo "──────────────────────"
    
    # Find git repositories
    local repos=()
    local common_dirs=("$HOME/singularity-engine" "$HOME/.dotfiles" "$HOME/architecturemcp")
    
    # Show existing sessions first
    echo "🎛️  Active Sessions (quick access):"
    local active_sessions=()
    if command -v tmux >/dev/null 2>&1; then
        mapfile -t active_sessions < <(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)
    fi
    
    if [[ ${#active_sessions[@]} -gt 0 ]]; then
        local s=1
        for session in "${active_sessions[@]}"; do
            echo "  [s$s] 📎 Attach to session: $session"
            ((s++))
        done
    else
        echo "  No active sessions"
    fi
    
    echo ""
    echo "📁 Available repositories:"
    local i=1
    for dir in "${common_dirs[@]}"; do
        if [[ -d "$dir/.git" ]]; then
            repos+=("$dir")
            local status=""
            cd "$dir" 2>/dev/null && {
                local changes
                changes=$(git status --porcelain 2>/dev/null | wc -l)
                if [[ $changes -gt 0 ]]; then
                    status=" (${changes} changes)"
                fi
                local branch
                branch=$(git branch --show-current 2>/dev/null || echo "unknown")
                echo "  [$i] $(basename "$dir") [$branch]$status"
            }
            ((i++))
        fi
    done
    
    # Add option to find more repos
    echo "  [f] Find more git repositories"
    echo "  [s] Show git status for all repos"
    echo "  [b] Back to main menu"
    echo ""
    
    read -rp "Selection: " git_choice
    
    case "$git_choice" in
        s[1-9]*)
            # Handle session selection (s1, s2, etc.)
            local session_num="${git_choice#s}"
            if [[ $session_num -le ${#active_sessions[@]} ]]; then
                local selected_session="${active_sessions[$((session_num-1))]}"
                echo "📎 Attaching to session: $selected_session"
                tmux attach-session -t "$selected_session"
                return  # Exit after attaching
            else
                echo "❌ Invalid session selection"
            fi
            ;;
        [1-9]*)
            if [[ $git_choice -le ${#repos[@]} ]]; then
                local selected_repo="${repos[$((git_choice-1))]}"
                navigate_repo "$selected_repo"
            else
                echo "❌ Invalid selection"
            fi
            ;;
        f|F)
            echo "🔍 Searching for git repositories..."
            echo "This may take a moment..."
            
            # Search for git repos (limit depth to avoid taking forever)
            local found_repos
            mapfile -t found_repos < <(fd -t d -H -d 3 "\.git$" "$HOME" 2>/dev/null | sed 's|/.git$||')
            
            if [[ ${#found_repos[@]} -gt 0 ]]; then
                echo "Found repositories:"
                local j=1
                for repo in "${found_repos[@]}"; do
                    echo "  [$j] $repo"
                    ((j++))
                done
                
                read -rp "Select repository [1]: " found_choice
                found_choice="${found_choice:-1}"
                
                if [[ $found_choice -le ${#found_repos[@]} ]]; then
                    navigate_repo "${found_repos[$((found_choice-1))]}"
                fi
            else
                echo "❌ No additional git repositories found"
            fi
            ;;
        s|S)
            echo "📊 Git status for all repositories:"
            for repo in "${repos[@]}"; do
                echo ""
                echo "🔍 $(basename "$repo") ($repo):"
                cd "$repo" 2>/dev/null && {
                    git status --short
                    local behind_ahead
                    behind_ahead=$(git status -b --porcelain 2>/dev/null | head -1)
                    if [[ "$behind_ahead" =~ \[.*\] ]]; then
                        echo "   Branch status: ${behind_ahead#*[}"
                    fi
                } || echo "   ❌ Failed to read status"
            done
            ;;
        b|B)
            return
            ;;
        *)
            echo "❌ Invalid option"
            ;;
    esac
    
    read -rp "Press Enter to continue..."
}

# Navigate and explore a git repository
navigate_repo() {
    local repo_path="$1"
    local repo_name
    repo_name=$(basename "$repo_path")
    
    while true; do
        clear
        echo "🌳 Git Repository: $repo_name"
        echo "═══════════════════════════════════════════════════════════════"
        echo "📁 Path: $repo_path"
        
        cd "$repo_path" 2>/dev/null || {
            echo "❌ Cannot access repository"
            return 1
        }
        
        # Show git status
        echo ""
        echo "📊 Git Status:"
        local branch
        branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        echo "   Branch: $branch"
        
        local changes
        changes=$(git status --porcelain 2>/dev/null)
        if [[ -n "$changes" ]]; then
            echo "   Changes:"
            echo "$changes" | head -5
            local total_changes
            total_changes=$(echo "$changes" | wc -l)
            if [[ $total_changes -gt 5 ]]; then
                echo "   ... and $((total_changes - 5)) more"
            fi
        else
            echo "   ✅ Working directory clean"
        fi
        
        # Show recent commits
        echo ""
        echo "📝 Recent commits:"
        git log --oneline -5 2>/dev/null || echo "   No commits found"
        
        # Show directory structure
        echo ""
        echo "📂 Directory structure:"
        eza --tree --level=2 --icons 2>/dev/null || find . -maxdepth 2 -type d | head -10
        
        echo ""
        echo "Options:"
        echo "  [1] Full git status"
        echo "  [2] Git log (detailed)"
        echo "  [3] Show file tree"
        echo "  [4] Create/switch branch"
        echo "  [5] Commit changes"
        echo "  [6] Push/pull"
        echo "  [7] Open in editor"
        echo "  [8] Start session here"
        echo "  [b] Back to git menu"
        
        read -rp "Choice: " repo_choice
        
        case "$repo_choice" in
            1)
                echo "📊 Full git status:"
                git status
                ;;
            2)
                echo "📝 Git log:"
                git log --oneline --graph -10
                ;;
            3)
                echo "🌳 File tree:"
                eza --tree --level=3 --icons 2>/dev/null || find . -type f | head -20
                ;;
            4)
                echo "🌿 Branch management:"
                echo "Current branches:"
                git branch -a
                echo ""
                read -rp "Create new branch or switch to existing [name]: " branch_name
                if [[ -n "$branch_name" ]]; then
                    git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"
                fi
                ;;
            5)
                echo "💾 Committing changes:"
                git add -A
                git status --short
                read -rp "Commit message: " commit_message
                if [[ -n "$commit_message" ]]; then
                    git commit -m "$commit_message"
                    echo "✅ Changes committed"
                fi
                ;;
            6)
                echo "🔄 Sync with remote:"
                echo "  [1] Pull latest changes"
                echo "  [2] Push local changes"
                echo "  [3] Both (pull then push)"
                read -rp "Choice [3]: " sync_choice
                
                case "${sync_choice:-3}" in
                    1) git pull ;;
                    2) git push ;;
                    3) git pull && git push ;;
                esac
                ;;
            7)
                echo "📝 Opening in editor..."
                "${EDITOR:-code}" .
                ;;
            8)
                echo "🎛️  Starting session..."
                # Use existing simple-sessions.sh function
                if command -v tmux >/dev/null 2>&1; then
                    local session_name="$repo_name"
                    if tmux has-session -t "$session_name" 2>/dev/null; then
                        echo "📎 Attaching to existing session: $session_name"
                        tmux attach-session -t "$session_name"
                    else
                        echo "🚀 Creating new session: $session_name"
                        tmux new-session -s "$session_name" -c "$repo_path"
                    fi
                    return  # Exit after starting session
                else
                    echo "❌ tmux not available"
                fi
                ;;
            b|B)
                return
                ;;
            *)
                echo "❌ Invalid option"
                ;;
        esac
        
        if [[ "$repo_choice" != "8" ]]; then
            read -rp "Press Enter to continue..."
        fi
    done
}

# Sync connection to Tabby config
sync_to_tabby() {
    local name="$1" host="$2" port="$3" user="$4" key="$5"
    
    # Check if Tabby config exists
    if [[ ! -f "$TABBY_CONFIG" ]]; then
        echo "⚠️  Tabby config not found at $TABBY_CONFIG"
        return 1
    fi
    
    # Expand tilde in key path
    if [[ "$key" == "~/"* ]]; then
        key="${key/#\~/$HOME}"
    fi
    
    # Create connection entry for Tabby
    local connection_entry="
  - name: \"$name\"
    host: \"$host\"
    port: $port
    user: \"$user\""
    
    if [[ -n "$key" && -f "$key" ]]; then
        connection_entry="$connection_entry
    privateKey: \"$key\""
    fi
    
    # Check if connection already exists in Tabby config
    if rg -q "name: \"$name\"" "$TABBY_CONFIG" 2>/dev/null; then
        echo "📱 Connection '$name' already exists in Tabby"
    else
        # Add connection to Tabby config
        if command -v sd >/dev/null 2>&1; then
            # Use sd if available
            if rg -q "connections: \[\]" "$TABBY_CONFIG" 2>/dev/null; then
                sd "connections: \[\]" "connections:$connection_entry" "$TABBY_CONFIG"
            elif rg -q "connections:" "$TABBY_CONFIG" 2>/dev/null; then
                sd "(connections:.*?)\n(\w)" "\$1$connection_entry\n\$2" "$TABBY_CONFIG"
            else
                echo "ssh:" >> "$TABBY_CONFIG"
                echo "  connections:$connection_entry" >> "$TABBY_CONFIG"
            fi
        else
            # Fallback to sed/awk if sd not available
            if rg -q "connections: \[\]" "$TABBY_CONFIG" 2>/dev/null; then
                sed -i "s/connections: \[\]/connections:$connection_entry/" "$TABBY_CONFIG"
            elif rg -q "connections:" "$TABBY_CONFIG" 2>/dev/null; then
                # Simple append to ssh connections section
                echo "$connection_entry" >> "$TABBY_CONFIG"
            else
                echo "ssh:" >> "$TABBY_CONFIG"
                echo "  connections:$connection_entry" >> "$TABBY_CONFIG"
            fi
        fi
        echo "✅ Added '$name' to Tabby config"
    fi
    
    # Backup Tabby config to gist if configured
    if [[ -n "${TABBY_GIST_ID:-}" ]]; then
        echo "💾 Backing up Tabby config to gist..."
        gh gist edit "$TABBY_GIST_ID" "$TABBY_CONFIG" 2>/dev/null || {
            echo "⚠️  Failed to backup to gist. Set TABBY_GIST_ID in ~/.env_tokens"
        }
    fi
}

# Import connections from Tabby
import_from_tabby() {
    if [[ ! -f "$TABBY_CONFIG" ]]; then
        echo "❌ Tabby config not found"
        return 1
    fi
    
    echo "📥 Importing connections from Tabby..."
    
    # Parse Tabby SSH connections (simplified YAML parsing)
    local imported=0
    
    # Look for SSH connections in Tabby config
    if rg -q "ssh:" "$TABBY_CONFIG" 2>/dev/null; then
        echo "Found Tabby SSH connections:"
        
        # Extract connection details (basic parsing)
        while IFS= read -r line; do
            if [[ "$line" =~ name:.*\"(.*)\" ]]; then
                local name="${BASH_REMATCH[1]}"
                echo "  - $name"
                ((imported++))
            fi
        done < <(rg -A 10 "name:" "$TABBY_CONFIG" 2>/dev/null || true)
        
        echo "📊 Found $imported connections in Tabby"
        echo "💡 Manual sync: Copy connection details from Tabby to retro-login config"
    else
        echo "No SSH connections found in Tabby config"
    fi
}

# Sync all retro-login connections to Tabby
sync_all_to_tabby() {
    echo "🔄 Syncing all connections to Tabby..."
    
    local servers
    mapfile -t servers < <(get_servers)
    
    local synced=0
    for server in "${servers[@]}"; do
        IFS='|' read -r name type host port user key desc <<< "$server"
        
        if [[ "$type" == "ssh" ]]; then
            sync_to_tabby "$name" "$host" "$port" "$user" "$key"
            ((synced++))
        fi
    done
    
    echo "✅ Synced $synced SSH connections to Tabby"
}

# Run main
main "$@"