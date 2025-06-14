#!/bin/bash
# Start hugo.dk tunnel

cd "$(dirname "$0")"

echo "🚇 Starting hugo.dk tunnel..."
docker-compose up -d

echo "✅ Tunnel started"
docker-compose ps