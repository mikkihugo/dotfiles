#!/bin/bash
# 🔄 Auto-sync dotfiles from Git

DOTFILES_DIR="$HOME/dotfiles"
LOG_FILE="$HOME/.dotfiles-sync.log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if we're in a git repo
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    log "ERROR: $DOTFILES_DIR is not a git repository"
    exit 1
fi

cd "$DOTFILES_DIR" || exit 1

# Fetch latest changes
log "Fetching latest changes..."
git fetch origin main --quiet

# Check if we're behind
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [[ "$LOCAL" != "$REMOTE" ]]; then
    log "Updates available! Pulling changes..."
    
    # Stash any local changes
    if [[ -n $(git status --porcelain) ]]; then
        log "Stashing local changes..."
        git stash push -m "Auto-stash before pull $(date +%s)"
    fi
    
    # Pull latest changes
    git pull origin main --quiet
    
    # Run install script if it was updated
    if git diff --name-only HEAD@{1} HEAD | grep -q "install.sh"; then
        log "install.sh updated, running it..."
        ./install.sh >> "$LOG_FILE" 2>&1
    fi
    
    # Source bashrc if it was updated
    if git diff --name-only HEAD@{1} HEAD | grep -q "bashrc"; then
        log "bashrc updated, sourcing it..."
        source "$HOME/.bashrc"
    fi
    
    log "Sync completed successfully!"
else
    log "Already up to date"
fi