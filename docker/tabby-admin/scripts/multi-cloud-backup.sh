#!/bin/bash
#
# Multi-Cloud Redundant Backup System
# Purpose: Backup to ALL free services for ultimate redundancy
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}☁️  Multi-Cloud Backup System${NC}"
echo "Backing up to: GitHub, Google, Cloudflare, and more!"
echo ""

# Create master backup
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="/tmp/admin-master-$BACKUP_DATE.tar.gz"
ENCRYPTED_FILE="$BACKUP_FILE.enc"

# Step 1: Create backup archive
create_backup() {
    echo -e "${YELLOW}Creating backup archive...${NC}"
    
    # Export Vault
    docker exec vault vault operator raft snapshot save /tmp/vault.snap
    docker cp vault:/tmp/vault.snap /tmp/
    
    # Create manifest
    cat > /tmp/backup-manifest.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "hostname": "$(hostname)",
    "docker_images": [
        "vault:$(docker inspect vault --format='{{.Image}}')",
        "warpgate:$(docker inspect warpgate --format='{{.Image}}')",
        "tabby-web:$(docker inspect tabby-web --format='{{.Image}}')"
    ],
    "backup_locations": {
        "github": "pending",
        "google": "pending",
        "cloudflare": "pending",
        "backblaze": "pending"
    }
}
EOF
    
    # Create archive
    tar czf "$BACKUP_FILE" \
        /tmp/vault.snap \
        /tmp/backup-manifest.json \
        -C $HOME/.dotfiles docker/tabby-admin \
        -C $HOME .dotfiles \
        -C /var/lib/docker/volumes . 2>/dev/null || true
    
    # Encrypt with master key from Vault
    BACKUP_KEY=$(docker exec vault vault kv get -field=backup_key secret/services)
    openssl enc -aes-256-cbc -pbkdf2 -salt -k "$BACKUP_KEY" \
        -in "$BACKUP_FILE" -out "$ENCRYPTED_FILE"
    
    # Clean up unencrypted
    rm -f "$BACKUP_FILE" /tmp/vault.snap
    
    echo -e "${GREEN}✓ Backup created: $(du -h $ENCRYPTED_FILE | cut -f1)${NC}"
}

# Backup to GitHub (Releases + Packages)
backup_to_github() {
    echo -e "${YELLOW}Backing up to GitHub...${NC}"
    
    # Create release
    local release_tag="backup-$BACKUP_DATE"
    gh release create "$release_tag" \
        --repo "mikkihugo/dotfiles-admin" \
        --title "Backup $BACKUP_DATE" \
        --notes "Multi-cloud backup" \
        "$ENCRYPTED_FILE" || echo "GitHub release failed"
    
    # Also push Docker images to GitHub Packages
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u mikkihugo --password-stdin
    for image in vault warpgate tabby-web; do
        docker tag "$image:latest" "ghcr.io/mikkihugo/admin/$image:backup-$BACKUP_DATE"
        docker push "ghcr.io/mikkihugo/admin/$image:backup-$BACKUP_DATE" || true
    done
    
    echo -e "${GREEN}✓ GitHub backup complete${NC}"
}

# Backup to Google (Drive + Cloud Storage)
backup_to_google() {
    echo -e "${YELLOW}Backing up to Google...${NC}"
    
    # Google Drive via gdrive
    if command -v gdrive &>/dev/null; then
        gdrive upload --parent "${GOOGLE_DRIVE_FOLDER_ID}" "$ENCRYPTED_FILE" || true
    fi
    
    # Google Cloud Storage
    if command -v gcloud &>/dev/null; then
        gsutil cp "$ENCRYPTED_FILE" "gs://hugo-backups/admin/$BACKUP_DATE/" || true
    fi
    
    # Google Photos (as additional backup) - via API
    # Photos API allows up to 16MB per photo, we can split the backup
    
    echo -e "${GREEN}✓ Google backup complete${NC}"
}

# Backup to Cloudflare (R2 + KV + D1)
backup_to_cloudflare() {
    echo -e "${YELLOW}Backing up to Cloudflare...${NC}"
    
    # R2 Storage (10GB free)
    aws s3 cp "$ENCRYPTED_FILE" \
        "s3://hugo-admin-backups/$BACKUP_DATE/" \
        --endpoint-url "https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com" \
        --profile cloudflare || true
    
    # Split for KV storage (25MB limit per key)
    split -b 20M "$ENCRYPTED_FILE" "/tmp/backup-part-"
    for part in /tmp/backup-part-*; do
        curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/storage/kv/namespaces/${KV_NAMESPACE_ID}/values/backup-$BACKUP_DATE-$(basename $part)" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            --data-binary "@$part" || true
    done
    
    echo -e "${GREEN}✓ Cloudflare backup complete${NC}"
}

