#!/bin/bash
# Guardian All-in-One Security Script
# Comprehensive protection, verification, and recovery

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
SCRIPTS_DIR="${HOME}/.dotfiles/.scripts/guardian"

# Header
echo -e "${BLUE}🛡️  Guardian Security System ${NC}"
echo -e "${BLUE}═══════════════════════════${NC}"

# Verify system
verify() {
  echo -e "${BLUE}🔍 Performing complete system verification...${NC}"
  
  local issues=0
  
  # Check primary binary
  if [ -f "${GUARDIAN_BIN}" ]; then
    echo -e "${GREEN}✅ Primary binary exists${NC}"
    
    # Check if executable
    if [ -x "${GUARDIAN_BIN}" ]; then
      echo -e "${GREEN}✅ Primary binary is executable${NC}"
    else
      echo -e "${RED}❌ Primary binary is not executable${NC}"
      chmod +x "${GUARDIAN_BIN}"
      echo -e "${YELLOW}🔧 Fixed permissions${NC}"
      issues=$((issues + 1))
    fi
    
    # Run integrity check if verify-guardian exists
    if command -v verify-guardian &>/dev/null; then
      echo -e "${YELLOW}🔍 Running binary verification...${NC}"
      if verify-guardian &>/dev/null; then
        echo -e "${GREEN}✅ Binary verification passed${NC}"
      else
        echo -e "${RED}❌ Binary verification failed${NC}"
        issues=$((issues + 1))
      fi
    fi
  else
    echo -e "${RED}❌ Primary binary missing${NC}"
    issues=$((issues + 1))
  }
  
  # Check backup binary
  if [ -f "${GUARDIAN_BACKUP}" ]; then
    echo -e "${GREEN}✅ Backup binary exists${NC}"
  else
    echo -e "${RED}❌ Backup binary missing${NC}"
    issues=$((issues + 1))
  fi
  
  # Check hardlinks if script exists
  if [ -f "${SCRIPTS_DIR}/guardian-hardlink.sh" ]; then
    echo -e "${YELLOW}🔍 Checking hardlinks...${NC}"
    ${SCRIPTS_DIR}/guardian-hardlink.sh verify
    
    # Consider hardlink verification an issue if it fails
    if [ $? -ne 0 ]; then
      issues=$((issues + 1))
    fi
  fi
  
  # Return result
  if [ $issues -eq 0 ]; then
    echo -e "${GREEN}✅ All verifications passed${NC}"
    return 0
  else
    echo -e "${RED}❌ Found $issues issues${NC}"
    return 1
  fi
}

