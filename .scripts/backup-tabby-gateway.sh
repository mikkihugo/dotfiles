#!/bin/bash

# Backup Tabby Gateway Docker data and config to GitHub Gist

set -e

# Source tokens
source ~/.env_tokens

CONTAINER_NAME="tabby-gateway"
BACKUP_DIR="/tmp/tabby-gateway-backup"

echo "🔄 Backing up Tabby Gateway data..."

# Create backup directory
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 1. Export container config
echo "📦 Exporting container config..."
docker inspect "$CONTAINER_NAME" > "$BACKUP_DIR/container-config.json"

# 2. Get container logs
echo "📜 Saving container logs..."
docker logs "$CONTAINER_NAME" > "$BACKUP_DIR/gateway.log" 2>&1

# 3. Save deployment info
echo "📋 Saving deployment info..."
cat > "$BACKUP_DIR/deployment.yaml" << EOF
# Tabby Gateway Deployment Info
deployed: $(date)
server: $(hostname)
ip: $(hostname -I | awk '{print $1}')
gateway_url: $TABBY_GATEWAY_URL
container_id: $(docker ps -q -f name=$CONTAINER_NAME)
image: ghcr.io/eugeny/tabby-connection-gateway:master
token: $TABBY_GATEWAY_TOKEN
EOF

# 4. Save docker run command
echo "🐳 Saving docker run command..."
cat > "$BACKUP_DIR/deploy.sh" << 'EOF'
#!/bin/bash
docker run -d \
    --name tabby-gateway \
    --restart unless-stopped \
    -e TABBY_AUTH_TOKEN="$TABBY_GATEWAY_TOKEN" \
    -p 9000:9000 \
    ghcr.io/eugeny/tabby-connection-gateway:master \
    --token-auth \
    --host 0.0.0.0
EOF

# 5. Check if gateway has any volume mounts
echo "💾 Checking for volumes..."
VOLUMES=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{"\n"}}{{end}}')
if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" > "$BACKUP_DIR/volumes.txt"
fi

# 6. Create or update gist
echo "📤 Uploading to GitHub Gist..."

if [ -z "$TABBY_GATEWAY_BACKUP_GIST_ID" ]; then
    # Create new gist
    echo "Creating new backup gist..."
    cd "$BACKUP_DIR"
    GIST_ID=$(gh gist create * --desc "Tabby Gateway Backup $(date)" | grep -oE '[a-f0-9]{32}')
    echo "" >> ~/.env_tokens
    echo "# Tabby Gateway Backup Gist" >> ~/.env_tokens
    echo "export TABBY_GATEWAY_BACKUP_GIST_ID=$GIST_ID" >> ~/.env_tokens
    gh gist edit "$TABBY_GIST_ID" ~/.env_tokens
    echo "✅ Created backup gist: $GIST_ID"
else
    # Update existing gist
    echo "Updating existing backup gist..."
    cd "$BACKUP_DIR"
    for file in *; do
        gh gist edit "$TABBY_GATEWAY_BACKUP_GIST_ID" -f "$file" "$file"
    done
    echo "✅ Updated backup gist: $TABBY_GATEWAY_BACKUP_GIST_ID"
fi

# Cleanup
rm -rf "$BACKUP_DIR"

echo ""
echo "🎉 Backup complete!"
echo "   Gist: https://gist.github.com/$TABBY_GATEWAY_BACKUP_GIST_ID"