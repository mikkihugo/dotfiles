#!/bin/bash
# Auto-sync dotfiles via cron/systemd timer
# Checks for updates and syncs when needed

set -e

DOTFILES_DIR="$HOME/.dotfiles"
LOG_FILE="$DOTFILES_DIR/auto-sync.log"
LOCK_FILE="$DOTFILES_DIR/.auto-sync.lock"
LAST_COMMIT_FILE="$DOTFILES_DIR/.last_commit"

# Prevent concurrent syncs
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Auto-sync already running, skipping" >> "$LOG_FILE"
    exit 0
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Change to dotfiles directory
cd "$DOTFILES_DIR"

# Get current local commit
LOCAL_COMMIT=$(git rev-parse HEAD)

# Fetch remote without merging
git fetch origin main --quiet

# Get remote commit
REMOTE_COMMIT=$(git rev-parse origin/main)

# Check if update is needed
if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    # No updates, but still sync gists periodically (every hour)
    if [ ! -f "$LAST_COMMIT_FILE" ] || [ "$(find "$LAST_COMMIT_FILE" -mmin +60 2>/dev/null)" ]; then
        echo "$(date): No git updates, checking gists..." >> "$LOG_FILE"
        
        # Sync tokens from gist
        if [ -n "$TOKENS_GIST_ID" ]; then
            if gh gist view "$TOKENS_GIST_ID" > ~/.env_tokens.new 2>/dev/null; then
                if ! diff -q ~/.env_tokens ~/.env_tokens.new >/dev/null 2>&1; then
                    mv ~/.env_tokens.new ~/.env_tokens
                    echo "$(date): Tokens updated from gist" >> "$LOG_FILE"
                else
                    rm -f ~/.env_tokens.new
                fi
            fi
        fi
        
        # Sync SSH hosts
        if [ -n "$TABBY_GIST_ID" ] && command -v tabby-sync >/dev/null 2>&1; then
            if tabby-sync pull >/dev/null 2>&1; then
                echo "$(date): SSH hosts checked" >> "$LOG_FILE"
            fi
        fi
        
        echo "$LOCAL_COMMIT" > "$LAST_COMMIT_FILE"
    fi
    exit 0
fi

echo "$(date): New commits available, syncing..." >> "$LOG_FILE"

# Pull latest changes
if git pull origin main >> "$LOG_FILE" 2>&1; then
    echo "$(date): Git pull successful" >> "$LOG_FILE"
    
    # Install/update mise tools
    if mise install >> "$LOG_FILE" 2>&1; then
        echo "$(date): Mise tools updated" >> "$LOG_FILE"
    else
        echo "$(date): Mise install failed" >> "$LOG_FILE"
    fi
    
    # Sync tokens from gist
    if [ -n "$TOKENS_GIST_ID" ]; then
        if gh gist view "$TOKENS_GIST_ID" > ~/.env_tokens.new 2>/dev/null; then
            mv ~/.env_tokens.new ~/.env_tokens
            echo "$(date): Tokens synced from gist" >> "$LOG_FILE"
        fi
    fi
    
    # Sync SSH hosts
    if [ -n "$TABBY_GIST_ID" ] && command -v tabby-sync >/dev/null 2>&1; then
        if tabby-sync pull >> "$LOG_FILE" 2>&1; then
            echo "$(date): SSH hosts synced" >> "$LOG_FILE"
        fi
    fi
    
    # Update last commit marker
    echo "$(git rev-parse HEAD)" > "$LAST_COMMIT_FILE"
    
    echo "$(date): Auto-sync completed successfully" >> "$LOG_FILE"
else
    echo "$(date): Git pull failed" >> "$LOG_FILE"
    exit 1
fi