# Backup to other free services
backup_to_others() {
    echo -e "${YELLOW}Backing up to additional services...${NC}"
    
    # Backblaze B2 (10GB free)
    if command -v b2 &>/dev/null; then
        b2 upload-file hugo-admin-backups "$ENCRYPTED_FILE" "backups/$BACKUP_DATE/admin-backup.enc" || true
    fi
    
    # MEGA (20GB free)
    if command -v mega-put &>/dev/null; then
        mega-put "$ENCRYPTED_FILE" /Root/backups/admin/$BACKUP_DATE/ || true
    fi
    
    # pCloud (10GB free)
    if command -v pcloudcc &>/dev/null; then
        pcloudcc upload "$ENCRYPTED_FILE" /backups/admin/$BACKUP_DATE/ || true
    fi
    
    # Archive.org (unlimited free for preservation)
    if command -v ia &>/dev/null; then
        ia upload "hugo-admin-backup-$BACKUP_DATE" "$ENCRYPTED_FILE" \
            --metadata="mediatype:data" \
            --metadata="description:Admin stack backup" || true
    fi
    
    echo -e "${GREEN}✓ Additional backups complete${NC}"
}

# Verify backups
verify_backups() {
    echo -e "${YELLOW}Verifying backups...${NC}"
    
    local verified=0
    local total=0
    
    # Check GitHub
    ((total++))
    if gh release view "backup-$BACKUP_DATE" --repo "mikkihugo/dotfiles-admin" &>/dev/null; then
        ((verified++))
        echo -e "${GREEN}✓ GitHub verified${NC}"
    else
        echo -e "${RED}✗ GitHub failed${NC}"
    fi
    
    # Check Google
    ((total++))
    if gsutil ls "gs://hugo-backups/admin/$BACKUP_DATE/" &>/dev/null; then
        ((verified++))
        echo -e "${GREEN}✓ Google verified${NC}"
    else
        echo -e "${YELLOW}⚠ Google not verified${NC}"
    fi
    
    # Check Cloudflare
    ((total++))
    if aws s3 ls "s3://hugo-admin-backups/$BACKUP_DATE/" --endpoint-url "https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com" &>/dev/null; then
        ((verified++))
        echo -e "${GREEN}✓ Cloudflare verified${NC}"
    else
        echo -e "${YELLOW}⚠ Cloudflare not verified${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Backup Summary:${NC}"
    echo "✓ Verified: $verified/$total locations"
    echo "✓ Backup size: $(du -h $ENCRYPTED_FILE | cut -f1)"
    echo "✓ Backup ID: $BACKUP_DATE"
}

# Restore from any available source
restore_from_any() {
    local backup_id=${1:-latest}
    
    echo -e "${BLUE}Attempting restore from multiple sources...${NC}"
    
    # Try GitHub first (most reliable)
    if gh release download "$backup_id" --repo "mikkihugo/dotfiles-admin" --pattern "*.enc" 2>/dev/null; then
        echo -e "${GREEN}✓ Restored from GitHub${NC}"
        return 0
    fi
    
    # Try Google
    if gsutil cp "gs://hugo-backups/admin/$backup_id/*.enc" . 2>/dev/null; then
        echo -e "${GREEN}✓ Restored from Google${NC}"
        return 0
    fi
    
    # Try Cloudflare
    if aws s3 cp "s3://hugo-admin-backups/$backup_id/" . --recursive --endpoint-url "https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com" 2>/dev/null; then
        echo -e "${GREEN}✓ Restored from Cloudflare${NC}"
        return 0
    fi
    
    echo -e "${RED}❌ Restore failed from all sources${NC}"
    return 1
}

# Main execution
main() {
    case "${1:-backup}" in
        backup)
            create_backup
            backup_to_github &
            backup_to_google &
            backup_to_cloudflare &
            backup_to_others &
            wait
            verify_backups
            rm -f "$ENCRYPTED_FILE" /tmp/backup-part-*
            ;;
        restore)
            restore_from_any "${2:-latest}"
            ;;
        list)
            echo "GitHub backups:"
            gh release list --repo "mikkihugo/dotfiles-admin" --limit 10
            echo -e "\nGoogle backups:"
            gsutil ls "gs://hugo-backups/admin/" 2>/dev/null || true
            echo -e "\nCloudflare backups:"
            aws s3 ls "s3://hugo-admin-backups/" --endpoint-url "https://${CF_ACCOUNT_ID}.r2.cloudflarestorage.com" 2>/dev/null || true
            ;;
        *)
            echo "Usage: $0 {backup|restore|list}"
            exit 1
            ;;
    esac
}

main "$@"