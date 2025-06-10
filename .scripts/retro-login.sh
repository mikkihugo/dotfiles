#!/bin/bash

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

# Production servers (examples)
prod-api|ssh|prod-api.company.com|22|admin|~/.ssh/prod_key|Production API server
prod-db|ssh|prod-db.company.com|22|admin|~/.ssh/prod_key|Production database

# Development (examples)
dev-api|ssh|dev-api.company.com|22|developer|~/.ssh/dev_key|Development API
dev-db|ssh|dev-db.company.com|22|developer|~/.ssh/dev_key|Development database

# Cloud providers
aws-prod|aws|us-east-1|443|admin||AWS Production
gcp-dev|gcp|us-central1|443|admin||GCP Development  
azure-prod|azure|subscription-id|443|admin||Azure Production

# Kubernetes
local-k8s|k8s|localhost|8001|kubectl||Local K8s cluster
prod-k8s|k8s|prod-cluster|8001|kubectl||Production K8s

# Databases
redis-cache|redis|redis.company.com|6379|admin|password|Redis cache cluster
postgres-main|postgres|db.company.com|5432|admin|password|Main PostgreSQL
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

# Show server menu
show_server_menu() {
    local servers
    mapfile -t servers < <(get_servers)
    
    if [[ ${#servers[@]} -eq 0 ]]; then
        echo "❌ No servers found in $CONNECTIONS_FILE"
        return 1
    fi
    
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│                              SERVER SELECTION                               │"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    
    local i=1
    for server in "${servers[@]}"; do
        IFS='|' read -r name type host port user key desc <<< "$server"
        printf "│ %-2d │ %-15s │ %-8s │ %-20s │ %s\n" "$i" "$name" "$type" "$host" "$desc"
        ((i++))
    done
    
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Options:"
    echo "  [1-${#servers[@]}] Connect to server"
    echo "  [a]dd new server"
    echo "  [e]dit config"
    echo "  [s]essions - show tmux/zellij sessions"
    echo "  [t]abby sync - sync with Tabby config"
    echo "  [c]laude tools - context and reminders"
    echo "  [g]it tree - project navigation"
    echo "  [q]uit"
    echo ""
    read -rp "Selection: " choice
    
    case "$choice" in
        [1-9]*) 
            if [[ $choice -le ${#servers[@]} ]]; then
                connect_server "${servers[$((choice-1))]}"
            else
                echo "❌ Invalid selection"
            fi
            ;;
        a|A) add_server ;;
        e|E) edit_config ;;
        s|S) show_sessions ;;
        t|T) tabby_menu ;;
        c|C) claude_tools_menu ;;
        g|G) git_tree_menu ;;
        q|Q) echo "👋 Goodbye!"; exit 0 ;;
        *) echo "❌ Invalid option" ;;
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

# Show sessions (integrate with simple-sessions.sh)
show_sessions() {
    echo ""
    echo "🎛️  Active Sessions"
    echo "─────────────────"
    
    # Check for tmux sessions
    if command -v tmux >/dev/null 2>&1; then
        echo "📋 Tmux sessions:"
        tmux list-sessions 2>/dev/null || echo "   No tmux sessions"
    fi
    
    # Check for zellij sessions  
    if command -v zellij >/dev/null 2>&1; then
        echo ""
        echo "🎯 Zellij sessions:"
        zellij list-sessions 2>/dev/null || echo "   No zellij sessions"
    fi
    
    echo ""
    echo "💡 Session commands (from simple-sessions.sh):"
    echo "   s [name]  - Create/attach session"
    echo "   sl        - List sessions"
    echo "   sk <name> - Kill session"
    echo "   sa/sm/sw/st - Quick shortcuts"
    
    read -rp "Press Enter to continue..."
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
        if rg -q "connections: \[\]" "$TABBY_CONFIG" 2>/dev/null; then
            # Replace empty connections array
            sd "connections: \[\]" "connections:$connection_entry" "$TABBY_CONFIG"
        elif rg -q "connections:" "$TABBY_CONFIG" 2>/dev/null; then
            # Append to existing connections
            sd "(connections:.*?)\n(\w)" "\$1$connection_entry\n\$2" "$TABBY_CONFIG"
        else
            # Add ssh section with connections
            echo "ssh:" >> "$TABBY_CONFIG"
            echo "  connections:$connection_entry" >> "$TABBY_CONFIG"
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