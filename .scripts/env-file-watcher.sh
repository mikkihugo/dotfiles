#!/bin/bash
# Environment File Watcher
# Automatically syncs environment files when they're modified

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(dirname "$0")"
SYNC_SCRIPT="$SCRIPT_DIR/multi-env-sync.sh"

# Files to watch
WATCH_FILES=(
    "$HOME/.env_tokens"
    "$HOME/.env_ai" 
    "$HOME/.env_docker"
    "$HOME/.env_repos"
)

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

sync_file() {
    local file="$1"
    local basename=$(basename "$file")
    local env_key=""
    
    # Map filename to environment key
    case "$basename" in
        ".env_tokens") env_key="tokens" ;;
        ".env_ai") env_key="ai" ;;
        ".env_docker") env_key="docker" ;;
        ".env_repos") env_key="repos" ;;
        *) return 1 ;;
    esac
    
    log "File changed: $file -> syncing $env_key"
    
    if "$SYNC_SCRIPT" push "$env_key" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Auto-synced $env_key${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to sync $env_key${NC}"
    fi
}

# Check if inotify-tools is available
if ! command -v inotifywait &> /dev/null; then
    echo "Installing inotify-tools for file watching..."
    sudo apt update && sudo apt install -y inotify-tools
fi

# Create watch files if they don't exist
for file in "${WATCH_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        touch "$file"
        log "Created $file"
    fi
done

log "Starting environment file watcher..."
log "Watching: ${WATCH_FILES[*]}"

# Watch for file modifications and sync automatically
inotifywait -m -e modify "${WATCH_FILES[@]}" 2>/dev/null |
while read path action file; do
    # Add small delay to avoid multiple rapid syncs
    sleep 2
    sync_file "$path$file"
done