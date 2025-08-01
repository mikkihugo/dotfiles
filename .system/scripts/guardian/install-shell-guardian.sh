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
GUARDIAN_DIR="${HOME}/.dotfiles/.guardian-shell"
GUARDIAN_RS="${GUARDIAN_DIR}/shell-guardian.rs"
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

# Keep a backup copy in the protected directory for preservation
echo -e "${YELLOW}🔧 Saving compiled binary to protected directory...${NC}"
cp "${GUARDIAN_BIN}" "${GUARDIAN_DIR}/shell-guardian.bin"
chmod +x "${GUARDIAN_DIR}/shell-guardian.bin"

# Create shell hooks
echo -e "${YELLOW}🔧 Setting up shell hooks...${NC}"
bash "${SCRIPT_DIR}/guardian-shell-hooks.sh"

# Create symlink to bash fallback for emergency use
echo -e "${YELLOW}🔧 Creating fallback symlink...${NC}"
ln -sf "${SCRIPT_DIR}/bash-guardian-fallback.sh" "${BIN_DIR}/shell-guardian-fallback"
chmod +x "${BIN_DIR}/shell-guardian-fallback"

echo -e "${GREEN}✅ Shell Guardian installed successfully${NC}"
echo -e "${BLUE}🚀 Log out and back in to activate, or run: shell-safe${NC}"