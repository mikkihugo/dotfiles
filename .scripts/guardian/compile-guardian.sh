#!/bin/bash
# Hardened guardian compilation script
# This compiles the Rust guardian with maximal optimization and security

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Compiling hardened shell guardian...${NC}"

# Paths
GUARDIAN_DIR="${HOME}/.dotfiles/.guardian-shell"
GUARDIAN_RS="${GUARDIAN_DIR}/shell-guardian.rs"
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"
GUARDIAN_BACKUP="${GUARDIAN_DIR}/shell-guardian.bin"
BIN_DIR="${HOME}/.local/bin"

# Create bin directory if it doesn't exist
mkdir -p "${BIN_DIR}"

# Check for rustc
if ! command -v rustc &>/dev/null; then
    echo -e "${RED}❌ Rust compiler not found${NC}"
    echo -e "${YELLOW}💡 Using pre-compiled binary or bash fallback${NC}"
    exit 1
fi

# Check if source exists
if [ ! -f "${GUARDIAN_RS}" ]; then
    echo -e "${RED}❌ Source file not found: ${GUARDIAN_RS}${NC}"
    exit 1
fi

# Create temporary working directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Copy source to temp dir
cp "${GUARDIAN_RS}" "${TEMP_DIR}/shell-guardian.rs"

# Calculate checksum of source
SOURCE_CHECKSUM=$(sha256sum "${TEMP_DIR}/shell-guardian.rs" | awk '{print $1}')
echo -e "${YELLOW}📋 Source checksum: ${SOURCE_CHECKSUM}${NC}"

# Get current timestamp
BUILD_TIMESTAMP=$(date +%s)

# Update checksum and timestamp placeholders in source
sed -i "s/CHECKSUM_PLACEHOLDER/${SOURCE_CHECKSUM}/" "${TEMP_DIR}/shell-guardian.rs"
sed -i "s/TIMESTAMP_PLACEHOLDER/${BUILD_TIMESTAMP}/" "${TEMP_DIR}/shell-guardian.rs"

# Compile with maximum optimization
echo -e "${YELLOW}🔧 Compiling with maximum optimization...${NC}"
rustc -O -C opt-level=3 -C lto=fat -C codegen-units=1 -C panic=abort \
    "${TEMP_DIR}/shell-guardian.rs" -o "${TEMP_DIR}/shell-guardian"

if [ ! -f "${TEMP_DIR}/shell-guardian" ]; then
    echo -e "${RED}❌ Compilation failed${NC}"
    exit 1
fi

# Calculate binary checksum
BINARY_CHECKSUM=$(sha256sum "${TEMP_DIR}/shell-guardian" | awk '{print $1}')
echo -e "${YELLOW}📋 Binary checksum: ${BINARY_CHECKSUM}${NC}"

# Create verification script
echo -e "${YELLOW}📝 Creating verification script...${NC}"
cat > "${TEMP_DIR}/verify-guardian.sh" << EOF
#!/bin/bash
# Shell Guardian verification script
# This verifies the integrity of the guardian binary

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
GUARDIAN_BIN="${GUARDIAN_BIN}"
GUARDIAN_BACKUP="${GUARDIAN_BACKUP}"
EMERGENCY_SCRIPT="${HOME}/.dotfiles/.guardian-shell/emergency-recovery.sh"

# Expected checksum
EXPECTED="${BINARY_CHECKSUM}"
BUILD_TIME="${BUILD_TIMESTAMP}"

# Check primary binary
check_primary() {
  echo -e "${BLUE}🔍 Checking primary guardian binary...${NC}"
  
  # Check if binary exists
  if [ ! -f "${GUARDIAN_BIN}" ]; then
    echo -e "${RED}❌ Primary binary missing!${NC}"
    return 1
  fi
  
  # Calculate actual checksum
  ACTUAL=\$(sha256sum "${GUARDIAN_BIN}" 2>/dev/null | awk '{print \$1}')
  
  # Check if checksums match
  if [ "\$ACTUAL" = "\$EXPECTED" ]; then
    echo -e "${GREEN}✅ Primary binary verified${NC}"
    return 0
  else
    echo -e "${RED}❌ Primary binary corrupted or tampered!${NC}"
    echo -e "${YELLOW}💡 Expected: \$EXPECTED${NC}"
    echo -e "${YELLOW}💡 Actual: \$ACTUAL${NC}"
    return 1
  fi
}

# Check backup binary
check_backup() {
  echo -e "${BLUE}🔍 Checking backup guardian binary...${NC}"
  
  # Check if backup exists
  if [ ! -f "${GUARDIAN_BACKUP}" ]; then
    echo -e "${RED}❌ Backup binary missing!${NC}"
    return 1
  fi
  
  # Calculate backup checksum
  BACKUP_CHECKSUM=\$(sha256sum "${GUARDIAN_BACKUP}" 2>/dev/null | awk '{print \$1}')
  
  # Check if checksums match
  if [ "\$BACKUP_CHECKSUM" = "\$EXPECTED" ]; then
    echo -e "${GREEN}✅ Backup binary verified${NC}"
    return 0
  else
    echo -e "${RED}❌ Backup binary corrupted or tampered!${NC}"
    return 1
  fi
}

