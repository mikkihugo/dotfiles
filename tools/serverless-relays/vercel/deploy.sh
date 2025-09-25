#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Deploying Secret Sync Relay to Vercel..."

# Check if vercel CLI is installed
if ! command -v vercel >/dev/null 2>&1; then
    echo "❌ Vercel CLI not found. Install with: npm install -g vercel"
    exit 1
fi

# Install dependencies
if [[ ! -d "node_modules" ]]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Check environment variables
if [[ -z "${KV_REST_API_URL:-}" ]] || [[ -z "${KV_REST_API_TOKEN:-}" ]]; then
    echo "⚠️  KV environment variables not set locally"
    echo "   Make sure to configure them in Vercel dashboard:"
    echo "   - KV_REST_API_URL"
    echo "   - KV_REST_API_TOKEN"
fi

# Deploy to production
echo "📡 Deploying to production..."
vercel --prod

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Configure KV storage in Vercel dashboard"
echo "   2. Add environment variables (KV_REST_API_URL, KV_REST_API_TOKEN)"
echo "   3. Test with: curl https://your-app.vercel.app/health"
echo ""
echo "💡 Usage in secret-tui:"
echo "   Relay URL: https://your-app.vercel.app"
echo "   Room ID: any-shared-secret-between-devices"