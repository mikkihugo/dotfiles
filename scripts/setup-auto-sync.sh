#!/bin/bash
# 🔧 Setup automatic dotfiles syncing

echo "🔄 Setting up dotfiles auto-sync..."

# Add cron job for hourly sync
CRON_CMD="0 * * * * $HOME/dotfiles/scripts/auto-sync.sh >/dev/null 2>&1"

# Check if cron job already exists
if ! crontab -l 2>/dev/null | grep -q "auto-sync.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo "✅ Added hourly sync cron job"
else
    echo "ℹ️  Cron job already exists"
fi

# Add to bashrc for sync-on-start
if ! grep -q "sync-on-start.sh" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto-sync dotfiles check" >> ~/.bashrc
    echo "source ~/dotfiles/scripts/sync-on-start.sh" >> ~/.bashrc
    echo "✅ Added sync check to bashrc"
else
    echo "ℹ️  Bashrc sync already configured"
fi

# Create aliases
if ! grep -q "dotfiles-sync" ~/.aliases; then
    echo "" >> ~/.aliases
    echo "# Dotfiles management" >> ~/.aliases
    echo "alias dotfiles-sync='~/dotfiles/scripts/auto-sync.sh'" >> ~/.aliases
    echo "alias dotfiles-status='cd ~/dotfiles && git status'" >> ~/.aliases
    echo "alias dotfiles-log='tail -20 ~/.dotfiles-sync.log'" >> ~/.aliases
    echo "✅ Added dotfiles aliases"
fi

echo ""
echo "🎯 Auto-sync configured!"
echo "   - Automatic sync every hour"
echo "   - Check on shell startup"
echo "   - Manual sync: dotfiles-sync"
echo "   - View logs: dotfiles-log"