#!/bin/bash
# Automatic installation script that does as much as possible without sudo

set -e

echo "🚀 AUTO-INSTALLER: Maximizing automatic setup..."
echo "================================================"

# Create all necessary directories
echo "📁 Creating directory structure..."
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/mise/shims
mkdir -p ~/.config/starship
mkdir -p ~/.ssh
mkdir -p ~/.dotfiles-backups
mkdir -p ~/.tmux/plugins
mkdir -p ~/.npm-global
mkdir -p ~/.cache

# Install mise if missing (no sudo needed)
if [ ! -f "$HOME/.local/bin/mise" ]; then
    echo "📦 Installing mise..."
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
    eval "$($HOME/.local/bin/mise activate bash)"
fi

# Install all mise tools (no sudo needed)
echo "🛠️ Installing development tools via mise..."
cd ~/.dotfiles
mise install --yes || true

# Install tmux plugin manager
if [ ! -d ~/.tmux/plugins/tpm ]; then
    echo "🔌 Installing tmux plugin manager..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# Setup npm global directory (avoid sudo for npm)
echo "📦 Configuring npm to avoid sudo..."
npm config set prefix ~/.npm-global

# Install global npm packages without sudo
echo "🌐 Installing useful npm packages..."
npm install -g --silent \
    tldr \
    how-2 \
    speed-test \
    empty-trash-cli \
    fkill-cli \
    npm-check \
    git-open \
    commitizen \
    2>/dev/null || true

# Setup Python packages in user space
echo "🐍 Installing Python packages..."
if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user --upgrade pip setuptools wheel 2>/dev/null || true
    python3 -m pip install --user \
        httpie \
        tldr \
        glances \
        pipenv \
        poetry \
        black \
        pylint \
        ipython \
        2>/dev/null || true
fi

# Install Rust tools if cargo available
if command -v cargo >/dev/null 2>&1; then
    echo "🦀 Installing Rust tools..."
    cargo install --quiet \
        cargo-update \
        cargo-edit \
        cargo-watch \
        2>/dev/null || true
fi

# Download useful scripts that don't need installation
echo "📥 Downloading standalone tools..."
mkdir -p ~/.local/bin

# Git-extras
if [ ! -f ~/.local/bin/git-extras ]; then
    curl -sSL https://raw.githubusercontent.com/tj/git-extras/master/bin/git-extras -o ~/.local/bin/git-extras
    chmod +x ~/.local/bin/git-extras
fi

# Setup shell integrations
echo "🐚 Setting up shell integrations..."

# Zoxide data import from common directories
if command -v zoxide >/dev/null 2>&1; then
    echo "📍 Training zoxide with common directories..."
    for dir in ~ ~/.dotfiles ~/projects ~/Documents ~/Downloads /tmp /var/log; do
        [ -d "$dir" ] && zoxide add "$dir" 2>/dev/null || true
    done
fi

# Pre-compile completions
echo "🔧 Setting up completions..."
mkdir -p ~/.local/share/bash-completion/completions

# Generate completions for installed tools
for cmd in git gh docker kubectl helm terraform aws gcloud az; do
    if command -v $cmd >/dev/null 2>&1; then
        case $cmd in
            git)
                curl -sSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash \
                    -o ~/.local/share/bash-completion/completions/git 2>/dev/null || true
                ;;
            gh)
                gh completion -s bash > ~/.local/share/bash-completion/completions/gh 2>/dev/null || true
                ;;
            kubectl)
                kubectl completion bash > ~/.local/share/bash-completion/completions/kubectl 2>/dev/null || true
                ;;
        esac
    fi
done

# Pre-create common tmux sessions
if command -v tmux >/dev/null 2>&1; then
    echo "📋 Pre-creating useful tmux sessions..."
    tmux new-session -d -s main 2>/dev/null || true
    tmux new-session -d -s work 2>/dev/null || true
    tmux new-session -d -s temp 2>/dev/null || true
fi

# Download and setup fonts (for better terminal experience)
echo "🔤 Setting up fonts..."
mkdir -p ~/.local/share/fonts

# Nerd Fonts (if not present)
if ! ls ~/.local/share/fonts/*Nerd* >/dev/null 2>&1; then
    echo "Downloading FiraCode Nerd Font..."
    curl -sSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip -o /tmp/FiraCode.zip
    unzip -q /tmp/FiraCode.zip -d ~/.local/share/fonts/ 2>/dev/null || true
    rm -f /tmp/FiraCode.zip
    fc-cache -f ~/.local/share/fonts/ 2>/dev/null || true
fi

# Setup cron jobs
echo "⏰ Setting up scheduled tasks..."
(crontab -l 2>/dev/null || true; echo "0 6 * * * cd ~/.dotfiles && mise run sync >/dev/null 2>&1") | \
    grep -v "mise run sync" | (cat; echo "0 6 * * * cd ~/.dotfiles && mise run sync >/dev/null 2>&1") | crontab -

# Optimize shell startup
echo "⚡ Optimizing shell startup..."
# Pre-generate starship cache
if command -v starship >/dev/null 2>&1; then
    starship module time >/dev/null 2>&1 || true
fi

# Setup git config
echo "🔧 Configuring git..."
git config --global core.excludesfile ~/.gitignore_global
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global fetch.prune true
git config --global diff.colorMoved zebra
git config --global include.path ~/.dotfiles/.gitconfig

# Create useful aliases and functions
echo "💫 Creating helper commands..."
cat > ~/.local/bin/update-all << 'EOF'
#!/bin/bash
# Update everything script
echo "🔄 Updating all packages..."

# Dotfiles
cd ~/.dotfiles && git pull

# Mise tools
mise upgrade
mise install

# NPM packages
npm update -g

# Tmux plugins
~/.tmux/plugins/tpm/bin/update_plugins all

echo "✅ All updates complete!"
EOF
chmod +x ~/.local/bin/update-all

# Create quick backup command
cat > ~/.local/bin/quick-backup << 'EOF'
#!/bin/bash
~/.dotfiles/.scripts/backup-restore.sh backup
echo "💾 Backup location: ~/.dotfiles-backups/"
EOF
chmod +x ~/.local/bin/quick-backup

# Summary of what we've done
echo ""
echo "✅ AUTO-INSTALLATION COMPLETE!"
echo "=============================="
echo ""
echo "🎉 Installed without sudo:"
echo "  • All mise tools (Python, Node, Go, Rust, etc.)"
echo "  • Tmux plugin manager"
echo "  • NPM global packages"
echo "  • Python user packages"
echo "  • Shell completions"
echo "  • Fonts (FiraCode Nerd Font)"
echo "  • Cron job for auto-sync"
echo "  • Helper scripts (update-all, quick-backup)"
echo ""
echo "⚠️  Still need sudo for:"
echo "  • System packages (tmux, curl, git, build-essential)"
echo "  • Run: mise run system-deps"
echo ""
echo "💡 Next steps:"
echo "  1. Restart your shell: exec bash"
echo "  2. Install system deps: mise run system-deps"
echo "  3. Enjoy your supercharged environment! 🚀"