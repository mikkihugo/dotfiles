#!/bin/bash
# Schedule failsafe checks via cron
# This ensures that even if someone tampers with the login scripts,
# the failsafe will be periodically checked and restored

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🕐 Setting up scheduled failsafe integrity checks...${NC}"

# Create logs directory
mkdir -p "${HOME}/.dotfiles/logs"

# Setup cron job for periodic checks (every 6 hours)
(crontab -l 2>/dev/null | grep -v "verify-failsafe-integrity" ; cat << EOF
# Failsafe Integrity Check (every 6 hours)
0 */6 * * * /home/mhugo/.dotfiles/.scripts/guardian/verify-failsafe-integrity.sh >> /home/mhugo/.dotfiles/logs/failsafe-integrity.log 2>&1
EOF
) | crontab -

echo -e "${GREEN}✅ Scheduled failsafe integrity checks (every 6 hours)${NC}"
echo -e "${YELLOW}📋 Current cron jobs:${NC}"
crontab -l | grep failsafe