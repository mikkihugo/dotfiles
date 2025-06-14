#!/bin/bash
set -e

echo "🚀 Starting nexus-hugo-dk..."

# Start Docker daemon
dockerd --host=unix:///var/run/docker.sock --host=tcp://0.0.0.0:2376 &

# Wait for Docker
while ! docker info >/dev/null 2>&1; do
    sleep 1
done
echo "✅ Docker ready"

# Start tunnel
if [ -n "$TUNNEL_TOKEN" ]; then
    cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" &
    echo "✅ Tunnel started"
fi

echo "🎯 nexus-hugo-dk ready"
wait