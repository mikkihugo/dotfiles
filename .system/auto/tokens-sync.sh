#!/bin/bash
# Sync environment tokens from GitHub gist

TOKENS_GIST_ID="61a7776d4d278cc1ef57549a7d0f61f8"
TOKENS_FILE="$HOME/.env_tokens"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Download latest tokens
sync_tokens() {
    echo -e "${BLUE}📥 Syncing tokens from gist...${NC}"
    
    # Backup current
    if [ -f "$TOKENS_FILE" ]; then
        cp "$TOKENS_FILE" "$TOKENS_FILE.backup"
    fi
    
    # Download from gist
    if gh gist view "$TOKENS_GIST_ID" -f .env_tokens > "$TOKENS_FILE.tmp"; then
        mv "$TOKENS_FILE.tmp" "$TOKENS_FILE"
        chmod 600 "$TOKENS_FILE"
        echo -e "${GREEN}✓ Tokens synced${NC}"
        
        # Source tokens
        source "$TOKENS_FILE"
        
        # Extract Claude gist ID if present
        if [ -n "$CLAUDE_AUTH_GIST_ID" ]; then
            echo -e "${GREEN}✓ Claude auth gist: $CLAUDE_AUTH_GIST_ID${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to sync tokens${NC}"
        rm -f "$TOKENS_FILE.tmp"
        return 1
    fi
}

# Update tokens in gist
push_tokens() {
    echo -e "${BLUE}📤 Pushing tokens to gist...${NC}"
    
    if [ -f "$TOKENS_FILE" ]; then
        if gh gist edit "$TOKENS_GIST_ID" "$TOKENS_FILE"; then
            echo -e "${GREEN}✓ Tokens pushed${NC}"
        else
            echo -e "${RED}❌ Failed to push tokens${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ No tokens file found${NC}"
        return 1
    fi
}

# Initialize Claude auth if needed
init_claude_if_needed() {
    source "$TOKENS_FILE" 2>/dev/null || true
    
    if [ -z "$CLAUDE_AUTH_GIST_ID" ]; then
        echo -e "${YELLOW}⚠ No Claude auth gist found${NC}"
        echo -e "${BLUE}Creating new Claude auth gist...${NC}"
        
        # Run init and capture output
        local output=$(~/.dotfiles/.scripts/claude-auth-gist.sh init 2>&1)
        local gist_id=$(echo "$output" | grep -oE '[a-f0-9]{32}' | head -1)
        
        if [ -n "$gist_id" ]; then
            # Update tokens file
            sed -i "s/export CLAUDE_AUTH_GIST_ID=\"\"/export CLAUDE_AUTH_GIST_ID=\"$gist_id\"/" "$TOKENS_FILE"
            
            # Push updated tokens
            push_tokens
            
            echo -e "${GREEN}✓ Claude auth initialized: $gist_id${NC}"
        else
            echo -e "${RED}❌ Failed to init Claude auth${NC}"
            echo "$output"
        fi
    fi
}

# Main
case "${1:-sync}" in
    sync)
        sync_tokens
        ;;
    
    push)
        push_tokens
        ;;
    
    init-claude)
        sync_tokens
        init_claude_if_needed
        ;;
    
    full)
        sync_tokens
        init_claude_if_needed
        # Try to sync Claude auth too
        if [ -n "$CLAUDE_AUTH_GIST_ID" ]; then
            echo ""
            ~/.dotfiles/.scripts/claude-auth-gist.sh auto
        fi
        ;;
    
    *)
        echo "Usage: $0 {sync|push|init-claude|full}"
        echo ""
        echo "Manages tokens from gist: $TOKENS_GIST_ID"
        echo "  sync        - Download latest tokens"
        echo "  push        - Upload current tokens"
        echo "  init-claude - Initialize Claude auth if needed"
        echo "  full        - Sync everything"
        ;;
esac