#!/bin/bash
# Bootstrap New Machine Script
# Sets up environment sync on a new machine

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

echo -e "${CYAN}🚀 New Machine Bootstrap${NC}"
echo "=========================="
echo ""

# Step 1: Check if GitHub CLI exists
log "Checking GitHub CLI availability..."
if ! command -v gh &> /dev/null; then
    warn "GitHub CLI not found. Installing..."
    
    # Install GitHub CLI based on OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update && sudo apt install gh -y
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install gh
        else
            error "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    else
        error "Unsupported OS. Please install GitHub CLI manually: https://cli.github.com/"
        exit 1
    fi
fi

success "GitHub CLI available"

# Step 2: Authenticate with GitHub
log "Checking GitHub authentication..."
if ! gh auth status &>/dev/null; then
    warn "GitHub CLI not authenticated"
    
    echo ""
    echo -e "${CYAN}Choose authentication method:${NC}"
    echo "1) Browser authentication (recommended)"
    echo "2) Personal Access Token (PAT)"
    echo ""
    read -p "Enter choice (1 or 2): " auth_choice
    
    case "$auth_choice" in
        1)
            log "Starting browser authentication..."
            echo ""
            echo -e "${YELLOW}This will open your browser for GitHub authentication.${NC}"
            echo -e "${YELLOW}Make sure to authorize access to gists!${NC}"
            echo ""
            read -p "Press Enter to continue..."
            
            # Browser auth with gist scope
            gh auth login --web --scopes read:user,user:email,gist
            ;;
        2)
            echo ""
            echo -e "${YELLOW}You'll need a Personal Access Token (PAT) with these scopes:${NC}"
            echo "• gist (read/write)"
            echo "• user (read)"
            echo ""
            echo -e "${BLUE}Get your PAT at: https://github.com/settings/tokens${NC}"
            echo ""
            read -p "Enter your Personal Access Token: " -s token
            echo ""
            
            # Token auth
            echo "$token" | gh auth login --with-token
            ;;
        *)
            error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
else
    success "GitHub CLI already authenticated"
fi

# Step 3: Test gist access
log "Testing gist access..."
if gh gist list &>/dev/null; then
    success "Gist access confirmed"
else
    error "Cannot access gists. Please check authentication."
    echo "You may need to re-authenticate with gist permissions:"
    echo "gh auth refresh --scopes read:user,user:email,gist"
    exit 1
fi

# Step 4: Set up shell configurations
log "Setting up shell configurations..."

# Create symlinks for shell configs
if [[ ! -e ~/.bashrc ]]; then
    ln -sf ~/.dotfiles/config/bashrc ~/.bashrc
    success "Created ~/.bashrc symlink"
fi

if [[ ! -e ~/.zshrc ]]; then
    ln -sf ~/.dotfiles/config/zshrc ~/.zshrc
    success "Created ~/.zshrc symlink"
fi

# Fish config requires directory structure
if [[ ! -d ~/.config/fish ]]; then
    mkdir -p ~/.config/fish
fi
if [[ ! -e ~/.config/fish/config.fish ]]; then
    ln -sf ~/.dotfiles/config/fish/config.fish ~/.config/fish/config.fish
    success "Created ~/.config/fish/config.fish symlink"
fi

# Step 5: Set up environment sync
log "Setting up multi-environment sync..."

# Make sync script executable
chmod +x ~/.dotfiles/.scripts/multi-env-sync.sh

# Pull all environment files
if ~/.dotfiles/.scripts/multi-env-sync.sh pull; then
    success "Environment files synced from gists"
else
    warn "Some environment files may not have synced properly"
fi

# Set up automatic sync
if ~/.dotfiles/.scripts/multi-env-sync.sh auto; then
    success "Automatic sync enabled"
else
    warn "Could not enable automatic sync"
fi

# Step 6: Reload shell configuration
log "Reloading shell configuration..."

# Detect current shell and reload appropriate config
current_shell=$(basename "$SHELL")
config_reloaded=false

case "$current_shell" in
    "bash")
        if [[ -f ~/.bashrc ]]; then
            source ~/.bashrc
            success "Bash configuration reloaded"
            config_reloaded=true
        fi
        ;;
    "zsh")
        if [[ -f ~/.zshrc ]]; then
            source ~/.zshrc
            success "Zsh configuration reloaded" 
            config_reloaded=true
        fi
        ;;
    "fish")
        if command -v fish &>/dev/null; then
            fish -c "source ~/.config/fish/config.fish" 2>/dev/null || true
            success "Fish configuration reloaded"
            config_reloaded=true
        fi
        ;;
    *)
        warn "Unknown shell: $current_shell"
        ;;
esac

if [[ "$config_reloaded" == false ]]; then
    warn "Could not reload shell configuration for $current_shell"
    echo "You may need to restart your shell or run: source ~/.${current_shell}rc"
fi

echo ""
echo -e "${CYAN}🎉 Bootstrap Complete!${NC}"
echo "==================="
echo ""
echo -e "${GREEN}Your new machine is now set up with:${NC}"
echo "• Multi-environment file sync"
echo "• Automatic sync every 30 minutes"
echo "• File watcher for immediate sync on changes"
echo "• All your environment variables loaded"
echo ""
echo -e "${BLUE}Available commands:${NC}"
echo "• env-status  - Check sync status"
echo "• env-pull    - Pull from gists"
echo "• env-push    - Push to gists"
echo "• env-watcher - Check watcher service"
echo "• secret-tui  - Manage secrets via TUI"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify your environment files: env-status"
echo "2. Test that all your API keys work"
echo "3. Check the watcher is running: env-watcher"