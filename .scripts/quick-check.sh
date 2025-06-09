#!/bin/bash
# Quick hash-based check for dotfiles updates
# Uses GitHub API to get latest commit hash without git operations

REPO="mikkihugo/dotfiles"
HASH_FILE="$HOME/.dotfiles/.remote_hash"
LOG_FILE="$HOME/.dotfiles/quick-check.log"

# Get latest commit hash from GitHub API
get_remote_hash() {
    gh api repos/$REPO/commits/main --jq '.sha' 2>/dev/null | head -c 7
}

# Get local hash
get_local_hash() {
    if [ -f "$HASH_FILE" ]; then
        cat "$HASH_FILE"
    else
        echo "unknown"
    fi
}

# Quick check without sync
check_only() {
    local remote_hash=$(get_remote_hash)
    local local_hash=$(get_local_hash)
    
    if [ "$remote_hash" != "$local_hash" ] && [ -n "$remote_hash" ]; then
        echo "📦 Updates available ($local_hash → $remote_hash)"
        return 1
    else
        return 0
    fi
}

# Full sync and update hash
sync_and_update() {
    echo "$(date): Starting sync..." >> "$LOG_FILE"
    
    # Run the full sync
    cd "$HOME/.dotfiles"
    if mise run sync >> "$LOG_FILE" 2>&1; then
        # Update hash file with new remote hash
        get_remote_hash > "$HASH_FILE"
        echo "$(date): Sync completed" >> "$LOG_FILE"
        return 0
    else
        echo "$(date): Sync failed" >> "$LOG_FILE"
        return 1
    fi
}

case "${1:-check}" in
    check)
        check_only
        ;;
    sync)
        sync_and_update
        ;;
    hash)
        echo "Local:  $(get_local_hash)"
        echo "Remote: $(get_remote_hash)"
        ;;
    *)
        echo "Usage: $0 [check|sync|hash]"
        ;;
esac