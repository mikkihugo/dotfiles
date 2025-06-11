#!/bin/bash
#
# Sync secrets between Google Secret Manager and local
# Purpose: Use Google's free secret storage
# Version: 1.0.0

set -euo pipefail

PROJECT_ID="hugo-admin-stack"

# Function to get secret from Google
get_google_secret() {
    local secret_name=$1
    gcloud secrets versions access latest --secret="$secret_name" --project="$PROJECT_ID" 2>/dev/null || echo ""
}

# Function to set secret in Google
set_google_secret() {
    local secret_name=$1
    local secret_value=$2
    
    # Create secret if doesn't exist
    if ! gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null; then
        gcloud secrets create "$secret_name" --project="$PROJECT_ID"
    fi
    
    # Add new version
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
        --data-file=- --project="$PROJECT_ID"
}

# Sync from Google to local
sync_from_google() {
    echo "📥 Syncing secrets from Google Secret Manager..."
    
    cat > .env << EOF
# Synced from Google Secret Manager
# Project: $PROJECT_ID
# Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)

CF_API_TOKEN=$(get_google_secret "cf-api-token")
CF_ZONE_ID=$(get_google_secret "cf-zone-id")
CF_DOMAIN=$(get_google_secret "cf-domain")
GITHUB_TOKEN=$(get_google_secret "github-token")
BACKUP_ENCRYPTION_KEY=$(get_google_secret "backup-key")
WARPGATE_ADMIN_PASS=$(get_google_secret "warpgate-pass")
EOF

    chmod 600 .env
    echo "✅ Secrets synced from Google!"
}

# Main
case "${1:-sync}" in
    sync)
        sync_from_google
        ;;
    set)
        secret_name=$2
        secret_value=$3
        set_google_secret "$secret_name" "$secret_value"
        echo "✅ Secret '$secret_name' stored in Google"
        ;;
    get)
        secret_name=$2
        get_google_secret "$secret_name"
        ;;
    list)
        gcloud secrets list --project="$PROJECT_ID"
        ;;
    *)
        echo "Usage: $0 {sync|set|get|list}"
        exit 1
        ;;
esac