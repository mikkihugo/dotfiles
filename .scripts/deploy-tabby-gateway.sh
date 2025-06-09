#!/bin/bash

# Tabby Gateway Deployment Script
# Deploys Tabby Connection Gateway for team access

set -e

# Configuration
GATEWAY_TOKEN="REDACTED"
GATEWAY_PORT=9000
CONTAINER_NAME="tabby-gateway"

echo "🚀 Deploying Tabby Connection Gateway..."

# Stop existing container if running
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "⏹️  Stopping existing gateway..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Run gateway container
echo "🐳 Starting gateway container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -e TABBY_AUTH_TOKEN="$GATEWAY_TOKEN" \
    -p "$GATEWAY_PORT:9000" \
    ghcr.io/eugeny/tabby-connection-gateway:master \
    --token-auth \
    --host 0.0.0.0

# Wait for container to start
echo "⏳ Waiting for gateway to start..."
sleep 5

# Check if running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "✅ Gateway running successfully!"
    echo ""
    echo "📋 Gateway Details:"
    echo "   URL: ws://$(hostname -I | awk '{print $1}'):$GATEWAY_PORT"
    echo "   Token: $GATEWAY_TOKEN"
    echo "   Container: $CONTAINER_NAME"
    echo ""
    echo "🔧 Configure Tabby Web to use this gateway"
else
    echo "❌ Failed to start gateway"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# Show logs
echo "📜 Recent logs:"
docker logs --tail 10 "$CONTAINER_NAME"