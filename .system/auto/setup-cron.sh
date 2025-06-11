#!/bin/bash
# Setup cron job for auto-sync dotfiles

CRON_JOB="0 6 * * * cd ~/.dotfiles && mise run sync >/dev/null 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "mise run sync"; then
    echo "✅ Cron job already exists"
    crontab -l | grep "mise run sync"
else
    # Add cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Added cron job: Check for updates daily at 6 AM"
    echo "$CRON_JOB"
fi

echo ""
echo "📋 Current cron jobs:"
crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "No cron jobs found"

echo ""
echo "🔧 Manual commands:"
echo "  Run sync now: cd ~/.dotfiles && mise run sync"
echo "  View logs:    tail -f ~/.dotfiles/auto-sync.log"
echo "  Remove cron:  crontab -e (delete the line)"