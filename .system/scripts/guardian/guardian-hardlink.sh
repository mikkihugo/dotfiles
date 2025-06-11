#!/bin/bash
# Guardian hardlink protection script
# Creates multiple hardlinks to the guardian binary across the filesystem
# This ensures that even if one copy is deleted, others remain available

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Guardian binary
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"

# Hardlink locations - places to store additional copies
# Choose locations that are unlikely to be accidentally deleted
HARDLINK_LOCATIONS=(
  "${HOME}/.config/guardian/bin/shell-guardian"
  "${HOME}/.cache/.guardian-backup"
  "${HOME}/.local/share/guardian/shell-guardian"
  "${HOME}/.ssh/.guardian"
  "${HOME}/.gnupg/.guardian-binary"
)

# Create hardlinks
create_hardlinks() {
  echo -e "${BLUE}🔗 Creating guardian hardlinks...${NC}"
  
  # Check if source exists
  if [ ! -f "$GUARDIAN_BIN" ]; then
    echo -e "${RED}❌ Guardian binary not found: $GUARDIAN_BIN${NC}"
    exit 1
  fi
  
  # Get source inode for verification
  SOURCE_INODE=$(stat -c '%i' "$GUARDIAN_BIN")
  
  # Create directories and hardlinks
  for location in "${HARDLINK_LOCATIONS[@]}"; do
    dir=$(dirname "$location")
    mkdir -p "$dir"
    
    # Create hardlink if it doesn't exist
    if [ ! -f "$location" ]; then
      ln "$GUARDIAN_BIN" "$location" 2>/dev/null || {
        # If hardlink fails (e.g., across filesystems), copy instead
        cp "$GUARDIAN_BIN" "$location"
        echo -e "${YELLOW}⚠️ Created copy instead of hardlink: $location${NC}"
        continue
      }
      echo -e "${GREEN}✅ Created hardlink: $location${NC}"
    else
      # Check if existing file is a hardlink to our binary
      LINK_INODE=$(stat -c '%i' "$location")
      if [ "$LINK_INODE" -eq "$SOURCE_INODE" ]; then
        echo -e "${GREEN}✅ Hardlink exists: $location${NC}"
      else
        # Replace with new hardlink
        rm "$location"
        ln "$GUARDIAN_BIN" "$location" 2>/dev/null || cp "$GUARDIAN_BIN" "$location"
        echo -e "${YELLOW}🔄 Updated hardlink: $location${NC}"
      fi
    fi
    
    # Set permissions
    chmod 755 "$location"
  done
}

# Verify hardlinks
verify_hardlinks() {
  echo -e "${BLUE}🔍 Verifying guardian hardlinks...${NC}"
  
  # Check if source exists
  if [ ! -f "$GUARDIAN_BIN" ]; then
    echo -e "${RED}❌ Guardian binary not found: $GUARDIAN_BIN${NC}"
    exit 1
  fi
  
  # Get source checksum and inode
  SOURCE_CHECKSUM=$(sha256sum "$GUARDIAN_BIN" | awk '{print $1}')
  SOURCE_INODE=$(stat -c '%i' "$GUARDIAN_BIN")
  
  # Check each location
  for location in "${HARDLINK_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
      # Get hardlink checksum and inode
      LINK_CHECKSUM=$(sha256sum "$location" | awk '{print $1}')
      LINK_INODE=$(stat -c '%i' "$location")
      
      # Check if hardlink is valid
      if [ "$LINK_INODE" -eq "$SOURCE_INODE" ]; then
        echo -e "${GREEN}✅ Valid hardlink: $location${NC}"
      elif [ "$LINK_CHECKSUM" = "$SOURCE_CHECKSUM" ]; then
        echo -e "${YELLOW}⚠️ Same content but not hardlinked: $location${NC}"
      else
        echo -e "${RED}❌ Invalid copy: $location${NC}"
      fi
    else
      echo -e "${RED}❌ Missing hardlink: $location${NC}"
    fi
  done
}

# Find guardian binary from hardlinks
find_guardian() {
  echo -e "${BLUE}🔍 Searching for guardian binary...${NC}"
  
  # Try primary location first
  if [ -f "$GUARDIAN_BIN" ] && [ -x "$GUARDIAN_BIN" ]; then
    echo -e "${GREEN}✅ Found primary guardian: $GUARDIAN_BIN${NC}"
    return 0
  fi
  
  # Check hardlink locations
  for location in "${HARDLINK_LOCATIONS[@]}"; do
    if [ -f "$location" ] && [ -x "$location" ]; then
      echo -e "${GREEN}✅ Found guardian at: $location${NC}"
      
      # Restore primary location
      mkdir -p "$(dirname "$GUARDIAN_BIN")"
      cp "$location" "$GUARDIAN_BIN"
      chmod 755 "$GUARDIAN_BIN"
      
      echo -e "${GREEN}✅ Restored guardian to: $GUARDIAN_BIN${NC}"
      return 0
    fi
  done
  
  echo -e "${RED}❌ Guardian binary not found in any location${NC}"
  return 1
}

# Main function
case "$1" in
  create)
    create_hardlinks
    ;;
  verify)
    verify_hardlinks
    ;;
  find)
    find_guardian
    ;;
  *)
    echo -e "${BLUE}Guardian Hardlink Protection${NC}"
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 create  - Create hardlinks across filesystem"
    echo "  $0 verify  - Verify hardlink integrity"
    echo "  $0 find    - Find and restore guardian binary"
    ;;
esac