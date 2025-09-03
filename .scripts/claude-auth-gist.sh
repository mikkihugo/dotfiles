#!/bin/bash
# Environment Variables Gist Sync
# Syncs environment files to private GitHub gists

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV_TOKENS_FILE="$HOME/.env_tokens"
GIST_ID_VAR="ENV_GIST_ID"

show_help() {
    echo -e "${BLUE}Environment Variables Gist Sync${NC}"
    echo "================================"
    echo ""
    echo "Commands:"
    echo "  init     Initialize new private gist"
    echo "  push     Upload env_tokens to gist"
    echo "  pull     Download from gist to env_tokens"
    echo "  status   Show current sync status"
    echo "  auto     Auto-sync (pull if exists, push if changed)"
}

# Check if gist ID is configured
get_gist_id() {
    if [ -f "$ENV_TOKENS_FILE" ]; then
        grep "^export $GIST_ID_VAR=" "$ENV_TOKENS_FILE" 2>/dev/null | cut -d'"' -f2 || echo ""
    else
        echo ""
    fi
}

# Initialize new gist
init_gist() {
    echo -e "${BLUE}🔧 Initializing new private gist for environment variables...${NC}"
    
    if [ ! -f "$ENV_TOKENS_FILE" ]; then
        echo -e "${RED}❌ $ENV_TOKENS_FILE not found${NC}"
        echo "Run this first: touch ~/.env_tokens"
        exit 1
    fi
    
    # Create private gist (private is default)
    echo -e "${YELLOW}📤 Creating private gist...${NC}"
    GIST_ID=$(gh gist create "$ENV_TOKENS_FILE" --desc "Environment variables - $(hostname)" | grep -oE '[a-f0-9]{32}')
    
    if [ -n "$GIST_ID" ]; then
        # Add gist ID to env_tokens file
        echo "" >> "$ENV_TOKENS_FILE"
        echo "# Gist sync configuration (auto-generated)" >> "$ENV_TOKENS_FILE"
        echo "export $GIST_ID_VAR=\"$GIST_ID\"" >> "$ENV_TOKENS_FILE"
        
        echo -e "${GREEN}✅ Private gist created: $GIST_ID${NC}"
        echo -e "${BLUE}🔗 URL: https://gist.github.com/$GIST_ID${NC}"
        
        # Test the sync
        echo -e "${YELLOW}🔄 Testing sync...${NC}"
        sleep 2
        push_to_gist
    else
        echo -e "${RED}❌ Failed to create gist${NC}"
        exit 1
    fi
}

# Push to gist
push_to_gist() {
    local gist_id=$(get_gist_id)
    
    if [ -z "$gist_id" ]; then
        echo -e "${RED}❌ No gist ID configured. Run 'init' first.${NC}"
        exit 1
    fi
    
    if [ ! -f "$ENV_TOKENS_FILE" ]; then
        echo -e "${RED}❌ $ENV_TOKENS_FILE not found${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📤 Pushing to gist: $gist_id${NC}"
    
    if gh gist edit "$gist_id" "$ENV_TOKENS_FILE"; then
        echo -e "${GREEN}✅ Successfully pushed to gist${NC}"
    else
        echo -e "${RED}❌ Failed to push to gist${NC}"
        exit 1
    fi
}

# Pull from gist
pull_from_gist() {
    local gist_id=$(get_gist_id)
    
    if [ -z "$gist_id" ]; then
        echo -e "${RED}❌ No gist ID configured${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📥 Pulling from gist: $gist_id${NC}"
    
    # Backup existing file
    if [ -f "$ENV_TOKENS_FILE" ]; then
        cp "$ENV_TOKENS_FILE" "${ENV_TOKENS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}💾 Backed up existing file${NC}"
    fi
    
    # Download from gist
    if gh gist view "$gist_id" --raw > "${ENV_TOKENS_FILE}.tmp"; then
        mv "${ENV_TOKENS_FILE}.tmp" "$ENV_TOKENS_FILE"
        echo -e "${GREEN}✅ Successfully pulled from gist${NC}"
    else
        echo -e "${RED}❌ Failed to pull from gist${NC}"
        # Restore backup if pull failed
        if [ -f "${ENV_TOKENS_FILE}.backup.$(date +%Y%m%d_%H%M%S)" ]; then
            mv "${ENV_TOKENS_FILE}.backup.$(date +%Y%m%d_%H%M%S)" "$ENV_TOKENS_FILE"
            echo -e "${YELLOW}🔄 Restored backup${NC}"
        fi
        exit 1
    fi
}

# Show status
show_status() {
    local gist_id=$(get_gist_id)
    
    echo -e "${BLUE}📊 Environment Gist Sync Status${NC}"
    echo "==============================="
    echo ""
    
    if [ -f "$ENV_TOKENS_FILE" ]; then
        local size=$(stat -c%s "$ENV_TOKENS_FILE" 2>/dev/null || echo "0")
        local date=$(stat -c%y "$ENV_TOKENS_FILE" 2>/dev/null | cut -d. -f1 || echo "Unknown")
        echo -e "${GREEN}✅ Local file: $ENV_TOKENS_FILE${NC}"
        echo -e "   Size: $size bytes"
        echo -e "   Modified: $date"
    else
        echo -e "${RED}❌ Local file: $ENV_TOKENS_FILE (missing)${NC}"
    fi
    
    echo ""
    
    if [ -n "$gist_id" ]; then
        echo -e "${GREEN}✅ Gist ID: $gist_id${NC}"
        echo -e "${BLUE}🔗 URL: https://gist.github.com/$gist_id${NC}"
        
        # Check if gist exists
        if gh gist view "$gist_id" --raw > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Gist accessible${NC}"
        else
            echo -e "${RED}❌ Gist not accessible${NC}"
        fi
    else
        echo -e "${RED}❌ No gist configured${NC}"
        echo -e "${YELLOW}💡 Run 'init' to create a new gist${NC}"
    fi
}

# Auto sync
auto_sync() {
    local gist_id=$(get_gist_id)
    
    if [ -z "$gist_id" ]; then
        echo -e "${YELLOW}⚠️  No gist configured, skipping sync${NC}"
        return 0
    fi
    
    if [ -f "$ENV_TOKENS_FILE" ]; then
        # Check if we can access the gist
        if gh gist view "$gist_id" --raw > /dev/null 2>&1; then
            # Compare timestamps (basic check)
            echo -e "${BLUE}🔄 Auto-syncing environment variables...${NC}"
            pull_from_gist
        else
            echo -e "${YELLOW}⚠️  Gist not accessible, pushing local version${NC}"
            push_to_gist
        fi
    else
        echo -e "${YELLOW}⚠️  No local env file, pulling from gist${NC}"
        pull_from_gist
    fi
}

# Main execution
case "${1:-help}" in
    "init")
        init_gist
        ;;
    "push")
        push_to_gist
        ;;
    "pull")
        pull_from_gist
        ;;
    "status")
        show_status
        ;;
    "auto")
        auto_sync
        ;;
    "help"|*)
        show_help
        ;;
esac