# Restore guardian from any available source
restore() {
  echo -e "${BLUE}🔄 Attempting to restore guardian...${NC}"
  
  # Check if primary already exists and is valid
  if [ -f "${GUARDIAN_BIN}" ] && [ -x "${GUARDIAN_BIN}" ]; then
    if command -v verify-guardian &>/dev/null && verify-guardian &>/dev/null; then
      echo -e "${GREEN}✅ Primary binary already valid${NC}"
      return 0
    fi
  fi
  
  # Try restoring from backup
  if [ -f "${GUARDIAN_BACKUP}" ]; then
    echo -e "${YELLOW}🔄 Restoring from backup...${NC}"
    mkdir -p "$(dirname "${GUARDIAN_BIN}")"
    cp "${GUARDIAN_BACKUP}" "${GUARDIAN_BIN}"
    chmod +x "${GUARDIAN_BIN}"
    echo -e "${GREEN}✅ Restored from backup${NC}"
    return 0
  fi
  
  # Try restoring from hardlinks
  if [ -f "${SCRIPTS_DIR}/guardian-hardlink.sh" ]; then
    echo -e "${YELLOW}🔄 Attempting to restore from hardlinks...${NC}"
    ${SCRIPTS_DIR}/guardian-hardlink.sh find
    
    if [ $? -eq 0 ] && [ -f "${GUARDIAN_BIN}" ]; then
      echo -e "${GREEN}✅ Restored from hardlinks${NC}"
      return 0
    fi
  fi
  
  # Try restoring from remote backup
  if [ -f "${SCRIPTS_DIR}/guardian-remote-backup.sh" ]; then
    echo -e "${YELLOW}🔄 Attempting to restore from remote backup...${NC}"
    ${SCRIPTS_DIR}/guardian-remote-backup.sh restore
    
    if [ $? -eq 0 ] && [ -f "${GUARDIAN_BIN}" ]; then
      echo -e "${GREEN}✅ Restored from remote backup${NC}"
      return 0
    fi
  fi
  
  # Try restoring from secure storage
  if [ -f "${SCRIPTS_DIR}/secure-storage.sh" ]; then
    echo -e "${YELLOW}🔄 Attempting to restore from secure storage...${NC}"
    ${SCRIPTS_DIR}/secure-storage.sh open && ${SCRIPTS_DIR}/secure-storage.sh restore
    
    if [ $? -eq 0 ] && [ -f "${GUARDIAN_BIN}" ]; then
      ${SCRIPTS_DIR}/secure-storage.sh close
      echo -e "${GREEN}✅ Restored from secure storage${NC}"
      return 0
    fi
    
    # Close storage if opened
    ${SCRIPTS_DIR}/secure-storage.sh close
  fi
  
  # If all else fails, try emergency recovery
  if [ -f "${HOME}/.dotfiles/.guardian-shell/emergency-recovery.sh" ]; then
    echo -e "${RED}❌ All restoration methods failed${NC}"
    echo -e "${YELLOW}⚠️ Please run emergency recovery:${NC}"
    echo -e "${YELLOW}   bash ${HOME}/.dotfiles/.guardian-shell/emergency-recovery.sh${NC}"
    return 1
  fi
  
  echo -e "${RED}❌ All restoration methods failed${NC}"
  return 1
}

# Apply all protection mechanisms
protect() {
  echo -e "${BLUE}🔒 Applying all protection mechanisms...${NC}"
  
  # Ensure binary exists
  if [ ! -f "${GUARDIAN_BIN}" ]; then
    echo -e "${RED}❌ Cannot protect: guardian binary missing${NC}"
    return 1
  fi
  
  # Create backup
  echo -e "${YELLOW}📦 Creating backup...${NC}"
  mkdir -p "$(dirname "${GUARDIAN_BACKUP}")"
  cp "${GUARDIAN_BIN}" "${GUARDIAN_BACKUP}"
  chmod +x "${GUARDIAN_BACKUP}"
  
  # Apply immutable attribute if available
  if command -v chattr &>/dev/null; then
    echo -e "${YELLOW}🔒 Setting immutable attribute...${NC}"
    chattr +i "${GUARDIAN_BIN}" 2>/dev/null || sudo chattr +i "${GUARDIAN_BIN}" 2>/dev/null || {
      echo -e "${YELLOW}⚠️ Could not set immutable attribute${NC}"
    }
    
    chattr +i "${GUARDIAN_BACKUP}" 2>/dev/null || sudo chattr +i "${GUARDIAN_BACKUP}" 2>/dev/null || {
      echo -e "${YELLOW}⚠️ Could not set immutable attribute on backup${NC}"
    }
  fi
  
  # Create hardlinks if script exists
  if [ -f "${SCRIPTS_DIR}/guardian-hardlink.sh" ]; then
    echo -e "${YELLOW}🔗 Creating hardlinks...${NC}"
    ${SCRIPTS_DIR}/guardian-hardlink.sh create
  fi
  
  # Update remote backup if script exists
  if [ -f "${SCRIPTS_DIR}/guardian-remote-backup.sh" ]; then
    echo -e "${YELLOW}☁️  Updating remote backup...${NC}"
    ${SCRIPTS_DIR}/guardian-remote-backup.sh update 2>/dev/null || {
      echo -e "${YELLOW}⚠️ Remote backup failed, trying to initialize...${NC}"
      ${SCRIPTS_DIR}/guardian-remote-backup.sh init
    }
  fi
  
  # Backup to secure storage if script exists
  if [ -f "${SCRIPTS_DIR}/secure-storage.sh" ]; then
    echo -e "${YELLOW}🔐 Backing up to secure storage...${NC}"
    ${SCRIPTS_DIR}/secure-storage.sh open && ${SCRIPTS_DIR}/secure-storage.sh backup
    ${SCRIPTS_DIR}/secure-storage.sh close
  fi
  
  echo -e "${GREEN}✅ All protection mechanisms applied${NC}"
}

