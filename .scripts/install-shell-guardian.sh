#!/bin/bash
# Shell Guardian installer

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📦 Installing Shell Guardian...${NC}"

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

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
GUARDIAN_RS="${SCRIPT_DIR}/shell-guardian.rs"
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"

# Create bin directory if it doesn't exist
mkdir -p "${HOME}/.local/bin"

# Compile
echo -e "${YELLOW}🔧 Compiling Shell Guardian...${NC}"
rustc -O "${GUARDIAN_RS}" -o "${GUARDIAN_BIN}"
chmod +x "${GUARDIAN_BIN}"

# Create shell wrapper
echo -e "${YELLOW}🔧 Creating shell wrapper...${NC}"
cat > "${HOME}/.local/bin/bash-safe" << 'EOF'
#!/bin/bash
exec shell-guardian bash "$@"
EOF
chmod +x "${HOME}/.local/bin/bash-safe"

# Update .bash_profile to use the guardian
BASH_PROFILE="${HOME}/.bash_profile"
if grep -q "shell-guardian" "${BASH_PROFILE}"; then
    echo -e "${GREEN}✅ Shell Guardian already integrated in .bash_profile${NC}"
else
    echo -e "${YELLOW}🔧 Updating .bash_profile...${NC}"
    # Create backup
    cp "${BASH_PROFILE}" "${BASH_PROFILE}.bak"
    
    # Add shell guardian to profile
    cat > "${BASH_PROFILE}" << 'EOF'
# .bash_profile with Shell Guardian integration

# If Shell Guardian is available and not already active, use it
if command -v shell-guardian &> /dev/null && [ -z "$SHELL_GUARDIAN_ACTIVE" ]; then
    # Start shell with guardian
    exec shell-guardian bash
else
    # Source bashrc directly if guardian is not available or already active
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi

# User specific environment and startup programs
EOF
    echo -e "${GREEN}✅ Updated .bash_profile with Shell Guardian integration${NC}"
fi

echo -e "${GREEN}✅ Shell Guardian installed successfully${NC}"
echo -e "${BLUE}🚀 Log out and back in to activate, or run: bash-safe${NC}"