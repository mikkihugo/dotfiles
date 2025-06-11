#!/bin/bash

# Backup Tabby Web SQLite database (encrypted) to GitHub Gist

set -e

source ~/.env_tokens

DB_PATH="$HOME/.dotfiles/data/tabby-web/tabby.db"
BACKUP_DIR="/tmp/tabby-web-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🔄 Backing up Tabby Web database..."

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found at $DB_PATH"
    exit 1
fi

# Create backup directory
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 1. Create SQL dump (more portable than binary)
echo "📤 Creating SQL dump..."
sqlite3 "$DB_PATH" .dump > "$BACKUP_DIR/tabby-web-$TIMESTAMP.sql"

# 2. Compress and encrypt with openssl
echo "🔒 Encrypting backup..."
gzip "$BACKUP_DIR/tabby-web-$TIMESTAMP.sql"
openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/tabby-web-$TIMESTAMP.sql.gz" -out "$BACKUP_DIR/tabby-web-$TIMESTAMP.sql.gz.enc" -pass pass:"$TABBY_GATEWAY_TOKEN"

# 3. Create metadata
cat > "$BACKUP_DIR/backup-info.txt" << EOF
# Tabby Web Database Backup
Created: $(date)
Server: $(hostname)
Size: $(ls -lh "$DB_PATH" | awk '{print $5}')
Tables: $(sqlite3 "$DB_PATH" ".tables")
Encryption: AES-256-CBC with gateway token
EOF

# 4. Upload to GitHub Gist
echo "📤 Uploading to GitHub Gist..."
cd "$BACKUP_DIR"

if [ -z "$TABBY_WEB_DB_GIST_ID" ]; then
    # Create new gist
    GIST_ID=$(gh gist create *.enc backup-info.txt --desc "Tabby Web DB Backup $(date)" | grep -oE '[a-f0-9]{32}')
    echo "" >> ~/.env_tokens
    echo "# Tabby Web Database Backup Gist" >> ~/.env_tokens
    echo "export TABBY_WEB_DB_GIST_ID=$GIST_ID" >> ~/.env_tokens
    gh gist edit "$TABBY_GIST_ID" ~/.env_tokens
    echo "✅ Created new backup gist: $GIST_ID"
else
    # Update existing gist
    for file in *.enc backup-info.txt; do
        gh gist edit "$TABBY_WEB_DB_GIST_ID" -f "$file" "$file"
    done
    echo "✅ Updated backup gist: $TABBY_WEB_DB_GIST_ID"
fi

# Cleanup
rm -rf "$BACKUP_DIR"

echo "🎉 Backup complete!"
echo "   Encrypted with gateway token"
echo "   Stored in gist: $TABBY_WEB_DB_GIST_ID"

# Also create local backup
cp "$DB_PATH" "$HOME/.dotfiles/data/tabby-web/tabby-backup-$TIMESTAMP.db"
echo "   Local backup: tabby-backup-$TIMESTAMP.db"