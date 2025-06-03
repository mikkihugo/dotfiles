#!/bin/bash
# 🔄 Lightweight sync check on shell start

DOTFILES_DIR="$HOME/dotfiles"
LAST_SYNC_FILE="$HOME/.dotfiles-last-sync"
SYNC_INTERVAL=3600  # 1 hour in seconds

# Check if enough time has passed
if [[ -f "$LAST_SYNC_FILE" ]]; then
    LAST_SYNC=$(cat "$LAST_SYNC_FILE")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_SYNC))
    
    if [[ $TIME_DIFF -lt $SYNC_INTERVAL ]]; then
        # Not time yet
        return 0
    fi
fi

# Run sync in background
(
    cd "$DOTFILES_DIR" || exit
    git fetch origin main --quiet
    
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$LOCAL" != "$REMOTE" ]]; then
        echo "🔄 Dotfiles updates available! Run: cd ~/dotfiles && git pull"
        echo "   Or run: dotfiles-sync"
    fi
    
    # Update last sync time
    date +%s > "$LAST_SYNC_FILE"
) &