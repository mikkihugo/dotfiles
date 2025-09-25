#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Deploying Secret Sync Relay to Cloudflare Workers..."

# Check if wrangler CLI is installed
if ! command -v wrangler >/dev/null 2>&1; then
    echo "❌ Wrangler CLI not found. Install with: npm install -g wrangler"
    exit 1
fi

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Check if we're logged in
if ! wrangler whoami >/dev/null 2>&1; then
    echo "🔐 Please login to Cloudflare first:"
    echo "   wrangler login"
    exit 1
fi

# Create KV namespaces if they don't exist
echo "🗄️ Setting up KV storage..."
echo "   Run these commands if you haven't already:"
echo "   npm run kv:namespace:create"
echo "   npm run kv:namespace:create:preview"
echo "   Then update wrangler.toml with the namespace IDs"
echo ""

read -p "Have you set up KV namespaces and updated wrangler.toml? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "⚠️  Please set up KV namespaces first and then run this script again"
    exit 1
fi

# Deploy to production
echo "📡 Deploying to production..."
wrangler deploy

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Note your Workers URL from the deployment output"
echo "   2. Test with: curl https://your-worker.your-subdomain.workers.dev/health"
echo ""
echo "💡 Usage in secret-tui:"
echo "   Relay URL: https://your-worker.your-subdomain.workers.dev"
echo "   Room ID: any-shared-secret-between-devices"
echo ""
echo "🆓 Free tier limits:"
echo "   - 100,000 requests/day"
echo "   - 10ms CPU time per request"
echo "   - 1GB KV storage"
echo "   - Global edge network!"