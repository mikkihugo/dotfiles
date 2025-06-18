#!/bin/bash
# Mise plugin for Git/GitHub/GitLab integration with vault

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/vault-client/vault-client.sh"

mise_vault_git_setup() {
    echo "🔧 Loading Git credentials from vault..."
    
    # GitHub
    local github_token=$(vault_get "github_token")
    local github_user=$(vault_get "github_username")
    if [ -n "$github_token" ]; then
        export GITHUB_TOKEN="$github_token"
        export GH_TOKEN="$github_token"
        
        # Configure git credential helper
        git config --global credential.helper store
        echo "https://${github_user:-mikkihugo}:$github_token@github.com" > ~/.git-credentials
        
        # Configure gh CLI
        echo "$github_token" | gh auth login --with-token 2>/dev/null || true
        echo "  ✓ GitHub configured"
    fi
    
    # GitLab
    local gitlab_token=$(vault_get "gitlab_token")
    if [ -n "$gitlab_token" ]; then
        export GITLAB_TOKEN="$gitlab_token"
        export GITLAB_API_TOKEN="$gitlab_token"
        echo "https://gitlab-ci-token:$gitlab_token@gitlab.com" >> ~/.git-credentials
        echo "  ✓ GitLab configured"
    fi
    
    # Gitea
    local gitea_token=$(vault_get "gitea_token")
    local gitea_url=$(vault_get "gitea_url")
    if [ -n "$gitea_token" ] && [ -n "$gitea_url" ]; then
        export GITEA_TOKEN="$gitea_token"
        echo "https://gitea:$gitea_token@${gitea_url#https://}" >> ~/.git-credentials
        echo "  ✓ Gitea configured"
    fi
    
    # Git user config
    local git_name=$(vault_get "git_user_name")
    local git_email=$(vault_get "git_user_email")
    if [ -n "$git_name" ] && [ -n "$git_email" ]; then
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        echo "  ✓ Git user configured: $git_name <$git_email>"
    fi
    
    # SSH keys
    local ssh_key=$(vault_get "ssh_private_key")
    if [ -n "$ssh_key" ]; then
        mkdir -p ~/.ssh
        echo "$ssh_key" > ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa
        
        # Extract public key
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        chmod 644 ~/.ssh/id_rsa.pub
        echo "  ✓ SSH key configured"
    fi
    
    # GPG signing key
    local gpg_key=$(vault_get "gpg_private_key")
    if [ -n "$gpg_key" ]; then
        echo "$gpg_key" | gpg --import 2>/dev/null
        local gpg_id=$(gpg --list-secret-keys --keyid-format LONG | grep sec | awk '{print $2}' | cut -d'/' -f2)
        git config --global user.signingkey "$gpg_id"
        git config --global commit.gpgsign true
        echo "  ✓ GPG signing configured"
    fi
}

# Install git tools
mise_vault_git_install() {
    echo "📦 Installing Git tools..."
    
    # GitHub CLI
    if ! command -v gh &> /dev/null; then
        mise use -g github-cli@latest
    fi
    
    # GitLab CLI
    if ! command -v glab &> /dev/null; then
        mise use -g glab@latest
    fi
    
    # Gitea CLI
    if ! command -v tea &> /dev/null; then
        mise use -g tea@latest
    fi
    
    # Git extras
    if ! command -v git-extras &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y git-extras
    fi
    
    # lazygit
    if ! command -v lazygit &> /dev/null; then
        mise use -g lazygit@latest
    fi
    
    # delta (better git diff)
    if ! command -v delta &> /dev/null; then
        cargo install git-delta
    fi
}

# Configure git aliases and settings
mise_vault_git_config() {
    # Better git log
    git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    
    # Useful aliases
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.st status
    git config --global alias.unstage 'reset HEAD --'
    git config --global alias.last 'log -1 HEAD'
    
    # Delta as pager
    if command -v delta &> /dev/null; then
        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.navigate true
        git config --global delta.theme 'Dracula'
    fi
    
    # Better merge conflict resolution
    git config --global merge.conflictstyle diff3
    
    # Rebase by default
    git config --global pull.rebase true
    
    # Auto stash before rebase
    git config --global rebase.autoStash true
}

# Clone common repos
mise_vault_git_repos() {
    local repos=$(vault_get "git_repos_to_clone")
    if [ -n "$repos" ]; then
        echo "📂 Cloning repositories..."
        mkdir -p ~/code
        cd ~/code
        
        echo "$repos" | tr ',' '\n' | while read -r repo; do
            if [ -n "$repo" ] && [ ! -d "$(basename "$repo" .git)" ]; then
                git clone "$repo"
                echo "  ✓ Cloned $repo"
            fi
        done
    fi
}

case "${1:-setup}" in
    setup)
        mise_vault_git_setup
        ;;
    install)
        mise_vault_git_install
        ;;
    config)
        mise_vault_git_config
        ;;
    repos)
        mise_vault_git_repos
        ;;
    all)
        mise_vault_git_setup
        mise_vault_git_install
        mise_vault_git_config
        mise_vault_git_repos
        ;;
    *)
        echo "Usage: $0 {setup|install|config|repos|all}"
        ;;
esac