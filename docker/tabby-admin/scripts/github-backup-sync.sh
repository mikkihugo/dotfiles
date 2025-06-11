#!/bin/bash
#
# GitHub Free Services Integration
# Purpose: Use GitHub's free tier for backup and secrets
# Version: 1.0.0

set -euo pipefail

echo "🐙 GitHub Free Services Setup"
echo ""

# GitHub Free Services:
# 1. Packages (500MB free) - Docker images
# 2. Actions (2000 mins/month) - CI/CD
# 3. Releases (unlimited) - Backup storage
# 4. Secrets (100 per repo) - Encrypted storage
# 5. LFS (1GB free) - Large file storage

# Function to store in GitHub Secrets
store_github_secret() {
    local secret_name=$1
    local secret_value=$2
    
    gh secret set "$secret_name" -b "$secret_value" \
        --repo "mikkihugo/dotfiles-admin"
}

# Function to get from GitHub Secrets (via Actions)
get_github_secret() {
    local secret_name=$1
    
    # This runs in GitHub Actions context
    echo "\${{ secrets.$secret_name }}"
}

# Backup Vault to GitHub Releases
backup_to_github_release() {
    local backup_file=$1
    local release_tag="backup-$(date +%Y%m%d-%H%M%S)"
    
    echo "📦 Creating GitHub release for backup..."
    
    # Create release
    gh release create "$release_tag" \
        --repo "mikkihugo/dotfiles-admin" \
        --title "Admin Stack Backup" \
        --notes "Automated backup of admin stack" \
        --draft=false
    
    # Upload backup file
    gh release upload "$release_tag" "$backup_file" \
        --repo "mikkihugo/dotfiles-admin"
    
    echo "✅ Backup uploaded to GitHub release: $release_tag"
}

# Setup GitHub repository for admin stack
setup_github_repo() {
    echo "🔧 Setting up GitHub repository..."
    
    # Create private repo if doesn't exist
    if ! gh repo view mikkihugo/dotfiles-admin &>/dev/null; then
        gh repo create dotfiles-admin --private \
            --description "Admin stack configuration and backups"
    fi
    
    # Enable GitHub Packages
    gh api repos/mikkihugo/dotfiles-admin \
        --method PATCH \
        -f has_issues=true \
        -f has_wiki=false \
        -f has_downloads=true
    
    # Add secrets
    echo "Adding secrets to GitHub..."
    
    # Get from Vault
    VAULT_TOKEN=$(docker exec vault cat /root/.vault-token)
    
    # Core secrets
    store_github_secret "VAULT_UNSEAL_KEY_1" "$(get_vault_secret unseal_key_1)"
    store_github_secret "VAULT_UNSEAL_KEY_2" "$(get_vault_secret unseal_key_2)"
    store_github_secret "VAULT_UNSEAL_KEY_3" "$(get_vault_secret unseal_key_3)"
    store_github_secret "CF_API_TOKEN" "$(get_vault_secret cf_api_token)"
    store_github_secret "GOOGLE_SA_KEY" "$(get_vault_secret google_sa_key)"
    
    echo "✅ GitHub repository configured!"
}

# Docker image backup to GitHub Packages
backup_docker_images() {
    echo "🐳 Pushing Docker images to GitHub Packages..."
    
    # Login to GitHub Container Registry
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u mikkihugo --password-stdin
    
    # Tag and push images
    for image in tabby-web admin-ui warpgate; do
        docker tag "$image:latest" "ghcr.io/mikkihugo/admin-stack/$image:latest"
        docker tag "$image:latest" "ghcr.io/mikkihugo/admin-stack/$image:$(date +%Y%m%d)"
        
        docker push "ghcr.io/mikkihugo/admin-stack/$image:latest"
        docker push "ghcr.io/mikkihugo/admin-stack/$image:$(date +%Y%m%d)"
    done
    
    echo "✅ Docker images backed up to GitHub Packages!"
}

# Main backup function
perform_github_backup() {
    echo "🔄 Starting GitHub backup..."
    
    # Create backup
    BACKUP_FILE="/tmp/admin-backup-$(date +%Y%m%d-%H%M%S).tar.gz.enc"
    
    # Export Vault
    docker exec vault vault operator raft snapshot save /tmp/vault.snap
    docker cp vault:/tmp/vault.snap /tmp/
    
    # Create archive
    tar czf - \
        /tmp/vault.snap \
        ~/.dotfiles/docker/tabby-admin \
        | openssl enc -aes-256-cbc -pbkdf2 -k "$BACKUP_KEY" > "$BACKUP_FILE"
    
    # Upload to GitHub Release
    backup_to_github_release "$BACKUP_FILE"
    
    # Also backup Docker images
    backup_docker_images
    
    # Clean up
    rm -f /tmp/vault.snap "$BACKUP_FILE"
    
    echo "✅ Backup complete!"
}

# Restore function
restore_from_github() {
    local release_tag=${1:-latest}
    
    echo "🔄 Restoring from GitHub..."
    
    # Download latest backup
    gh release download "$release_tag" \
        --repo "mikkihugo/dotfiles-admin" \
        --pattern "*.tar.gz.enc" \
        --dir /tmp
    
    # Decrypt and extract
    BACKUP_FILE=$(ls /tmp/admin-backup-*.tar.gz.enc | head -1)
    openssl enc -d -aes-256-cbc -pbkdf2 -k "$BACKUP_KEY" < "$BACKUP_FILE" \
        | tar xzf - -C /
    
    echo "✅ Restore complete!"
}

# GitHub Actions workflow generator
generate_github_workflow() {
    cat > .github/workflows/admin-stack.yml << 'EOF'
name: Admin Stack Management

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:
    inputs:
      action:
        description: 'Action to perform'
        required: true
        default: 'backup'
        type: choice
        options:
          - backup
          - restore
          - unlock

jobs:
  admin-stack:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup gcloud
        uses: google-github-actions/setup-gcloud@v1
        with:
          service_account_key: ${{ secrets.GOOGLE_SA_KEY }}
          
      - name: Unlock Vault
        run: |
          echo "${{ secrets.VAULT_UNSEAL_KEY_1 }}" | vault operator unseal
          echo "${{ secrets.VAULT_UNSEAL_KEY_2 }}" | vault operator unseal
          echo "${{ secrets.VAULT_UNSEAL_KEY_3 }}" | vault operator unseal
          
      - name: Perform Action
        run: |
          case "${{ github.event.inputs.action }}" in
            backup)
              ./scripts/github-backup-sync.sh backup
              ;;
            restore)
              ./scripts/github-backup-sync.sh restore
              ;;
            unlock)
              ./scripts/layered-unlock.sh
              ;;
          esac
EOF
}

# Main
case "${1:-setup}" in
    setup)
        setup_github_repo
        generate_github_workflow
        ;;
    backup)
        perform_github_backup
        ;;
    restore)
        restore_from_github "${2:-latest}"
        ;;
    push-images)
        backup_docker_images
        ;;
    *)
        echo "Usage: $0 {setup|backup|restore|push-images}"
        exit 1
        ;;
esac