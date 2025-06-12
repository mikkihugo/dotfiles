#!/bin/bash
# Build script for Guardian binaries with optimizations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
INSTALL_DIR="${HOME}/.local/bin"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔨 Building Guardian System V2${NC}"

# Check for Rust
if ! command -v rustc &> /dev/null; then
    echo -e "${RED}❌ Rust compiler not found!${NC}"
    echo "Install Rust from https://rustup.rs/"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

# Optimization flags for production
RUSTFLAGS="-C opt-level=3 -C lto=fat -C codegen-units=1 -C target-cpu=native"

# Build shell-guardian with SpaceX improvements
echo -e "${YELLOW}Building shell-guardian...${NC}"
rustc $RUSTFLAGS \
    "${SCRIPT_DIR}/shell-guardian.rs" \
    -o "${BUILD_DIR}/shell-guardian" \
    2>&1 | tee "${BUILD_DIR}/shell-guardian.log"

# Build guardian-keeper with SpaceX improvements
echo -e "${YELLOW}Building guardian-keeper...${NC}"
if [ -f "${SCRIPT_DIR}/guardian-keeper-spacex.rs" ]; then
    rustc $RUSTFLAGS \
        "${SCRIPT_DIR}/guardian-keeper-spacex.rs" \
        -o "${BUILD_DIR}/guardian-keeper" \
        2>&1 | tee "${BUILD_DIR}/guardian-keeper.log"
else
    rustc $RUSTFLAGS \
        "${SCRIPT_DIR}/guardian-keeper.rs" \
        -o "${BUILD_DIR}/guardian-keeper" \
        2>&1 | tee "${BUILD_DIR}/guardian-keeper.log"
fi

# Strip binaries for size
if command -v strip &> /dev/null; then
    echo -e "${YELLOW}Stripping binaries...${NC}"
    strip "${BUILD_DIR}/shell-guardian"
    strip "${BUILD_DIR}/guardian-keeper"
fi

# Show binary info
echo -e "\n${GREEN}📊 Build Results:${NC}"
ls -lh "${BUILD_DIR}"/shell-guardian "${BUILD_DIR}"/guardian-keeper

# Install binaries
echo -e "\n${YELLOW}Installing binaries...${NC}"
install -m 755 "${BUILD_DIR}/shell-guardian" "${INSTALL_DIR}/shell-guardian"
install -m 755 "${BUILD_DIR}/guardian-keeper" "${INSTALL_DIR}/guardian-keeper"

# Create initial survival copies
echo -e "\n${YELLOW}Creating survival copies...${NC}"
SURVIVAL_DIRS=(
    "${HOME}/.cache/guardian"
    "${HOME}/.config/guardian/bin"
    "${HOME}/.local/share/guardian"
)

for dir in "${SURVIVAL_DIRS[@]}"; do
    mkdir -p "$dir"
    cp "${INSTALL_DIR}/shell-guardian" "$dir/" 2>/dev/null || true
done

# Run initial keeper check
echo -e "\n${YELLOW}Running initial keeper check...${NC}"
"${INSTALL_DIR}/guardian-keeper" check

# Create systemd service file (optional)
if command -v systemctl &> /dev/null; then
    echo -e "\n${YELLOW}Creating systemd service file...${NC}"
    mkdir -p "${HOME}/.config/systemd/user"
    cat > "${HOME}/.config/systemd/user/guardian-keeper.service" << EOF
[Unit]
Description=Guardian Keeper - Binary survival service
After=default.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/guardian-keeper service
Restart=always
RestartSec=30
StartLimitBurst=5
StartLimitIntervalSec=300
Environment="GUARDIAN_CHECK_INTERVAL=60"

[Install]
WantedBy=default.target
EOF
    
    echo -e "${GREEN}✅ Systemd service created${NC}"
    echo "To enable: systemctl --user enable guardian-keeper.service"
fi

echo -e "\n${GREEN}✅ Guardian System (SpaceX Edition) built and installed!${NC}"
echo -e "${GREEN}📍 Binaries installed to: ${INSTALL_DIR}${NC}"

# Test the guardian
echo -e "\n${YELLOW}Testing guardian...${NC}"
"${INSTALL_DIR}/shell-guardian" /bin/echo "Guardian test successful!"

echo -e "\n${GREEN}🎉 All done!${NC}"