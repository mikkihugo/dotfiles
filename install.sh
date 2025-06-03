#!/bin/bash
# 🚀 Modern Development Environment Setup
# GitOps-style dotfiles installation

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

echo "🚀 Setting up modern development environment..."

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo "📦 Backup directory: $BACKUP_DIR"

# Backup existing files
backup_file() {
    if [[ -f "$1" ]]; then
        echo "📋 Backing up $1"
        cp "$1" "$BACKUP_DIR/"
    fi
}

# Backup existing configurations
backup_file ~/.bashrc
backup_file ~/.aliases
backup_file ~/.tmux.conf
backup_file ~/.tool-versions
backup_file ~/.config/starship.toml

echo ""
echo "🔧 Installing ASDF and plugins..."

# Install ASDF if not present
if [[ ! -d ~/.asdf ]]; then
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.17.0
    echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
    echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
    source ~/.asdf/asdf.sh
fi

# Install ASDF plugins and tools
echo "📦 Installing development tools..."
asdf plugin add python || true
asdf plugin add nodejs || true
asdf plugin add golang || true
asdf plugin add rust || true
asdf plugin add starship || true
asdf plugin add k9s || true
asdf plugin add bat || true
asdf plugin add fd || true
asdf plugin add fzf || true
asdf plugin add exa || true
asdf plugin add hyperfine || true
asdf plugin add lazygit || true
asdf plugin add github-cli || true

# Install versions from .tool-versions
if [[ -f "$DOTFILES_DIR/.tool-versions" ]]; then
    cp "$DOTFILES_DIR/.tool-versions" ~/.tool-versions
    asdf install
fi

echo ""
echo "⚙️  Installing configuration files..."

# Install config files
cp "$DOTFILES_DIR/config/bashrc" ~/.bashrc
cp "$DOTFILES_DIR/config/aliases" ~/.aliases
cp "$DOTFILES_DIR/config/tmux.conf" ~/.tmux.conf

# Create directories and install starship config
mkdir -p ~/.config
cp "$DOTFILES_DIR/config/starship.toml" ~/.config/

# Install scripts
chmod +x "$DOTFILES_DIR/scripts/"*.sh
cp "$DOTFILES_DIR/scripts/tmux-auto.sh" ~/.tmux-auto.sh
cp "$DOTFILES_DIR/scripts/mosh-wrapper.sh" ~/.mosh-wrapper.sh
cp "$DOTFILES_DIR/scripts/mosh-monitor.sh" ~/.mosh-monitor.sh

echo ""
echo "🎨 Setting up shell integrations..."

# Setup FZF
if command -v fzf >/dev/null; then
    ~/.asdf/installs/fzf/*/install --key-bindings --completion --no-update-rc
fi

echo ""
echo "🐍 Setting up Python with SQLite support..."

# Download and install sqlite-devel for Python building
mkdir -p ~/.local/{include,lib,src}
cd ~/.local/src
if [[ ! -f sqlite-devel-*.rpm ]]; then
    dnf download sqlite-devel 2>/dev/null || echo "Note: Could not download sqlite-devel, Python may not have SQLite support"
    if ls sqlite-devel-*.rpm 1> /dev/null 2>&1; then
        rpm2cpio sqlite-devel-*.rpm | cpio -idmv
        cp -r usr/include/* ~/.local/include/ 2>/dev/null || true
        ln -sf /usr/lib64/libsqlite3.so.0 ~/.local/lib/libsqlite3.so 2>/dev/null || true
    fi
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Restart your terminal or run: source ~/.bashrc"
echo "2. For SSH sessions, tmux will auto-start"
echo "3. Try these commands:"
echo "   - lg          # LazyGit"
echo "   - k9s         # Kubernetes TUI"
echo "   - ls          # Pretty file listing"
echo "   - cat file    # Syntax highlighted"
echo ""
echo "📚 Documentation: See README.md for more details"
echo "🔧 Customization: Edit files in $DOTFILES_DIR/config/"
echo ""
echo "Happy coding! 🚀"