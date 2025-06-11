#!/bin/bash
# Setup guardian verification service
# This creates a systemd user service to regularly verify guardian integrity

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Setting up guardian verification service...${NC}"

# Check if systemd is available
if ! command -v systemctl &>/dev/null; then
    echo -e "${RED}❌ systemd not available${NC}"
    echo -e "${YELLOW}💡 Skipping service setup${NC}"
    exit 1
fi

# Ensure user systemd directory exists
mkdir -p "${HOME}/.config/systemd/user"

# Create verification service
cat > "${HOME}/.config/systemd/user/guardian-verify.service" << EOF
[Unit]
Description=Shell Guardian Integrity Check
After=network.target

[Service]
Type=oneshot
ExecStart=${HOME}/.local/bin/verify-guardian
EOF

# Create timer
cat > "${HOME}/.config/systemd/user/guardian-verify.timer" << EOF
[Unit]
Description=Regular Shell Guardian Integrity Check

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start timer
systemctl --user daemon-reload
systemctl --user enable guardian-verify.timer
systemctl --user start guardian-verify.timer

echo -e "${GREEN}✅ Guardian verification service installed${NC}"
echo -e "${BLUE}💡 The service will check guardian integrity hourly${NC}"
echo -e "${YELLOW}📋 Service status:${NC}"
systemctl --user status guardian-verify.timer