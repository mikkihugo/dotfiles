#!/bin/bash
# Minimal Guardian Compilation
# Ultra-simple, ultra-secure

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Compiling Minimal Guardian...${NC}"

# Paths
SOURCE="${HOME}/.dotfiles/.guardian-shell/minimal-guardian.rs"
BIN="${HOME}/.local/bin/shell-guardian"
BACKUP="${HOME}/.dotfiles/.guardian-shell/shell-guardian.bin"
CONFIG="${HOME}/.config/.guardian"

# Create directories
mkdir -p "${HOME}/.local/bin" "${HOME}/.config"

# Check Rust
if ! command -v rustc &>/dev/null; then
    echo -e "${RED}❌ Rust compiler not found${NC}"
    echo -e "${YELLOW}💡 Install with: mise install rust${NC}"
    exit 1
fi

# Check source
if [ ! -f "${SOURCE}" ]; then
    echo -e "${RED}❌ Source file not found: ${SOURCE}${NC}"
    exit 1
fi

# Compile
echo -e "${YELLOW}🔧 Compiling...${NC}"
rustc -O "${SOURCE}" -o "${BIN}"
chmod +x "${BIN}"

# Create backup
echo -e "${YELLOW}🔧 Creating backup...${NC}"
cp "${BIN}" "${BACKUP}"
chmod +x "${BACKUP}"

# Create config copy
echo -e "${YELLOW}🔧 Creating config copy...${NC}"
cp "${BIN}" "${CONFIG}"
chmod +x "${CONFIG}"

# Make immutable if possible
if command -v chattr &>/dev/null; then
    echo -e "${YELLOW}🔒 Setting immutable attribute...${NC}"
    chattr +i "${BIN}" 2>/dev/null || sudo chattr +i "${BIN}" 2>/dev/null || true
    chattr +i "${BACKUP}" 2>/dev/null || sudo chattr +i "${BACKUP}" 2>/dev/null || true
    chattr +i "${CONFIG}" 2>/dev/null || sudo chattr +i "${CONFIG}" 2>/dev/null || true
fi

echo -e "${GREEN}✅ Minimal Guardian installed successfully${NC}"
echo -e "${BLUE}💡 The guardian will automatically maintain its copies${NC}"