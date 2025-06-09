#!/bin/bash

# Auto-sync ALL configs: dotfiles, team gist, personal gist
# Runs on login and via cron for complete synchronization

set -e

LOG_FILE="$HOME/.dotfiles/logs/auto-sync-all.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to sync with error handling
safe_sync() {
    local name="$1"
    local command="$2"
    
    log "🔄 Syncing $name..."
    if eval "$command" 2>&1 | tee -a "$LOG_FILE"; then
        log "✅ $name synced"
        return 0
    else
        log "❌ $name sync failed"
        return 1
    fi
}

# 1. DOTFILES - Pull latest from GitHub
safe_sync "dotfiles" "cd ~/.dotfiles && git pull --quiet"

# 2. TEAM CONFIG - Pull from team gist
if [ -n "$TEAM_GIST_ID" ]; then
    safe_sync "team config" "gh gist view '$TEAM_GIST_ID' -f team-config.sh > ~/.team-config.tmp && mv ~/.team-config.tmp ~/.team-config"
    source ~/.team-config
fi

# 3. PERSONAL TOKENS - Pull from personal gist
if [ -n "$PERSONAL_GIST_ID" ]; then
    safe_sync "personal tokens" "gh gist view '$PERSONAL_GIST_ID' -f .env_tokens > ~/.env_tokens.tmp && mv ~/.env_tokens.tmp ~/.env_tokens"
fi

# 4. TABBY CONFIG - Update with latest gateway info
if [ -f ~/.config/tabby/config.yaml ] && [ -n "$TABBY_GATEWAY_URL" ]; then
    log "🔧 Updating Tabby gateway config..."
    ~/.dotfiles/.scripts/tabby-gateway-config.sh update >/dev/null 2>&1
fi

# 5. SSH HOSTS - Sync from team gist if configured
if [ -n "$SSH_HOSTS_GIST_ID" ]; then
    safe_sync "SSH hosts" "~/.dotfiles/.scripts/tabby-sync.sh pull"
fi

# 6. GATEWAY STATUS - Check if this server runs gateway
if docker ps | grep -q "tabby-gateway" 2>/dev/null; then
    log "🌐 Gateway running on this server"
    ~/.dotfiles/.scripts/gateway-status.sh update >/dev/null 2>&1
fi

log "🎉 All syncs complete"

# Return success only if critical syncs worked
[ -f ~/.team-config ] && [ -f ~/.env_tokens ]