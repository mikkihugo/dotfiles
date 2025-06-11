#!/bin/bash
# Guardian remote backup
# Stores and restores guardian binaries to/from GitHub Gists
# This allows recovery even if the local machine is compromised

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"
GUARDIAN_BACKUP="${HOME}/.dotfiles/.guardian-shell/shell-guardian.bin"
CONFIG_FILE="${HOME}/.config/guardian/remote-config"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Check GitHub CLI availability
if ! command -v gh &>/dev/null; then
    echo -e "${RED}❌ GitHub CLI not available${NC}"
    echo -e "${YELLOW}💡 Install with: sudo apt install gh${NC}"
    exit 1
fi

# Check GitHub auth
if ! gh auth status &>/dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub${NC}"
    echo -e "${YELLOW}💡 Run: gh auth login${NC}"
    exit 1
fi

# Ensure config directory exists
mkdir -p "${HOME}/.config/guardian"

# Initialize remote backup
initialize() {
    echo -e "${BLUE}🔧 Initializing remote backup...${NC}"
    
    # Check if already initialized
    if [ -f "$CONFIG_FILE" ] && [ -n "$(cat "$CONFIG_FILE" 2>/dev/null)" ]; then
        echo -e "${YELLOW}⚠️ Remote backup already initialized${NC}"
        echo -e "${YELLOW}💡 Use 'update' to update backup${NC}"
        return 1
    fi
    
    # Verify binary exists
    if [ ! -f "$GUARDIAN_BIN" ] && [ ! -f "$GUARDIAN_BACKUP" ]; then
        echo -e "${RED}❌ No guardian binary found to backup${NC}"
        exit 1
    fi
    
    # Choose source binary
    if [ -f "$GUARDIAN_BIN" ]; then
        SOURCE="$GUARDIAN_BIN"
    else
        SOURCE="$GUARDIAN_BACKUP"
    fi
    
    # Calculate checksum
    CHECKSUM=$(sha256sum "$SOURCE" | awk '{print $1}')
    
    # Encode binary to base64
    base64 "$SOURCE" > "$TEMP_DIR/guardian.b64"
    
    # Create gist description
    HOSTNAME=$(hostname)
    DESCRIPTION="Shell Guardian backup for $HOSTNAME (DO NOT DELETE)"
    
    # Create gist
    echo -e "${YELLOW}📤 Creating private gist...${NC}"
    GIST_URL=$(gh gist create --private --desc "$DESCRIPTION" "$TEMP_DIR/guardian.b64" | head -n1)
    
    # Extract gist ID
    GIST_ID=$(echo "$GIST_URL" | awk -F/ '{print $NF}')
    
    # Save config
    echo "GIST_ID=$GIST_ID" > "$CONFIG_FILE"
    echo "CHECKSUM=$CHECKSUM" >> "$CONFIG_FILE"
    echo "LAST_UPDATE=$(date +%s)" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ Remote backup initialized${NC}"
    echo -e "${BLUE}📋 Gist URL: $GIST_URL${NC}"
    echo -e "${BLUE}🔑 Gist ID: $GIST_ID${NC}"
}

# Update remote backup
update() {
    echo -e "${BLUE}🔄 Updating remote backup...${NC}"
    
    # Check if initialized
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}❌ Remote backup not initialized${NC}"
        echo -e "${YELLOW}💡 Run: $0 init${NC}"
        return 1
    fi
    
    # Load config
    source "$CONFIG_FILE"
    
    # Verify binary exists
    if [ ! -f "$GUARDIAN_BIN" ] && [ ! -f "$GUARDIAN_BACKUP" ]; then
        echo -e "${RED}❌ No guardian binary found to backup${NC}"
        exit 1
    fi
    
    # Choose source binary
    if [ -f "$GUARDIAN_BIN" ]; then
        SOURCE="$GUARDIAN_BIN"
    else
        SOURCE="$GUARDIAN_BACKUP"
    fi
    
    # Calculate checksum
    CHECKSUM=$(sha256sum "$SOURCE" | awk '{print $1}')
    
    # Check if changed
    if [ "$CHECKSUM" = "$CHECKSUM" ]; then
        echo -e "${YELLOW}⚠️ Binary unchanged, no update needed${NC}"
        return 0
    fi
    
    # Encode binary to base64
    base64 "$SOURCE" > "$TEMP_DIR/guardian.b64"
    
    # Update gist
    echo -e "${YELLOW}📤 Updating private gist...${NC}"
    gh gist edit "$GIST_ID" "$TEMP_DIR/guardian.b64"
    
    # Update config
    echo "GIST_ID=$GIST_ID" > "$CONFIG_FILE"
    echo "CHECKSUM=$CHECKSUM" >> "$CONFIG_FILE"
    echo "LAST_UPDATE=$(date +%s)" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ Remote backup updated${NC}"
}