# Comprehensive status
status() {
  echo -e "${BLUE}📊 Guardian Security Status${NC}"
  
  # Check binaries
  echo -e "${YELLOW}📋 Binary Status:${NC}"
  if [ -f "${GUARDIAN_BIN}" ]; then
    echo -e "  ${GREEN}✅ Primary: ${GUARDIAN_BIN}${NC}"
    
    # Check immutable flag
    if command -v lsattr &>/dev/null; then
      if lsattr "${GUARDIAN_BIN}" 2>/dev/null | grep -q "i"; then
        echo -e "  ${GREEN}✅ Immutable: Yes${NC}"
      else
        echo -e "  ${RED}❌ Immutable: No${NC}"
      fi
    fi
    
    # Check verification if available
    if command -v verify-guardian &>/dev/null; then
      if verify-guardian &>/dev/null; then
        echo -e "  ${GREEN}✅ Verification: Passed${NC}"
      else
        echo -e "  ${RED}❌ Verification: Failed${NC}"
      fi
    fi
  else
    echo -e "  ${RED}❌ Primary: Missing${NC}"
  fi
  
  if [ -f "${GUARDIAN_BACKUP}" ]; then
    echo -e "  ${GREEN}✅ Backup: ${GUARDIAN_BACKUP}${NC}"
  else
    echo -e "  ${RED}❌ Backup: Missing${NC}"
  fi
  
  # Check hardlinks if script exists
  if [ -f "${SCRIPTS_DIR}/guardian-hardlink.sh" ]; then
    echo -e "${YELLOW}📋 Hardlink Status:${NC}"
    ${SCRIPTS_DIR}/guardian-hardlink.sh verify | grep -v "Verifying" | sed 's/^/  /'
  fi
  
  # Check remote backup if script exists
  if [ -f "${SCRIPTS_DIR}/guardian-remote-backup.sh" ]; then
    echo -e "${YELLOW}📋 Remote Backup Status:${NC}"
    ${SCRIPTS_DIR}/guardian-remote-backup.sh status 2>/dev/null | grep -v "status" | sed 's/^/  /' || {
      echo -e "  ${YELLOW}⚠️ Remote backup not initialized${NC}"
    }
  fi
  
  # Check secure storage if script exists
  if [ -f "${SCRIPTS_DIR}/secure-storage.sh" ]; then
    echo -e "${YELLOW}📋 Secure Storage Status:${NC}"
    ${SCRIPTS_DIR}/secure-storage.sh status 2>/dev/null | grep -v "status" | sed 's/^/  /' || {
      echo -e "  ${YELLOW}⚠️ Secure storage not initialized${NC}"
    }
  fi
}

# Main function
case "$1" in
  verify)
    verify
    ;;
  restore)
    restore
    ;;
  protect)
    protect
    ;;
  status)
    status
    ;;
  all)
    verify || restore
    protect
    status
    ;;
  *)
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 verify   - Check guardian integrity"
    echo "  $0 restore  - Restore guardian from any available source"
    echo "  $0 protect  - Apply all protection mechanisms"
    echo "  $0 status   - Show comprehensive status"
    echo "  $0 all      - Verify, restore if needed, protect, and show status"
    ;;
esac