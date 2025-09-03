#!/bin/bash
# Environment Sync Manager
# Unified interface for managing multiple environment sync methods

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    echo -e "${CYAN}🔧 Environment Sync Manager${NC}"
    echo "============================="
    echo ""
    echo "Unified management for multiple environment sync methods:"
    echo ""
    echo -e "${BLUE}Available Sync Methods:${NC}"
    echo "  1. GitHub Gists (current method)"
    echo "  2. GitHub Repository Secrets"
    echo "  3. Local files only"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo "  status          Show current sync status"
    echo "  setup-gists     Setup GitHub gists sync"
    echo "  setup-secrets   Setup GitHub repository secrets"
    echo "  push-gists      Push to gists"
    echo "  pull-gists      Pull from gists"
    echo "  push-secrets    Push to repository secrets"
    echo "  list-methods    List available sync methods"
    echo "  switch <method> Switch sync method"
    echo ""
    echo -e "${BLUE}Environment Files:${NC}"
    echo "  ~/.env_tokens   - Personal tokens (private)"
    echo "  ~/.env_ai       - AI configurations (can be shared)"
    echo "  ~/.env_docker   - Container configs (can be shared)"
    echo "  ~/.env_repos    - Repository paths (can be shared)"
    echo "  ~/.env_local    - Local machine only (never synced)"
}

show_status() {
    echo -e "${CYAN}📊 Environment Sync Status${NC}"
    echo "=========================="
    echo ""
    
    # Check which env files exist
    echo -e "${BLUE}Local Environment Files:${NC}"
    for env_file in env_tokens env_ai env_docker env_repos env_local; do
        if [ -f "$HOME/.${env_file}" ]; then
            local size=$(stat -f%z "$HOME/.${env_file}" 2>/dev/null || stat -c%s "$HOME/.${env_file}" 2>/dev/null)
            local date=$(stat -f%Sm -t%Y-%m-%d\ %H:%M "$HOME/.${env_file}" 2>/dev/null || stat -c%y "$HOME/.${env_file}" 2>/dev/null | cut -d. -f1)
            echo -e "  ${GREEN}✅ ~/.${env_file}${NC} (${size} bytes, ${date})"
        else
            echo -e "  ${RED}❌ ~/.${env_file}${NC} (missing)"
        fi
    done
    
    echo ""
    
    # Check sync methods
    echo -e "${BLUE}Available Sync Methods:${NC}"
    
    # GitHub CLI check
    if command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ GitHub CLI${NC} (authenticated)"
        echo -e "  ${GREEN}✅ GitHub Gists${NC} (available)"
        echo -e "  ${GREEN}✅ GitHub Secrets${NC} (available)"
    else
        echo -e "  ${RED}❌ GitHub CLI${NC} (not authenticated)"
        echo -e "  ${RED}❌ GitHub Gists${NC} (unavailable)"
        echo -e "  ${RED}❌ GitHub Secrets${NC} (unavailable)"
    fi
    
    # Check existing gist sync
    if [ -f "$HOME/.env_tokens" ] && grep -q "GIST_ID" "$HOME/.env_tokens" 2>/dev/null; then
        echo -e "  ${GREEN}✅ Gist Sync${NC} (configured)"
    else
        echo -e "  ${YELLOW}⚠️  Gist Sync${NC} (not configured)"
    fi
}

list_methods() {
    echo -e "${CYAN}🔄 Available Sync Methods${NC}"
    echo "========================="
    echo ""
    
    echo -e "${BLUE}1. GitHub Gists (Current Default)${NC}"
    echo "   ✅ Private gists for sensitive data"
    echo "   ✅ Easy sharing and versioning"
    echo "   ✅ Works with existing setup"
    echo "   ❌ Limited to text files"
    echo ""
    
    echo -e "${BLUE}2. GitHub Repository Secrets${NC}"
    echo "   ✅ Native GitHub integration"
    echo "   ✅ Fine-grained access control"
    echo "   ✅ Audit logging"
    echo "   ❌ Cannot read secrets directly via CLI"
    echo "   ❌ Requires GitHub Actions for full workflow"
    echo ""
    
    echo -e "${BLUE}3. Local Files Only${NC}"
    echo "   ✅ No network dependencies"
    echo "   ✅ Complete privacy"
    echo "   ❌ No sync between machines"
    echo "   ❌ No backup/recovery"
}

setup_gists() {
    echo -e "${BLUE}🔧 Setting up GitHub Gists sync...${NC}"
    
    if [ -f "$SCRIPT_DIR/claude-auth-gist.sh" ]; then
        "$SCRIPT_DIR/claude-auth-gist.sh" setup
    else
        echo -e "${RED}❌ Gist sync script not found${NC}"
        echo "Expected: $SCRIPT_DIR/claude-auth-gist.sh"
    fi
}

setup_secrets() {
    echo -e "${BLUE}🔧 Setting up GitHub Repository Secrets sync...${NC}"
    
    if [ -f "$SCRIPT_DIR/gh-secrets-sync.sh" ]; then
        "$SCRIPT_DIR/gh-secrets-sync.sh" setup
    else
        echo -e "${RED}❌ GitHub secrets script not found${NC}"
        echo "Expected: $SCRIPT_DIR/gh-secrets-sync.sh"
    fi
}

push_gists() {
    echo -e "${BLUE}📤 Pushing to GitHub Gists...${NC}"
    
    if [ -f "$SCRIPT_DIR/claude-auth-gist.sh" ]; then
        "$SCRIPT_DIR/claude-auth-gist.sh" push
    else
        echo -e "${RED}❌ Gist sync script not found${NC}"
    fi
}

pull_gists() {
    echo -e "${BLUE}📥 Pulling from GitHub Gists...${NC}"
    
    if [ -f "$SCRIPT_DIR/claude-auth-gist.sh" ]; then
        "$SCRIPT_DIR/claude-auth-gist.sh" pull
    else
        echo -e "${RED}❌ Gist sync script not found${NC}"
    fi
}

push_secrets() {
    echo -e "${BLUE}📤 Pushing to GitHub Repository Secrets...${NC}"
    
    if [ -f "$SCRIPT_DIR/gh-secrets-sync.sh" ]; then
        "$SCRIPT_DIR/gh-secrets-sync.sh" push
    else
        echo -e "${RED}❌ GitHub secrets script not found${NC}"
    fi
}

# Main execution
case "${1:-help}" in
    "status")
        show_status
        ;;
    "setup-gists")
        setup_gists
        ;;
    "setup-secrets")
        setup_secrets
        ;;
    "push-gists")
        push_gists
        ;;
    "pull-gists")
        pull_gists
        ;;
    "push-secrets")
        push_secrets
        ;;
    "list-methods")
        list_methods
        ;;
    "help"|*)
        show_help
        ;;
esac