#!/bin/bash
#
# Ops Host Manager - Determines if this host should run ops services
# Purpose: Ensure services run on only ONE designated server
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get current hostname
CURRENT_HOST=$(hostname -f 2>/dev/null || hostname)

# Check for local override
if [ -f "$HOME/.dotfiles/.config/ops-hosts.local" ]; then
    source "$HOME/.dotfiles/.config/ops-hosts.local"
else
    source "$HOME/.dotfiles/.config/ops-hosts.conf"
fi

# Function to check if we're the primary ops host
is_ops_primary() {
    [ "$CURRENT_HOST" = "$OPS_PRIMARY_HOST" ]
}

# Function to check if we should run services
should_run_services() {
    # Check local override first
    if [ -f "$HOME/.ops-primary" ]; then
        return 0
    fi
    
    # Check if we're the designated primary
    if is_ops_primary; then
        return 0
    fi
    
    # Check if primary is down and we're backup
    if [ "$CURRENT_HOST" = "$OPS_BACKUP_HOST" ]; then
        if ! ping -c 1 -W 2 "$OPS_PRIMARY_HOST" &>/dev/null; then
            echo -e "${YELLOW}Primary host down, activating backup ops services${NC}"
            return 0
        fi
    fi
    
    return 1
}

# Function to start ops services
start_ops_services() {
    echo -e "${GREEN}Starting ops services on $CURRENT_HOST${NC}"
    
    if [ "$RUN_TABBY_GATEWAY" = "true" ]; then
        systemctl --user start tabby-gateway.service || true
    fi
    
    if [ "$RUN_TABBY_SYNC" = "true" ]; then
        systemctl --user start tabby-sync.timer || true
    fi
    
    if [ "$RUN_MONITORING" = "true" ]; then
        systemctl --user start ops-monitor.service || true
    fi
}

# Function to stop ops services
stop_ops_services() {
    echo -e "${YELLOW}Stopping ops services on $CURRENT_HOST${NC}"
    
    systemctl --user stop tabby-gateway.service 2>/dev/null || true
    systemctl --user stop tabby-sync.timer 2>/dev/null || true
    systemctl --user stop ops-monitor.service 2>/dev/null || true
}

# Main logic
case "${1:-status}" in
    start)
        if should_run_services; then
            start_ops_services
        else
            echo -e "${RED}This host ($CURRENT_HOST) is not designated to run ops services${NC}"
            echo "Primary ops host: $OPS_PRIMARY_HOST"
        fi
        ;;
    
    stop)
        stop_ops_services
        ;;
    
    status)
        echo "Current host: $CURRENT_HOST"
        echo "Primary ops: $OPS_PRIMARY_HOST"
        echo "Backup ops: $OPS_BACKUP_HOST"
        echo ""
        
        if should_run_services; then
            echo -e "${GREEN}✓ This host SHOULD run ops services${NC}"
            systemctl --user status tabby-gateway.service tabby-sync.timer 2>/dev/null || true
        else
            echo -e "${YELLOW}✗ This host should NOT run ops services${NC}"
        fi
        ;;
    
    claim)
        # Force this host to become primary
        echo "$CURRENT_HOST" > "$HOME/.ops-primary"
        echo -e "${GREEN}Claimed ops primary role for $CURRENT_HOST${NC}"
        start_ops_services
        ;;
    
    release)
        # Release primary role
        rm -f "$HOME/.ops-primary"
        echo -e "${YELLOW}Released ops primary role${NC}"
        stop_ops_services
        ;;
    
    sync-hosts)
        # Sync host configuration from gist
        if [ -n "$GIST_CONFIG_ID" ]; then
            echo "Syncing ops host configuration from gist..."
            curl -sL "https://gist.github.com/raw/$GIST_CONFIG_ID/ops-hosts.conf" \
                -o "$HOME/.dotfiles/.config/ops-hosts.conf.new"
            
            if [ -s "$HOME/.dotfiles/.config/ops-hosts.conf.new" ]; then
                mv "$HOME/.dotfiles/.config/ops-hosts.conf.new" \
                   "$HOME/.dotfiles/.config/ops-hosts.conf"
                echo -e "${GREEN}✓ Ops host configuration updated${NC}"
            fi
        fi
        ;;
    
    *)
        echo "Usage: $0 {start|stop|status|claim|release|sync-hosts}"
        exit 1
        ;;
esac