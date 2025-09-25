#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Deploying Secret Sync Relay to Netlify..."

# Check if netlify CLI is installed
if ! command -v netlify >/dev/null 2>&1; then
    echo "❌ Netlify CLI not found. Install with: npm install -g netlify-cli"
    exit 1
fi

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Check if we're logged in
if ! netlify status >/dev/null 2>&1; then
    echo "🔐 Please login to Netlify first:"
    echo "   netlify login"
    exit 1
fi

# Build (not needed for functions, but included for completeness)
echo "🔨 Building..."
npm run build

# Deploy to production
echo "📡 Deploying to production..."
netlify deploy --prod

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Note your Netlify app URL from the deployment output"
echo "   2. Test with: curl https://your-app.netlify.app/health"
echo ""
echo "💡 Usage in secret-tui:"
echo "   Relay URL: https://your-app.netlify.app"
echo "   Room ID: any-shared-secret-between-devices"
echo ""
echo "🆓 Free tier limits:"
echo "   - 125,000 function invocations/month"
echo "   - 100 hours runtime/month"
echo "   - Perfect for personal secret sync!"