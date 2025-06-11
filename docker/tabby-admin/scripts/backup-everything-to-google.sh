#!/bin/bash
#
# Complete backup to Google Drive
# Purpose: Backup everything including dotfiles to Google
# Version: 1.0.0

set -euo pipefail

echo "📦 Backing up everything to Google Drive..."

# Authenticate if needed
if ! gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
    gcloud auth login --enable-gdrive-access
fi

# Install gdrive CLI if needed
if ! command -v gdrive &>/dev/null; then
    echo "Installing gdrive CLI..."
    go install github.com/prasmussen/gdrive@latest
fi

# Create backup directory structure
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/hugo-backup-$BACKUP_DATE"
mkdir -p "$BACKUP_DIR"

# 1. Export Vault data
echo "📦 Exporting Vault..."
docker exec vault vault operator raft snapshot save /tmp/vault-backup.snap
docker cp vault:/tmp/vault-backup.snap "$BACKUP_DIR/"

# 2. Backup all Docker volumes
echo "📦 Backing up Docker volumes..."
for volume in vault-data warpgate-data tabby-data gitea-data drone-data; do
    docker run --rm -v $volume:/data -v $BACKUP_DIR:/backup alpine \
        tar czf /backup/$volume.tar.gz -C /data .
done

# 3. Backup dotfiles
echo "📦 Backing up dotfiles..."
tar czf "$BACKUP_DIR/dotfiles.tar.gz" -C $HOME .dotfiles

# 4. Export docker configs
echo "📦 Exporting Docker configs..."
cd $(dirname "$0")/..
tar czf "$BACKUP_DIR/docker-admin-configs.tar.gz" .

# 5. Create manifest
cat > "$BACKUP_DIR/manifest.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "services": {
    "vault": "unsealed",
    "warpgate": "running",
    "tabby": "running",
    "gitea": "running",
    "drone": "running"
  },
  "backup_size": "$(du -sh $BACKUP_DIR | cut -f1)"
}
EOF

# 6. Encrypt backup
echo "🔐 Encrypting backup..."
ENCRYPTION_KEY=$(docker exec vault vault kv get -field=backup_key secret/services)
tar czf - -C "$BACKUP_DIR" . | openssl enc -aes-256-cbc -pbkdf2 -k "$ENCRYPTION_KEY" > "$BACKUP_DIR.enc"

# 7. Upload to Google Drive
echo "☁️  Uploading to Google Drive..."
gdrive upload --parent "${GOOGLE_DRIVE_FOLDER_ID}" "$BACKUP_DIR.enc"

# Also upload to Google Cloud Storage if available
if gcloud storage buckets list 2>/dev/null | grep -q "hugo-backups"; then
    gcloud storage cp "$BACKUP_DIR.enc" "gs://hugo-backups/admin-stack/"
fi

# Clean up
rm -rf "$BACKUP_DIR" "$BACKUP_DIR.enc"

echo "✅ Backup complete!"
echo "Location: Google Drive/hugo-backups/admin-stack-$BACKUP_DATE.enc"