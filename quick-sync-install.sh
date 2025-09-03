#!/bin/bash
# Quick Environment Sync Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/mikkihugo/dotfiles/main/quick-sync-install.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

echo -e "${CYAN}🔄 Quick Environment Sync Setup${NC}"
echo "================================="
echo ""

# Check if dotfiles already exist
if [[ -d "$HOME/.dotfiles" ]]; then
    log "Dotfiles directory found, updating..."
    cd "$HOME/.dotfiles"
    git pull origin main
    success "Repository updated"
else
    log "Cloning dotfiles repository..."
    git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles
    success "Repository cloned"
fi

# Run bootstrap for environment sync
log "Running environment sync bootstrap..."
exec "$HOME/.dotfiles/bootstrap-new-machine.sh"