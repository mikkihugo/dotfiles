#!/bin/bash

# SSH Manager with private gist integration
# Stores hosts in encrypted gist, provides fuzzy search

GIST_ID="${SSH_HOSTS_GIST_ID}"  # Set in ~/.env_tokens
HOSTS_FILE="$HOME/.ssh/hosts.json"

# Update hosts from gist
update_hosts() {
    if [ -z "$GIST_ID" ]; then
        echo "Error: SSH_HOSTS_GIST_ID not set in ~/.env_tokens"
        return 1
    fi
    
    echo "Updating hosts from gist..."
    gh gist view "$GIST_ID" > "$HOSTS_FILE.tmp" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
        echo "Hosts updated successfully"
    else
        echo "Failed to update hosts"
        rm -f "$HOSTS_FILE.tmp"
    fi
}

# Generate SSH config from hosts file
generate_ssh_config() {
    if [ ! -f "$HOSTS_FILE" ]; then
        echo "No hosts file found. Run: ssh-manager update"
        return 1
    fi
    
    # Backup existing config
    cp ~/.ssh/config ~/.ssh/config.bak 2>/dev/null
    
    # Generate new config
    cat > ~/.ssh/config.generated << 'EOF'
# Generated SSH config - DO NOT EDIT
# Edit the gist instead and run: ssh-manager update

EOF
    
    # Parse JSON and generate config
    if command -v jq &> /dev/null; then
        jq -r '.hosts[] | "Host \(.alias)\n  HostName \(.hostname)\n  User \(.user // "root")\n  Port \(.port // 22)\n" + (if .key then "  IdentityFile ~/.ssh/\(.key)\n" else "" end) + (if .forward_agent then "  ForwardAgent yes\n" else "" end) + (if .proxy then "  ProxyJump \(.proxy)\n" else "" end)' "$HOSTS_FILE" >> ~/.ssh/config.generated
    else
        echo "jq not found. Install it to parse hosts.json"
        return 1
    fi
    
    # Merge with existing config
    echo -e "\n# User config" >> ~/.ssh/config.generated
    grep -v "^# Generated SSH config" ~/.ssh/config 2>/dev/null >> ~/.ssh/config.generated || true
    
    mv ~/.ssh/config.generated ~/.ssh/config
    chmod 600 ~/.ssh/config
    echo "SSH config updated"
}

# Interactive SSH connection with fzf
ssh_connect() {
    if ! command -v fzf &> /dev/null; then
        echo "fzf not found. Install with: mise install fzf"
        return 1
    fi
    
    # Get list of hosts
    local hosts=$(grep "^Host " ~/.ssh/config 2>/dev/null | grep -v "\*" | cut -d' ' -f2)
    
    if [ -z "$hosts" ]; then
        echo "No hosts found in SSH config"
        return 1
    fi
    
    # Add recent hosts from history
    local recent=$(history | grep -E "ssh [^-]" | tail -20 | awk '{for(i=2;i<=NF;i++) if($i=="ssh") print $(i+1)}' | grep -v "^-" | sort -u)
    
    # Combine and dedupe
    local all_hosts=$(echo -e "$hosts\n$recent" | sort -u)
    
    # Select with fzf
    local selected=$(echo "$all_hosts" | fzf \
        --header="🔐 SSH CONNECTION MANAGER" \
        --preview='echo "Connecting to: {}"' \
        --height=50% \
        --reverse \
        --border)
    
    if [ ! -z "$selected" ]; then
        echo "Connecting to $selected..."
        
        # Check if mosh is available and connection is poor
        if command -v mosh &> /dev/null && [ "${USE_MOSH:-auto}" != "no" ]; then
            # Test connection latency
            local latency=$(ping -c 1 -W 1 "$selected" 2>/dev/null | grep "time=" | cut -d'=' -f4 | cut -d' ' -f1 | cut -d'.' -f1)
            
            if [ ! -z "$latency" ] && [ "$latency" -gt 100 ]; then
                echo "High latency detected (${latency}ms), using mosh..."
                mosh "$selected" -- tmux attach || tmux new
            else
                ssh "$selected" -t "tmux attach || tmux new || bash"
            fi
        else
            ssh "$selected" -t "tmux attach || tmux new || bash"
        fi
    fi
}

# Add new host to gist
add_host() {
    local alias="$1"
    local hostname="$2"
    local user="${3:-root}"
    local port="${4:-22}"
    
    if [ -z "$alias" ] || [ -z "$hostname" ]; then
        echo "Usage: ssh-manager add <alias> <hostname> [user] [port]"
        return 1
    fi
    
    # Update hosts file
    update_hosts
    
    # Add new host using jq
    if command -v jq &> /dev/null; then
        jq --arg alias "$alias" \
           --arg hostname "$hostname" \
           --arg user "$user" \
           --arg port "$port" \
           '.hosts += [{"alias": $alias, "hostname": $hostname, "user": $user, "port": $port | tonumber}]' \
           "$HOSTS_FILE" > "$HOSTS_FILE.tmp"
        
        mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
        
        # Update gist
        gh gist edit "$GIST_ID" "$HOSTS_FILE"
        
        # Regenerate SSH config
        generate_ssh_config
        
        echo "Host $alias added successfully"
    else
        echo "jq not found. Cannot add host."
        return 1
    fi
}

# Main command handler
case "${1:-connect}" in
    update)
        update_hosts && generate_ssh_config
        ;;
    add)
        shift
        add_host "$@"
        ;;
    connect|"")
        ssh_connect
        ;;
    edit)
        gh gist edit "$GIST_ID"
        ;;
    *)
        echo "Usage: ssh-manager [update|add|connect|edit]"
        echo "  update  - Update hosts from gist"
        echo "  add     - Add new host"
        echo "  connect - Connect to host (default)"
        echo "  edit    - Edit hosts gist directly"
        ;;
esac