# Restore from remote backup
restore() {
    echo -e "${BLUE}🔄 Restoring from remote backup...${NC}"
    
    # Check if initialized
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}❌ Remote backup not initialized${NC}"
        echo -e "${YELLOW}💡 Run: $0 init${NC}"
        return 1
    fi
    
    # Load config
    source "$CONFIG_FILE"
    
    # Create temp file
    echo -e "${YELLOW}📥 Downloading from gist...${NC}"
    gh gist view "$GIST_ID" > "$TEMP_DIR/guardian.b64"
    
    # Decode from base64
    base64 -d "$TEMP_DIR/guardian.b64" > "$TEMP_DIR/guardian"
    chmod +x "$TEMP_DIR/guardian"
    
    # Calculate checksum
    RESTORED_CHECKSUM=$(sha256sum "$TEMP_DIR/guardian" | awk '{print $1}')
    
    # Verify checksum
    if [ "$RESTORED_CHECKSUM" != "$CHECKSUM" ]; then
        echo -e "${RED}❌ Checksum verification failed!${NC}"
        echo -e "${YELLOW}💡 Expected: $CHECKSUM${NC}"
        echo -e "${YELLOW}💡 Got: $RESTORED_CHECKSUM${NC}"
        echo -e "${YELLOW}⚠️ The backup may be corrupted or tampered with${NC}"
        
        # Ask for confirmation
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${RED}❌ Restoration aborted${NC}"
            return 1
        fi
    fi
    
    # Install binary
    echo -e "${YELLOW}📦 Installing guardian binary...${NC}"
    mkdir -p "$HOME/.local/bin" "$HOME/.dotfiles/.guardian-shell"
    cp "$TEMP_DIR/guardian" "$GUARDIAN_BIN"
    cp "$TEMP_DIR/guardian" "$GUARDIAN_BACKUP"
    chmod +x "$GUARDIAN_BIN" "$GUARDIAN_BACKUP"
    
    echo -e "${GREEN}✅ Guardian restored from remote backup${NC}"
}

# Show status
status() {
    echo -e "${BLUE}📊 Guardian remote backup status${NC}"
    
    # Check if initialized
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}⚠️ Remote backup not initialized${NC}"
        echo -e "${YELLOW}💡 Run: $0 init${NC}"
        return 1
    fi
    
    # Load config
    source "$CONFIG_FILE"
    
    # Calculate age
    CURRENT_TIME=$(date +%s)
    AGE=$((CURRENT_TIME - LAST_UPDATE))
    DAYS=$((AGE / 86400))
    
    # Show info
    echo -e "${YELLOW}📋 Gist ID: $GIST_ID${NC}"
    echo -e "${YELLOW}📋 Last update: $DAYS days ago${NC}"
    echo -e "${YELLOW}📋 Checksum: $CHECKSUM${NC}"
    
    # Check local binaries
    if [ -f "$GUARDIAN_BIN" ]; then
        LOCAL_CHECKSUM=$(sha256sum "$GUARDIAN_BIN" | awk '{print $1}')
        if [ "$LOCAL_CHECKSUM" = "$CHECKSUM" ]; then
            echo -e "${GREEN}✅ Local binary matches remote backup${NC}"
        else
            echo -e "${RED}❌ Local binary differs from remote backup${NC}"
        fi
    else
        echo -e "${RED}❌ Local binary missing${NC}"
    fi
    
    if [ -f "$GUARDIAN_BACKUP" ]; then
        BACKUP_CHECKSUM=$(sha256sum "$GUARDIAN_BACKUP" | awk '{print $1}')
        if [ "$BACKUP_CHECKSUM" = "$CHECKSUM" ]; then
            echo -e "${GREEN}✅ Backup binary matches remote backup${NC}"
        else
            echo -e "${RED}❌ Backup binary differs from remote backup${NC}"
        fi
    else
        echo -e "${RED}❌ Backup binary missing${NC}"
    fi
}

# Parse command
case "$1" in
    init|initialize)
        initialize
        ;;
    update)
        update
        ;;
    restore)
        restore
        ;;
    status)
        status
        ;;
    *)
        echo -e "${BLUE}Guardian Remote Backup${NC}"
        echo -e "${YELLOW}Usage:${NC}"
        echo "  $0 init     - Initialize remote backup"
        echo "  $0 update   - Update remote backup"
        echo "  $0 restore  - Restore from remote backup"
        echo "  $0 status   - Show backup status"
        ;;
esac