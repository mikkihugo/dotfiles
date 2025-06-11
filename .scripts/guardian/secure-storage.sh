#!/bin/bash
# Secure storage for guardian binaries
# Uses encrypted storage to keep guardian binaries safe

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"
ENCRYPTED_DIR="${HOME}/.guardian-secure"
ENCRYPTED_FILE="${ENCRYPTED_DIR}/guardian.enc"
MOUNT_POINT="${ENCRYPTED_DIR}/secure"
SIZE_MB=10

# Check dependencies
check_dependencies() {
  local missing=0
  
  if ! command -v cryptsetup &>/dev/null; then
    echo -e "${RED}❌ cryptsetup not found${NC}"
    echo -e "${YELLOW}💡 Install with: sudo apt install cryptsetup${NC}"
    missing=1
  fi
  
  if ! command -v dd &>/dev/null; then
    echo -e "${RED}❌ dd not found${NC}"
    missing=1
  fi
  
  if ! command -v mkfs.ext4 &>/dev/null; then
    echo -e "${RED}❌ mkfs.ext4 not found${NC}"
    echo -e "${YELLOW}💡 Install with: sudo apt install e2fsprogs${NC}"
    missing=1
  fi
  
  return $missing
}

# Initialize secure storage
initialize() {
  echo -e "${BLUE}🔒 Initializing secure storage...${NC}"
  
  # Check dependencies
  check_dependencies || return 1
  
  # Create directory
  mkdir -p "${ENCRYPTED_DIR}" "${MOUNT_POINT}"
  
  # Check if already initialized
  if [ -f "${ENCRYPTED_FILE}" ]; then
    echo -e "${YELLOW}⚠️ Secure storage already initialized${NC}"
    return 0
  fi
  
  # Create encrypted container
  echo -e "${YELLOW}🔧 Creating encrypted container (${SIZE_MB}MB)...${NC}"
  dd if=/dev/urandom of="${ENCRYPTED_FILE}" bs=1M count=${SIZE_MB} status=progress
  
  # Set up encryption
  echo -e "${YELLOW}🔑 Setting up encryption (enter a strong passphrase)...${NC}"
  cryptsetup -y luksFormat "${ENCRYPTED_FILE}"
  
  # Open container
  echo -e "${YELLOW}🔓 Opening container (enter passphrase)...${NC}"
  cryptsetup open "${ENCRYPTED_FILE}" guardian-secure
  
  # Format filesystem
  echo -e "${YELLOW}📦 Formatting filesystem...${NC}"
  mkfs.ext4 -L guardian-secure /dev/mapper/guardian-secure
  
  # Mount filesystem
  mount /dev/mapper/guardian-secure "${MOUNT_POINT}"
  
  # Create directory structure
  mkdir -p "${MOUNT_POINT}/bin" "${MOUNT_POINT}/backup" "${MOUNT_POINT}/recovery"
  
  # Copy guardian binary if it exists
  if [ -f "${GUARDIAN_BIN}" ]; then
    cp "${GUARDIAN_BIN}" "${MOUNT_POINT}/bin/shell-guardian"
    cp "${GUARDIAN_BIN}" "${MOUNT_POINT}/backup/shell-guardian.$(date +%Y%m%d)"
    echo -e "${GREEN}✅ Copied guardian binary to secure storage${NC}"
  fi
  
  # Create recovery script
  cat > "${MOUNT_POINT}/recovery/recover.sh" << 'EOF'
#!/bin/bash
# Guardian recovery script

# Copy guardian binary from secure storage
cp "$(dirname "$0")/../bin/shell-guardian" "${HOME}/.local/bin/shell-guardian"
chmod 755 "${HOME}/.local/bin/shell-guardian"
echo "✅ Guardian binary restored from secure storage"
EOF
  chmod +x "${MOUNT_POINT}/recovery/recover.sh"
  
  # Unmount and close
  umount "${MOUNT_POINT}"
  cryptsetup close guardian-secure
  
  echo -e "${GREEN}✅ Secure storage initialized${NC}"
  echo -e "${YELLOW}💡 To open: $0 open${NC}"
}

# Open secure storage
open_storage() {
  echo -e "${BLUE}🔓 Opening secure storage...${NC}"
  
  # Check if initialized
  if [ ! -f "${ENCRYPTED_FILE}" ]; then
    echo -e "${RED}❌ Secure storage not initialized${NC}"
    echo -e "${YELLOW}💡 Run: $0 init${NC}"
    return 1
  fi
  
  # Check if already mounted
  if mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${YELLOW}⚠️ Secure storage already mounted${NC}"
    return 0
  fi
  
  # Open container
  echo -e "${YELLOW}🔑 Enter passphrase to unlock...${NC}"
  cryptsetup open "${ENCRYPTED_FILE}" guardian-secure
  
  # Mount filesystem
  mkdir -p "${MOUNT_POINT}"
  mount /dev/mapper/guardian-secure "${MOUNT_POINT}"
  
  echo -e "${GREEN}✅ Secure storage opened${NC}"
  echo -e "${YELLOW}📂 Mounted at: ${MOUNT_POINT}${NC}"
}

