#!/bin/bash
#
# Simplified unlock - just Google login
# Purpose: One command to unlock everything
# Version: 1.0.0

set -euo pipefail

echo "🔐 Admin Stack Quick Unlock"
echo ""

# Install gcloud if needed
if ! command -v gcloud &>/dev/null; then
    echo "Installing Google Cloud SDK..."
    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL
fi

# Run Google auth unlock
$(dirname "$0")/google-auth-unlock.sh

# Start services if not running
if ! docker-compose ps | grep -q "Up"; then
    echo ""
    echo "Starting admin stack..."
    cd "$(dirname "$0")/.."
    make up
fi

echo ""
echo "✅ Admin stack is ready!"