# Check file permissions and attributes
check_permissions() {
  echo -e "${BLUE}🔍 Checking file permissions and attributes...${NC}"
  
  # Check primary binary permissions
  if [ -f "${GUARDIAN_BIN}" ]; then
    PERM=\$(stat -c "%a" "${GUARDIAN_BIN}")
    if [ "\$PERM" != "755" ] && [ "\$PERM" != "775" ]; then
      echo -e "${YELLOW}⚠️ Primary binary has incorrect permissions: \$PERM${NC}"
    fi
    
    # Check for immutable flag if lsattr is available
    if command -v lsattr &>/dev/null; then
      if ! lsattr "${GUARDIAN_BIN}" 2>/dev/null | grep -q "i"; then
        echo -e "${YELLOW}⚠️ Primary binary is not immutable${NC}"
      fi
    fi
  fi
  
  # Check backup binary permissions
  if [ -f "${GUARDIAN_BACKUP}" ]; then
    PERM=\$(stat -c "%a" "${GUARDIAN_BACKUP}")
    if [ "\$PERM" != "755" ] && [ "\$PERM" != "775" ]; then
      echo -e "${YELLOW}⚠️ Backup binary has incorrect permissions: \$PERM${NC}"
    fi
    
    # Check for immutable flag if lsattr is available
    if command -v lsattr &>/dev/null; then
      if ! lsattr "${GUARDIAN_BACKUP}" 2>/dev/null | grep -q "i"; then
        echo -e "${YELLOW}⚠️ Backup binary is not immutable${NC}"
      fi
    fi
  fi
}

# Restore from backup if needed
restore_from_backup() {
  if [ ! -f "${GUARDIAN_BACKUP}" ]; then
    echo -e "${RED}❌ Cannot restore: backup binary missing${NC}"
    return 1
  fi
  
  echo -e "${YELLOW}🔄 Restoring from backup...${NC}"
  cp "${GUARDIAN_BACKUP}" "${GUARDIAN_BIN}"
  chmod +x "${GUARDIAN_BIN}"
  
  # Verify restoration
  RESTORED_CHECKSUM=\$(sha256sum "${GUARDIAN_BIN}" 2>/dev/null | awk '{print \$1}')
  if [ "\$RESTORED_CHECKSUM" = "\$EXPECTED" ]; then
    echo -e "${GREEN}✅ Restoration successful${NC}"
    return 0
  else
    echo -e "${RED}❌ Restoration failed${NC}"
    return 1
  fi
}

# Main function
main() {
  # Verify primary binary
  PRIMARY_OK=0
  check_primary || PRIMARY_OK=1
  
  # Verify backup binary
  BACKUP_OK=0
  check_backup || BACKUP_OK=1
  
  # Check permissions
  check_permissions
  
  # Restore if needed
  if [ "\$PRIMARY_OK" -eq 1 ] && [ "\$BACKUP_OK" -eq 0 ]; then
    restore_from_backup
  fi
  
  # Final status
  if [ "\$PRIMARY_OK" -eq 0 ]; then
    echo -e "${GREEN}✅ Guardian binary integrity verified${NC}"
    exit 0
  elif [ "\$BACKUP_OK" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ Primary corrupted but backup is intact${NC}"
    echo -e "${YELLOW}💡 Run 'restore_from_backup' to restore${NC}"
    exit 1
  else
    echo -e "${RED}❌ CRITICAL: Both primary and backup are corrupted!${NC}"
    echo -e "${YELLOW}💡 Run emergency recovery: bash ${EMERGENCY_SCRIPT}${NC}"
    exit 2
  fi
}

# Export functions for direct use
export -f check_primary
export -f check_backup
export -f check_permissions
export -f restore_from_backup

# Run main function
main "\$@"
EOF
chmod +x "${TEMP_DIR}/verify-guardian.sh"

# Install binary and verification script
echo -e "${YELLOW}📦 Installing guardian binary...${NC}"
cp "${TEMP_DIR}/shell-guardian" "${GUARDIAN_BIN}"
chmod +x "${GUARDIAN_BIN}"

echo -e "${YELLOW}📦 Installing backup binary...${NC}"
cp "${TEMP_DIR}/shell-guardian" "${GUARDIAN_BACKUP}"
chmod +x "${GUARDIAN_BACKUP}"

echo -e "${YELLOW}📦 Installing verification script...${NC}"
cp "${TEMP_DIR}/verify-guardian.sh" "${BIN_DIR}/verify-guardian"
chmod +x "${BIN_DIR}/verify-guardian"

# Run verification as a final check
echo -e "${YELLOW}🔍 Verifying installation...${NC}"
"${BIN_DIR}/verify-guardian"

echo -e "${GREEN}✅ Guardian compiled and installed successfully${NC}"
echo -e "${BLUE}💡 Verify integrity at any time with: verify-guardian${NC}"