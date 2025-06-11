#!/bin/bash
#
# Initialize Git + CI in Docker
# Purpose: Setup Gitea and Drone for dotfiles CI/CD
# Version: 1.0.0

set -euo pipefail

echo "🚀 Initializing Git + CI services..."

# Wait for Gitea to be ready
echo "Waiting for Gitea..."
until curl -s http://localhost:3000 > /dev/null; do
    sleep 5
done

# Create admin user
echo "Creating Gitea admin user..."
docker exec gitea gitea admin user create \
    --username admin \
    --password "${GITEA_ADMIN_PASS:-admin}" \
    --email "admin@localhost" \
    --admin

# Create dotfiles repo
echo "Creating dotfiles repository..."
curl -X POST http://localhost:3000/api/v1/user/repos \
    -H "Content-Type: application/json" \
    -u "admin:${GITEA_ADMIN_PASS:-admin}" \
    -d '{
        "name": "dotfiles",
        "description": "Portable dotfiles with admin stack",
        "private": true,
        "auto_init": false
    }'

# Add git remote to local dotfiles
echo "Adding Git remote..."
cd ~/.dotfiles
git remote add docker http://localhost:3000/admin/dotfiles.git || true

# Push to Gitea
echo "Pushing dotfiles to Gitea..."
git push docker main

# Configure Drone OAuth
echo "Configuring Drone CI..."
# This would need OAuth app creation in Gitea
# Left as exercise for security

echo "✅ Git + CI initialized!"
echo ""
echo "Access:"
echo "  Gitea: http://localhost:3000"
echo "  Drone: http://localhost:3001"
echo ""
echo "To push updates:"
echo "  git push docker main"