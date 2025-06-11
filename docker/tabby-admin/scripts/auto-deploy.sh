#!/bin/bash
#
# Auto-deploy admin stack with systemd
# Purpose: Automated deployment on server startup/updates
# Version: 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_DIR="$(dirname "$SCRIPT_DIR")"

# Create systemd service for auto-deploy
sudo tee /etc/systemd/system/tabby-admin.service > /dev/null << EOF
[Unit]
Description=Tabby Admin Stack
After=docker.service network-online.target
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${ADMIN_DIR}
ExecStartPre=/usr/bin/docker-compose pull
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
Restart=on-failure
RestartSec=30
User=${USER}

[Install]
WantedBy=multi-user.target
EOF

# Create update timer
sudo tee /etc/systemd/system/tabby-admin-update.timer > /dev/null << EOF
[Unit]
Description=Update Tabby Admin Stack
Requires=tabby-admin-update.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Create update service
sudo tee /etc/systemd/system/tabby-admin-update.service > /dev/null << EOF
[Unit]
Description=Update Tabby Admin Stack
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${ADMIN_DIR}
ExecStart=/bin/bash -c 'cd ${HOME}/.dotfiles && git pull && cd docker/tabby-admin && docker-compose build && docker-compose up -d'
User=${USER}
EOF

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable --now tabby-admin.service
sudo systemctl enable --now tabby-admin-update.timer

echo "✅ Auto-deploy configured!"
echo ""
echo "Services:"
echo "  - tabby-admin.service     (auto-starts on boot)"
echo "  - tabby-admin-update      (daily updates)"
echo ""
echo "Commands:"
echo "  sudo systemctl status tabby-admin"
echo "  sudo journalctl -u tabby-admin -f"