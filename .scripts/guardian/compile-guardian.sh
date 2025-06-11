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

# Update checksum placeholder in source
sed -i "s/CHECKSUM_PLACEHOLDER/${SOURCE_CHECKSUM}/" "${TEMP_DIR}/shell-guardian.rs"

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

# Expected checksum
EXPECTED="${BINARY_CHECKSUM}"

# Calculate actual checksum
ACTUAL=\$(sha256sum "${GUARDIAN_BIN}" 2>/dev/null | awk '{print \$1}')

# Check if checksums match
if [ "\$ACTUAL" = "\$EXPECTED" ]; then
  echo -e "\033[32m✅ Guardian binary verified\033[0m"
  exit 0
else
  echo -e "\033[31m❌ Guardian binary corrupted or tampered!\033[0m"
  echo -e "\033[33m💡 Expected: \$EXPECTED\033[0m"
  echo -e "\033[33m💡 Actual: \$ACTUAL\033[0m"
  exit 1
fi
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