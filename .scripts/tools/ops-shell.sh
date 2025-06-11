#!/bin/bash
#
# Ops Shell - Dedicated environment for infrastructure management
# Purpose: Separate shell for Tabby gateway, sync, and system operations
# Version: 1.0.0

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧 Launching Ops Shell...${NC}"

# Check if this host runs ops services
/home/mhugo/.dotfiles/.system/scripts/ops-host-manager.sh status

# Create ops environment
export OPS_SHELL=1
export PS1="[OPS] \[\033[0;31m\]\u@\h\[\033[0m\]:\[\033[0;34m\]\w\[\033[0m\]# "

# Add system management paths
export PATH="/home/mhugo/.dotfiles/.system/scripts:$PATH"
export PATH="/home/mhugo/.dotfiles/.system/auto:$PATH"

# Ops-specific aliases
alias gw-status='gateway-status.sh'
alias gw-deploy='deploy-tabby-gateway.sh'
alias tabby-backup='backup-tabby-gateway.sh && backup-tabby-web-db.sh'
alias tabby-sync='tabby-sync.sh'
alias logs='journalctl --user -f'
alias services='systemctl --user status'

# Show status dashboard
cat << EOF

${GREEN}=== Ops Shell Active ===${NC}
${YELLOW}Available Commands:${NC}
  gw-status     - Check gateway status
  gw-deploy     - Deploy gateway updates
  tabby-backup  - Backup all Tabby configs
  tabby-sync    - Sync configurations
  logs          - Follow system logs
  services      - Check service status

${YELLOW}System Tasks:${NC}
  mise -f .system/mise/system-tasks.toml tasks

${YELLOW}Quick Actions:${NC}
  guardian      - Check guardian status
  sync          - Run full sync
  backup        - Create system backup

EOF

# Launch in contained environment
/bin/bash --rcfile <(echo '
# Minimal ops environment
source /etc/profile
export OPS_SHELL=1
export PS1="[OPS] \\[\\033[0;31m\\]\\u@\\h\\[\\033[0m\\]:\\[\\033[0;34m\\]\\w\\[\\033[0m\\]# "

# Ops aliases
alias gw-status="gateway-status.sh"
alias gw-deploy="deploy-tabby-gateway.sh"
alias tabby-backup="backup-tabby-gateway.sh && backup-tabby-web-db.sh"
alias tabby-sync="tabby-sync.sh"
alias logs="journalctl --user -f"
alias services="systemctl --user status"
alias guardian="mise -f ~/.dotfiles/.system/mise/system-tasks.toml run guardian-status"
alias sync="mise -f ~/.dotfiles/.system/mise/system-tasks.toml run sync"
alias backup="mise -f ~/.dotfiles/.system/mise/system-tasks.toml run backup-create"

# Load tokens for operations
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens"
    set +a
fi

echo -e "\\033[0;32m✓ Ops environment ready\\033[0m"
')