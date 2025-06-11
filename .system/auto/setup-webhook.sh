#!/bin/bash
# Setup GitHub webhook for dotfiles auto-sync

set -e

REPO="mikkihugo/dotfiles"
WEBHOOK_URL="$1"
SECRET="$2"

if [ -z "$WEBHOOK_URL" ]; then
    echo "Usage: $0 <webhook_url> [secret]"
    echo "Example: $0 http://your-server:8080/webhook my-secret-key"
    exit 1
fi

if [ -z "$SECRET" ]; then
    SECRET=$(openssl rand -hex 32)
    echo "Generated webhook secret: $SECRET"
    echo "Add this to your ~/.env_tokens: export GITHUB_WEBHOOK_SECRET=\"$SECRET\""
fi

# Create webhook
gh api repos/$REPO/hooks \
    --method POST \
    --field name=web \
    --field active=true \
    --field config="{\"url\":\"$WEBHOOK_URL\",\"content_type\":\"json\",\"secret\":\"$SECRET\"}" \
    --field events='["push"]'

echo "✅ Webhook created successfully!"
echo ""
echo "Next steps:"
echo "1. Add to ~/.env_tokens: export GITHUB_WEBHOOK_SECRET=\"$SECRET\""
echo "2. Start webhook server: ~/.dotfiles/.scripts/webhook-server.py"
echo "3. Test with: curl http://your-server:8080/health"