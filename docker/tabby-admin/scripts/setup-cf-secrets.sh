#!/bin/bash
#
# One-time Cloudflare Secrets setup
# Purpose: Create all secrets in CF dashboard
# Version: 1.0.0

cat << 'EOF'
🔐 Cloudflare Secrets Setup Guide

1. Go to: https://dash.cloudflare.com/?to=/:account/workers/secrets

2. Create these secrets:
   
   REQUIRED:
   - CF_ZONE_ID         → Your domain's zone ID
   - CF_DOMAIN          → hugo.dk
   - BACKUP_ENCRYPTION_KEY → Generate with: openssl rand -base64 32
   
   OPTIONAL (for full features):
   - CF_R2_ACCESS_KEY   → R2 API token
   - CF_R2_SECRET_KEY   → R2 secret
   - GITHUB_TOKEN       → GitHub personal token
   - GITHUB_CLIENT_ID   → OAuth app ID
   - GITHUB_CLIENT_SECRET → OAuth app secret
   - DRONE_RPC_SECRET   → Generate random
   - DRONE_CLIENT_ID    → From Gitea OAuth
   - DRONE_CLIENT_SECRET → From Gitea OAuth
   - WARPGATE_ADMIN_PASS → Admin password

3. Create API Token with permissions:
   - Account:Cloudflare Secrets:Read
   - Zone:Zone:Read
   
4. Save the API token - you'll enter it once during deployment

Alternative: Use Wrangler CLI
   wrangler secret put CF_ZONE_ID
   wrangler secret put CF_DOMAIN
   ... etc

EOF