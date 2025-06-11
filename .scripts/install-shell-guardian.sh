#!/bin/bash
# Ultra-minimal Shell Guardian installer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 Installing Minimal Shell Guardian...${NC}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
GUARDIAN_RS="${SCRIPT_DIR}/shell-guardian.rs"
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"
BIN_DIR="${HOME}/.local/bin"

# Check for rustc
if ! command -v rustc &> /dev/null; then
    echo -e "${YELLOW}⚠️ Rust compiler not found${NC}"
    
    # Try to use mise to install Rust
    if command -v mise &> /dev/null; then
        echo -e "${YELLOW}🔧 Installing Rust via mise...${NC}"
        mise install rust@stable
        eval "$(mise activate bash)"
    else
        echo -e "${RED}❌ Rust compiler not found and mise not available${NC}"
        echo -e "${YELLOW}💡 Install Rust with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
        exit 1
    fi
fi

# Create bin directory if it doesn't exist
mkdir -p "${BIN_DIR}"

# Compile guardian
echo -e "${YELLOW}🔧 Compiling Shell Guardian...${NC}"
rustc -O "${GUARDIAN_RS}" -o "${GUARDIAN_BIN}"
chmod +x "${GUARDIAN_BIN}"

# Keep a backup copy in the dotfiles repo for preservation
echo -e "${YELLOW}🔧 Saving compiled binary to dotfiles...${NC}"
cp "${GUARDIAN_BIN}" "${SCRIPT_DIR}/shell-guardian.bin"
chmod +x "${SCRIPT_DIR}/shell-guardian.bin"

# Create shell hooks
echo -e "${YELLOW}🔧 Setting up shell hooks...${NC}"
bash "${SCRIPT_DIR}/guardian-shell-hooks.sh"

echo -e "${GREEN}✅ Shell Guardian installed successfully${NC}"
echo -e "${BLUE}🚀 Log out and back in to activate, or run: shell-safe${NC}"