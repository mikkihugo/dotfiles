#!/bin/bash
# Multi-Environment Gist Sync System
# Manages multiple environment files with separate gists

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Environment file configuration
declare -A ENV_FILES=(
    ["tokens"]="~/.env_tokens|648e6e5ddf8923787e8adc19e9e96335|Personal Tokens (PRIVATE)"
    ["ai"]="~/.env_ai|a9f4ebacecff791970c390b76589d3be|AI Service Keys" 
    ["docker"]="~/.env_docker|a911d1895fe15dc9f2e3c6b1eccd20d3|Docker & Infrastructure"
    ["repos"]="~/.env_repos|6d666c098fe5f3f9b79aa2dae84976a7|Repository & Git Config"
)

show_help() {
    echo -e "${CYAN}Multi-Environment Gist Sync System${NC}"
    echo "=================================="
    echo ""
    echo "Commands:"
    echo "  status     Show sync status for all environment files"
    echo "  push       Push all environment files to their gists"
    echo "  pull       Pull all environment files from their gists"
    echo "  push <env> Push specific environment file"
    echo "  pull <env> Pull specific environment file"
    echo ""
    echo "Environment files:"
    for key in "${!ENV_FILES[@]}"; do
        IFS='|' read -r file gist desc <<< "${ENV_FILES[$key]}"
        echo "  $key - $desc"
    done
}

# Get file info
get_file_info() {
    local env_key="$1"
    local env_info="${ENV_FILES[$env_key]}"
    
    if [ -z "$env_info" ]; then
        echo "Unknown environment: $env_key" >&2
        return 1
    fi
    
    IFS='|' read -r file gist desc <<< "$env_info"
    file=$(eval echo "$file")  # Expand ~ 
    
    echo "$file|$gist|$desc"
}

# Show status for all files
show_status() {
    echo -e "${CYAN}📊 Multi-Environment Sync Status${NC}"
    echo "================================="
    echo ""
    
    for key in "${!ENV_FILES[@]}"; do
        file_info=$(get_file_info "$key")
        IFS='|' read -r file gist desc <<< "$file_info"
        
        echo -e "${BLUE}[$key] $desc${NC}"
        
        # Check local file
        if [ -f "$file" ]; then
            local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local date=$(stat -c%y "$file" 2>/dev/null | cut -d. -f1 || echo "Unknown")
            echo -e "  ${GREEN}✅ Local:${NC} $file ($size bytes, $date)"
        else
            echo -e "  ${RED}❌ Local:${NC} $file (missing)"
        fi
        
        # Check gist
        if gh gist view "$gist" --raw > /dev/null 2>&1; then
            echo -e "  ${GREEN}✅ Gist:${NC} https://gist.github.com/$gist"
        else
            echo -e "  ${RED}❌ Gist:${NC} $gist (not accessible)"
        fi
        
        echo ""
    done
}

# Push specific file to gist
push_file() {
    local env_key="$1"
    file_info=$(get_file_info "$env_key")
    IFS='|' read -r file gist desc <<< "$file_info"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}❌ File not found: $file${NC}"
        return 1
    fi
    
    echo -e "${BLUE}📤 Pushing $desc...${NC}"
    
    if gh gist edit "$gist" "$file"; then
        echo -e "${GREEN}✅ Successfully pushed $env_key${NC}"
    else
        echo -e "${RED}❌ Failed to push $env_key${NC}"
        return 1
    fi
}

# Pull specific file from gist
pull_file() {
    local env_key="$1"
    file_info=$(get_file_info "$env_key")
    IFS='|' read -r file gist desc <<< "$file_info"
    
    echo -e "${BLUE}📥 Pulling $desc...${NC}"
    
    # Backup existing file
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}💾 Backed up existing file${NC}"
    fi
    
    # Download from gist
    if gh gist view "$gist" --raw > "${file}.tmp"; then
        mv "${file}.tmp" "$file"
        echo -e "${GREEN}✅ Successfully pulled $env_key${NC}"
    else
        echo -e "${RED}❌ Failed to pull $env_key${NC}"
        # Restore backup if pull failed
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        if [ -f "$backup" ]; then
            mv "$backup" "$file"
            echo -e "${YELLOW}🔄 Restored backup${NC}"
        fi
        return 1
    fi
}

# Push all files
push_all() {
    echo -e "${CYAN}📤 Pushing all environment files...${NC}"
    
    local failed=0
    for key in "${!ENV_FILES[@]}"; do
        if ! push_file "$key"; then
            ((failed++))
        fi
    done
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✅ All files pushed successfully${NC}"
    else
        echo -e "${RED}❌ $failed files failed to push${NC}"
        return 1
    fi
}

# Pull all files
pull_all() {
    echo -e "${CYAN}📥 Pulling all environment files...${NC}"
    
    local failed=0
    for key in "${!ENV_FILES[@]}"; do
        if ! pull_file "$key"; then
            ((failed++))
        fi
    done
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✅ All files pulled successfully${NC}"
    else
        echo -e "${RED}❌ $failed files failed to pull${NC}"
        return 1
    fi
}

# Auto-sync setup
setup_auto_sync() {
    echo -e "${CYAN}⚙️ Setting up automatic sync...${NC}"
    
    # Create systemd timer for auto-pull on login
    local timer_dir="$HOME/.config/systemd/user"
    mkdir -p "$timer_dir"
    
    # Service file
    cat > "$timer_dir/env-sync.service" << 'EOF'
[Unit]
Description=Multi-Environment Sync Service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/mhugo/.dotfiles/.scripts/multi-env-sync.sh pull
Environment=HOME=/home/mhugo
WorkingDirectory=/home/mhugo

[Install]
WantedBy=default.target
EOF

    # Timer file for periodic sync
    cat > "$timer_dir/env-sync.timer" << 'EOF'
[Unit]
Description=Auto-sync environment files every 30 minutes
Requires=env-sync.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    systemctl --user daemon-reload
    systemctl --user enable env-sync.timer
    systemctl --user start env-sync.timer
    
    echo -e "${GREEN}✅ Auto-sync enabled (every 30 minutes)${NC}"
    echo -e "${BLUE}ℹ️  Check status: systemctl --user status env-sync.timer${NC}"
}

# Setup new machine from gists
setup_new_machine() {
    echo -e "${CYAN}🚀 Setting up new machine from existing gists...${NC}"
    
    # Check if GitHub CLI is authenticated
    if ! gh auth status &>/dev/null; then
        echo -e "${RED}❌ GitHub CLI not authenticated${NC}"
        echo "Please run: gh auth login"
        return 1
    fi
    
    # Pull all environment files
    echo -e "${BLUE}📥 Downloading environment files...${NC}"
    pull_all
    
    # Set up auto-sync
    setup_auto_sync
    
    # Reload shell configuration
    echo -e "${BLUE}🔄 Reloading shell configuration...${NC}"
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    
    echo -e "${GREEN}✅ New machine setup complete!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "1. Verify all environment files are loaded correctly"
    echo "2. Auto-sync is enabled and will run every 30 minutes"
    echo "3. Use 'env-sync status' to check sync status anytime"
}

# Main execution
case "${1:-help}" in
    "status")
        show_status
        ;;
    "push")
        if [ -n "$2" ]; then
            push_file "$2"
        else
            push_all
        fi
        ;;
    "pull")
        if [ -n "$2" ]; then
            pull_file "$2"
        else
            pull_all
        fi
        ;;
    "auto")
        setup_auto_sync
        ;;
    "setup"|"bootstrap")
        setup_new_machine
        ;;
    "help"|*)
        show_help
        ;;
esac