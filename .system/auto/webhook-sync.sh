#!/bin/bash
# Webhook endpoint for auto-syncing dotfiles across servers
# Called by GitHub webhook when dotfiles repo is updated

set -e

LOG_FILE="$HOME/.dotfiles/sync.log"
LOCK_FILE="$HOME/.dotfiles/.sync.lock"

# Prevent concurrent syncs
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Sync already in progress, skipping" >> "$LOG_FILE"
    exit 0
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Log sync start
echo "$(date): Starting dotfiles sync via webhook" >> "$LOG_FILE"

# Change to dotfiles directory
cd "$HOME/.dotfiles"

# Pull latest changes
if git pull origin main >> "$LOG_FILE" 2>&1; then
    echo "$(date): Git pull successful" >> "$LOG_FILE"
    
    # Install/update mise tools
    if mise install >> "$LOG_FILE" 2>&1; then
        echo "$(date): Mise install successful" >> "$LOG_FILE"
    else
        echo "$(date): Mise install failed" >> "$LOG_FILE"
    fi
    
    # Reload shell configuration for active sessions
    # (Note: This only affects new shells, existing ones need manual reload)
    
    # Auto-sync tokens and SSH hosts from gists
    if [ -n "$TOKENS_GIST_ID" ]; then
        if gh gist view "$TOKENS_GIST_ID" > ~/.env_tokens.new 2>/dev/null; then
            mv ~/.env_tokens.new ~/.env_tokens
            echo "$(date): Tokens synced from gist" >> "$LOG_FILE"
        fi
    fi
    
    if [ -n "$TABBY_GIST_ID" ]; then
        if tabby-sync pull >> "$LOG_FILE" 2>&1; then
            echo "$(date): SSH hosts synced" >> "$LOG_FILE"
        fi
    fi
    
    echo "$(date): Dotfiles sync completed successfully" >> "$LOG_FILE"
else
    echo "$(date): Git pull failed" >> "$LOG_FILE"
    exit 1
fi