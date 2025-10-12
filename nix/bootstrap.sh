#!/bin/bash

# 🚀 PrimeCode Development Environment Bootstrap
# One-command setup for new computers
# Usage: curl -fsSL https://raw.githubusercontent.com/mhugo/.dotfiles/main/nix/bootstrap.sh | bash

set -e

echo "🚀 PrimeCode Development Environment Bootstrap"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ️${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please don't run this script as root"
    exit 1
fi

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    print_error "Unsupported OS: $OSTYPE"
    exit 1
fi

print_info "Detected OS: $OS"

# Check if Nix is available
if command -v nix &> /dev/null; then
    print_status "Nix is available: $(nix --version)"
else
    print_error "Nix is not available. Please install Nix first:"
    print_info "Linux: sh <(curl -L https://nixos.org/nix/install) --no-daemon"
    print_info "macOS: sh <(curl -L https://nixos.org/nix/install)"
    exit 1
fi

# Create necessary directories
print_info "Creating directories..."
mkdir -p ~/.config/nixpkgs
mkdir -p ~/.local/bin
mkdir -p ~/.npm-global/bin

# Clone or update dotfiles
if [ -d ~/.dotfiles ]; then
    print_info "Updating existing dotfiles..."
    cd ~/.dotfiles
    git pull origin main
else
    print_info "Cloning dotfiles repository..."
    git clone https://github.com/mhugo/.dotfiles.git ~/.dotfiles
fi

# Set up Nix configuration
print_info "Setting up Nix configuration..."
cp ~/.dotfiles/nix/nixpkgs-config.nix ~/.config/nixpkgs/config.nix

# Install global Nix packages
print_info "Installing global development tools..."
nix profile install nixpkgs#nodejs_22
nix profile install nixpkgs#pnpm
nix profile install nixpkgs#git
nix profile install nixpkgs#moonrepo
nix profile install nixpkgs#npm
nix profile install nixpkgs#btop

# Install AI tools (unfree packages)
print_info "Installing AI development tools..."
nix profile install nixpkgs#claude-code
nix profile install nixpkgs#gemini-cli
nix profile install nixpkgs#codex
nix profile install nixpkgs#copilot-cli

# Set up daily update script
print_info "Setting up daily updates..."
cp ~/.dotfiles/nix/nix-daily-update.sh ~/.local/bin/
chmod +x ~/.local/bin/nix-daily-update.sh

# Set up cron job for daily updates
print_info "Setting up automated daily updates..."
(crontab -l 2>/dev/null; echo "0 9 * * * ~/.local/bin/nix-daily-update.sh >> ~/.local/logs/nix-updates.log 2>&1") | crontab -

# Create logs directory
mkdir -p ~/.local/logs

# Set up shell configuration
print_info "Setting up shell configuration..."
SHELL_CONFIG=""

if [ -f ~/.bashrc ]; then
    SHELL_CONFIG="~/.bashrc"
elif [ -f ~/.zshrc ]; then
    SHELL_CONFIG="~/.zshrc"
elif [ -f ~/.profile ]; then
    SHELL_CONFIG="~/.profile"
fi

if [ -n "$SHELL_CONFIG" ]; then
    # Add Nix to PATH if not already present
    if ! grep -q "nix-profile" "$SHELL_CONFIG"; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Nix package manager" >> "$SHELL_CONFIG"
        echo 'export PATH="$HOME/.nix-profile/bin:$PATH"' >> "$SHELL_CONFIG"
    fi
    
    # Add local bin to PATH if not already present
    if ! grep -q "\.local/bin" "$SHELL_CONFIG"; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Local binaries" >> "$SHELL_CONFIG"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_CONFIG"
    fi
fi

# Install direnv
print_info "Installing direnv..."
if ! command -v direnv &> /dev/null; then
    nix profile install nixpkgs#direnv
fi

# Set up direnv hook
if [ -n "$SHELL_CONFIG" ]; then
    if ! grep -q "direnv hook" "$SHELL_CONFIG"; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Direnv hook" >> "$SHELL_CONFIG"
        echo 'eval "$(direnv hook bash)"' >> "$SHELL_CONFIG"
    fi
fi

# Create Claude wrapper
print_info "Setting up Claude OAuth wrapper..."
cat > ~/.local/bin/claude << 'EOF'
#!/bin/bash
# Claude Wrapper Script - Forces OAuth token usage

# Claude authentication removed

# Pass all arguments to the original claude command
exec claude "$@"
EOF

chmod +x ~/.local/bin/claude

# Create setup script for individual repos
print_info "Setting up repo integration..."
cp ~/.dotfiles/nix/setup-repo.sh ~/.local/bin/
chmod +x ~/.local/bin/setup-repo.sh

# Create template files
cp ~/.dotfiles/nix/.envrc-template ~/.dotfiles/nix/

# Test installation
print_info "Testing installation..."
echo ""
echo "🧪 Testing installed tools:"
echo "  🌙 Moon:      $(moon --version 2>/dev/null || echo 'Not found')"
echo "  📦 Node.js:   $(node --version 2>/dev/null || echo 'Not found')"
echo "  📦 pnpm:      $(pnpm --version 2>/dev/null || echo 'Not found')"
echo "  🔧 Git:       $(git --version 2>/dev/null | head -1 || echo 'Not found')"
echo "  🤖 Claude:    $(claude --version 2>/dev/null || echo 'Not found')"
echo "  🔮 Gemini:    $(gemini --version 2>/dev/null || echo 'Not found')"
echo "  🧠 Codex:     $(codex --version 2>/dev/null || echo 'Not found')"
echo "  🚀 Copilot:   $(copilot --version 2>/dev/null || echo 'Not found')"

echo ""
echo "🎉 PrimeCode Development Environment Setup Complete!"
echo "=================================================="
echo ""
echo "📋 Next Steps:"
echo "1. Restart your shell or run: source $SHELL_CONFIG"
echo "2. Navigate to a project: cd ~/code/your-project"
echo "3. Set up Nix environment: setup-repo.sh"
echo "4. Allow direnv: direnv allow"
echo "5. Start developing!"
echo ""
echo "🔧 Available Commands:"
echo "  setup-repo.sh     - Set up Nix environment in any repo"
echo "  nix-daily-update.sh - Update all tools manually"
echo "  claude --help     - Claude Code help"
echo "  moon --help       - Moonrepo help"
echo ""
echo "📚 Documentation: ~/.dotfiles/nix/README.md"
echo ""
print_status "Setup complete! Welcome to PrimeCode development! 🚀"