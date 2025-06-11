#!/bin/bash
# Compile and install the Guardian Keeper
# This is the parasite-like component that ensures the guardian always survives

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧬 Compiling Guardian Keeper (parasite system)...${NC}"

# Paths
GUARDIAN_DIR="${HOME}/.dotfiles/.guardian-shell"
KEEPER_RS="${GUARDIAN_DIR}/guardian-keeper.rs"
KEEPER_BIN="${HOME}/.local/bin/guardian-keeper"
BIN_DIR="${HOME}/.local/bin"

# Check for rustc
if ! command -v rustc &>/dev/null; then
    echo -e "${RED}❌ Rust compiler not found${NC}"
    echo -e "${YELLOW}💡 Install with: mise install rust${NC}"
    exit 1
fi

# Check if source exists
if [ ! -f "${KEEPER_RS}" ]; then
    echo -e "${RED}❌ Source file not found: ${KEEPER_RS}${NC}"
    exit 1
fi

# Create bin directory if it doesn't exist
mkdir -p "${BIN_DIR}"

# Compile keeper
echo -e "${YELLOW}🔧 Compiling keeper...${NC}"
rustc -O -C opt-level=3 -C lto=fat "${KEEPER_RS}" -o "${KEEPER_BIN}"
chmod +x "${KEEPER_BIN}"

# Create a copy in the guardian directory
cp "${KEEPER_BIN}" "${GUARDIAN_DIR}/guardian-keeper"
chmod +x "${GUARDIAN_DIR}/guardian-keeper"

echo -e "${GREEN}✅ Guardian Keeper compiled and installed${NC}"

# Ask about systemd service
echo -e "${YELLOW}🔄 Would you like to install the Guardian Keeper as a service? (y/n)${NC}"
read -r install_service

if [[ "$install_service" =~ ^[Yy]$ ]]; then
    # Create systemd user directory
    mkdir -p "${HOME}/.config/systemd/user"
    
    # Create service file
    cat > "${HOME}/.config/systemd/user/guardian-keeper.service" << EOF
[Unit]
Description=Guardian Keeper - Guardian Binary Survival Service
After=network.target

[Service]
Type=simple
ExecStart=${KEEPER_BIN} service
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    # Enable and start service
    systemctl --user daemon-reload
    systemctl --user enable guardian-keeper.service
    systemctl --user start guardian-keeper.service
    
    echo -e "${GREEN}✅ Guardian Keeper service installed and started${NC}"
fi

# Run keeper once to create initial copies
echo -e "${YELLOW}🔄 Running initial parasitic replication...${NC}"
"${KEEPER_BIN}"

echo -e "${GREEN}✅ Guardian Keeper setup complete${NC}"
echo -e "${BLUE}💡 The keeper will maintain multiple copies of the guardian${NC}"
echo -e "${BLUE}💡 Even if the guardian is deleted, it will automatically restore it${NC}"