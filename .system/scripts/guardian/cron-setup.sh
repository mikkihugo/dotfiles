#!/bin/bash
# System cron setup for Guardian
# This creates a system-level cron job for maximum security and persistence

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Setting up system cron for Guardian...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}⚠️ This script needs root privileges${NC}"
  echo -e "${YELLOW}💡 Re-running with sudo...${NC}"
  exec sudo bash "$0" "$@"
  exit $?
fi

# Essential paths (minimal and secure)
USER=$(logname || echo $SUDO_USER)
HOME_DIR=$(eval echo ~$USER)
CRON_SCRIPT="/etc/cron.hourly/guardian-check"

# Create the cron script
echo -e "${YELLOW}📝 Creating cron script...${NC}"
cat > "${CRON_SCRIPT}" << EOF
#!/bin/bash
# Guardian check - System cron
# Ensures guardian survival even if user processes fail

# Essential paths
HOME_DIR="${HOME_DIR}"
GUARDIAN_BIN="\${HOME_DIR}/.local/bin/shell-guardian"
GUARDIAN_BACKUP="\${HOME_DIR}/.dotfiles/.guardian-shell/shell-guardian.bin"
CONFIG_BACKUP="\${HOME_DIR}/.config/.guardian"

# Check if a source file exists
check_source() {
  for src in "\${GUARDIAN_BIN}" "\${GUARDIAN_BACKUP}" "\${CONFIG_BACKUP}"; do
    if [ -f "\${src}" ] && [ -x "\${src}" ]; then
      echo "\${src}"
      return 0
    fi
  done
  return 1
}

# Find source file
SOURCE=\$(check_source)
if [ -z "\${SOURCE}" ]; then
  # No source found, cannot repair
  exit 1
fi

# Restore to all locations
mkdir -p "\$(dirname "\${GUARDIAN_BIN}")" "\$(dirname "\${CONFIG_BACKUP}")"
cp "\${SOURCE}" "\${GUARDIAN_BIN}" 2>/dev/null || true
cp "\${SOURCE}" "\${GUARDIAN_BACKUP}" 2>/dev/null || true
cp "\${SOURCE}" "\${CONFIG_BACKUP}" 2>/dev/null || true
chmod 755 "\${GUARDIAN_BIN}" "\${GUARDIAN_BACKUP}" "\${CONFIG_BACKUP}" 2>/dev/null || true

# Exit silently
exit 0
EOF

# Make cron script executable
chmod 755 "${CRON_SCRIPT}"

# Secure the cron script from modification
echo -e "${YELLOW}🔒 Securing cron script...${NC}"
chown root:root "${CRON_SCRIPT}"
chmod 755 "${CRON_SCRIPT}"

# Make immutable if possible
if command -v chattr &>/dev/null; then
  echo -e "${YELLOW}🔐 Setting immutable attribute...${NC}"
  chattr +i "${CRON_SCRIPT}" 2>/dev/null || true
fi

echo -e "${GREEN}✅ System cron setup complete${NC}"
echo -e "${BLUE}🔄 Guardian will be checked and restored hourly${NC}"
echo -e "${YELLOW}💡 Note: This uses system cron, which runs independently of user sessions${NC}"