# Close secure storage
close_storage() {
  echo -e "${BLUE}🔒 Closing secure storage...${NC}"
  
  # Check if mounted
  if ! mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${YELLOW}⚠️ Secure storage not mounted${NC}"
    
    # Check if mapper exists anyway
    if [ -e "/dev/mapper/guardian-secure" ]; then
      cryptsetup close guardian-secure
      echo -e "${GREEN}✅ Cleaned up stale mapper${NC}"
    fi
    
    return 0
  fi
  
  # Unmount and close
  umount "${MOUNT_POINT}"
  cryptsetup close guardian-secure
  
  echo -e "${GREEN}✅ Secure storage closed${NC}"
}

# Backup guardian binary to secure storage
backup() {
  echo -e "${BLUE}📦 Backing up guardian binary...${NC}"
  
  # Check if storage is open
  if ! mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${YELLOW}⚠️ Secure storage not mounted${NC}"
    echo -e "${YELLOW}💡 Run: $0 open${NC}"
    return 1
  fi
  
  # Check if guardian binary exists
  if [ ! -f "${GUARDIAN_BIN}" ]; then
    echo -e "${RED}❌ Guardian binary not found: ${GUARDIAN_BIN}${NC}"
    return 1
  fi
  
  # Copy to secure storage
  cp "${GUARDIAN_BIN}" "${MOUNT_POINT}/bin/shell-guardian"
  cp "${GUARDIAN_BIN}" "${MOUNT_POINT}/backup/shell-guardian.$(date +%Y%m%d)"
  
  echo -e "${GREEN}✅ Guardian binary backed up to secure storage${NC}"
}

# Restore guardian binary from secure storage
restore() {
  echo -e "${BLUE}🔄 Restoring guardian binary...${NC}"
  
  # Check if storage is open
  if ! mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${YELLOW}⚠️ Secure storage not mounted${NC}"
    echo -e "${YELLOW}💡 Run: $0 open${NC}"
    return 1
  fi
  
  # Check if guardian binary exists in secure storage
  if [ ! -f "${MOUNT_POINT}/bin/shell-guardian" ]; then
    echo -e "${RED}❌ Guardian binary not found in secure storage${NC}"
    return 1
  fi
  
  # Create directory if it doesn't exist
  mkdir -p "$(dirname "${GUARDIAN_BIN}")"
  
  # Copy from secure storage
  cp "${MOUNT_POINT}/bin/shell-guardian" "${GUARDIAN_BIN}"
  chmod 755 "${GUARDIAN_BIN}"
  
  echo -e "${GREEN}✅ Guardian binary restored from secure storage${NC}"
}

# Show status
status() {
  echo -e "${BLUE}📊 Secure storage status${NC}"
  
  # Check if initialized
  if [ ! -f "${ENCRYPTED_FILE}" ]; then
    echo -e "${YELLOW}⚠️ Secure storage not initialized${NC}"
    echo -e "${YELLOW}💡 Run: $0 init${NC}"
    return 1
  fi
  
  # Check if mounted
  if mountpoint -q "${MOUNT_POINT}"; then
    echo -e "${GREEN}✅ Secure storage is mounted${NC}"
    echo -e "${YELLOW}📂 Mount point: ${MOUNT_POINT}${NC}"
    
    # Check available space
    df -h "${MOUNT_POINT}" | grep -v Filesystem
    
    # Check contents
    echo -e "${YELLOW}📋 Backup versions:${NC}"
    ls -la "${MOUNT_POINT}/backup/" | grep -v "^total" | grep -v "^d"
  else
    echo -e "${YELLOW}⚠️ Secure storage is not mounted${NC}"
    echo -e "${YELLOW}💡 Run: $0 open${NC}"
  fi
  
  # Check container size
  if [ -f "${ENCRYPTED_FILE}" ]; then
    SIZE=$(du -h "${ENCRYPTED_FILE}" | awk '{print $1}')
    echo -e "${YELLOW}📋 Container size: ${SIZE}${NC}"
  fi
}

# Parse command
case "$1" in
  init|initialize)
    initialize
    ;;
  open)
    open_storage
    ;;
  close)
    close_storage
    ;;
  backup)
    backup
    ;;
  restore)
    restore
    ;;
  status)
    status
    ;;
  *)
    echo -e "${BLUE}Guardian Secure Storage${NC}"
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 init     - Initialize secure storage"
    echo "  $0 open     - Open secure storage"
    echo "  $0 close    - Close secure storage"
    echo "  $0 backup   - Backup guardian binary"
    echo "  $0 restore  - Restore guardian binary"
    echo "  $0 status   - Show storage status"
    ;;
esac