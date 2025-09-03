#!/bin/bash
# GitHub Secrets Integration for Environment Variables
# Alternative to gist-based storage using GitHub repository secrets

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_OWNER="mikkihugo"
SECRETS_REPO="dotfiles-secrets"  # Private repo for secrets
ENV_FILES=("env_tokens" "env_ai" "env_docker" "env_repos")

# Help function
show_help() {
    echo -e "${BLUE}GitHub Secrets Sync Tool${NC}"
    echo "=========================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  push     Upload local env files to GitHub secrets"
    echo "  pull     Download secrets to local env files"
    echo "  list     List available secrets"
    echo "  setup    Initial setup (create private repo)"
    echo "  status   Show sync status"
    echo ""
    echo "Examples:"
    echo "  $0 push                    # Upload all env files"
    echo "  $0 pull                    # Download all secrets"
    echo "  $0 push env_tokens         # Upload specific file"
    echo "  $0 pull env_ai             # Download specific secret"
}

# Check if gh CLI is available
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}❌ GitHub CLI (gh) is not installed${NC}"
        echo "Install with: sudo apt install gh"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        echo -e "${RED}❌ Not authenticated with GitHub${NC}"
        echo "Run: gh auth login"
        exit 1
    fi
}

# Setup private repository for secrets
setup_secrets_repo() {
    echo -e "${BLUE}🔧 Setting up GitHub secrets repository...${NC}"
    
    # Check if repo exists
    if gh repo view "$REPO_OWNER/$SECRETS_REPO" &> /dev/null; then
        echo -e "${GREEN}✅ Repository $SECRETS_REPO already exists${NC}"
        return 0
    fi
    
    # Create private repository
    echo -e "${YELLOW}📦 Creating private repository: $SECRETS_REPO${NC}"
    gh repo create "$SECRETS_REPO" --private --description "Private environment variables and secrets"
    
    # Create initial README
    cat > /tmp/secrets-readme.md << EOF
# Dotfiles Secrets Repository

This private repository stores environment variables and secrets for the dotfiles system.

**⚠️ SECURITY WARNING: This repository contains sensitive data and should remain private.**

## Contents

- Environment variables from local \`~/.env_*\` files
- Stored as GitHub repository secrets
- Automatically synced via \`gh-secrets-sync.sh\`

## Usage

This repository is managed by the dotfiles automation system. 
Manual editing is not recommended.
EOF

    # Initialize repo with README
    cd /tmp
    git clone "git@github.com:$REPO_OWNER/$SECRETS_REPO.git" || git clone "https://github.com/$REPO_OWNER/$SECRETS_REPO.git"
    cd "$SECRETS_REPO"
    mv ../secrets-readme.md README.md
    git add README.md
    git commit -m "Initial commit: Setup secrets repository"
    git push
    cd - > /dev/null
    rm -rf "/tmp/$SECRETS_REPO"
    
    echo -e "${GREEN}✅ Secrets repository created successfully${NC}"
}

# Push local env files to GitHub secrets
push_secrets() {
    local file_filter="$1"
    echo -e "${BLUE}📤 Pushing environment files to GitHub secrets...${NC}"
    
    for env_file in "${ENV_FILES[@]}"; do
        # Skip if filtering and doesn't match
        if [ -n "$file_filter" ] && [ "$env_file" != "$file_filter" ]; then
            continue
        fi
        
        local file_path="$HOME/.${env_file}"
        local secret_name="${env_file^^}"  # Convert to uppercase
        
        if [ -f "$file_path" ]; then
            echo -e "${YELLOW}🔄 Uploading $env_file...${NC}"
            
            # Read file content and set as secret
            if gh secret set "$secret_name" --repo "$REPO_OWNER/$SECRETS_REPO" --body-file "$file_path"; then
                echo -e "${GREEN}✅ $env_file uploaded successfully${NC}"
            else
                echo -e "${RED}❌ Failed to upload $env_file${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  $file_path not found, skipping...${NC}"
        fi
    done
}

# Pull secrets from GitHub to local env files
pull_secrets() {
    local file_filter="$1"
    echo -e "${BLUE}📥 Pulling secrets from GitHub to local env files...${NC}"
    
    for env_file in "${ENV_FILES[@]}"; do
        # Skip if filtering and doesn't match
        if [ -n "$file_filter" ] && [ "$env_file" != "$file_filter" ]; then
            continue
        fi
        
        local file_path="$HOME/.${env_file}"
        local secret_name="${env_file^^}"
        
        echo -e "${YELLOW}🔄 Downloading $env_file...${NC}"
        
        # Note: GitHub CLI doesn't support reading secret values directly for security
        # This would require GitHub API with proper authentication
        echo -e "${RED}❌ Direct secret reading not supported by gh CLI${NC}"
        echo -e "${YELLOW}💡 Use GitHub Actions or API with proper authentication${NC}"
        echo -e "${BLUE}🔗 Secret URL: https://github.com/$REPO_OWNER/$SECRETS_REPO/settings/secrets/actions${NC}"
    done
}

# List available secrets
list_secrets() {
    echo -e "${BLUE}📋 Available secrets in repository:${NC}"
    gh secret list --repo "$REPO_OWNER/$SECRETS_REPO" || echo -e "${RED}❌ Failed to list secrets${NC}"
}

# Show sync status
show_status() {
    echo -e "${BLUE}📊 Environment Files Sync Status${NC}"
    echo "================================="
    echo ""
    
    for env_file in "${ENV_FILES[@]}"; do
        local file_path="$HOME/.${env_file}"
        local secret_name="${env_file^^}"
        
        if [ -f "$file_path" ]; then
            local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
            local file_date=$(stat -f%Sm -t%Y-%m-%d\ %H:%M "$file_path" 2>/dev/null || stat -c%y "$file_path" 2>/dev/null | cut -d. -f1 || echo "Unknown")
            echo -e "${GREEN}✅ $env_file${NC} ($file_size bytes, modified: $file_date)"
        else
            echo -e "${RED}❌ $env_file${NC} (missing)"
        fi
    done
    
    echo ""
    echo -e "${BLUE}🔗 Repository: https://github.com/$REPO_OWNER/$SECRETS_REPO${NC}"
}

# Main execution
main() {
    check_gh_cli
    
    case "${1:-help}" in
        "setup")
            setup_secrets_repo
            ;;
        "push")
            push_secrets "$2"
            ;;
        "pull")
            pull_secrets "$2"
            ;;
        "list")
            list_secrets
            ;;
        "status")
            show_status
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

main "$@"