#!/bin/bash
# Install system dependencies that mise can't handle

set -e

FLAGFILE="$HOME/.dotfiles/.system-deps-installed"

# Check if already installed
if [ -f "$FLAGFILE" ]; then
    echo "✅ System dependencies already installed (flagfile exists)"
    echo "💡 To force reinstall: rm $FLAGFILE && mise run system-deps"
    exit 0
fi

echo "🔧 Installing system dependencies..."
echo "💡 This will install system packages and may require sudo password"
echo ""

# Detect package manager
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    INSTALL_CMD="sudo yum install -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="sudo dnf install -y"
elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
    INSTALL_CMD="sudo pacman -Sy --noconfirm"
else
    echo "❌ No supported package manager found"
    exit 1
fi

echo "📦 Detected package manager: $PKG_MANAGER"

# Check what we need to install
MISSING_PACKAGES=()

if ! command -v tmux >/dev/null 2>&1; then
    MISSING_PACKAGES+=("tmux")
fi

if ! command -v curl >/dev/null 2>&1; then
    MISSING_PACKAGES+=("curl")
fi

if ! command -v git >/dev/null 2>&1; then
    MISSING_PACKAGES+=("git")
fi

# Install missing packages
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "📦 Missing packages: ${MISSING_PACKAGES[*]}"
    echo "🔐 Please enter sudo password to install system packages..."
    
    case $PKG_MANAGER in
        apt)
            sudo apt-get update && sudo apt-get install -y tmux curl wget git build-essential ncurses-dev libevent-dev
            ;;
        yum)
            sudo yum install -y tmux curl wget git gcc make ncurses-devel libevent-devel
            ;;
        dnf)
            sudo dnf install -y tmux curl wget git gcc make ncurses-devel libevent-devel
            ;;
        pacman)
            sudo pacman -Sy --noconfirm tmux curl wget git base-devel ncurses libevent
            ;;
    esac
else
    echo "✅ All essential packages already installed"
fi

# Verify installations
echo ""
echo "🔍 Verifying installations..."
command -v tmux >/dev/null 2>&1 && echo "✅ tmux: $(tmux -V)" || echo "❌ tmux: not found"
command -v curl >/dev/null 2>&1 && echo "✅ curl: $(curl --version | head -1)" || echo "❌ curl: not found"
command -v git >/dev/null 2>&1 && echo "✅ git: $(git --version)" || echo "❌ git: not found"

echo "✅ System dependencies installed!"

# Create flagfile to prevent re-running
echo "$(date): System dependencies installed successfully" > "$FLAGFILE"
echo "📝 Created flagfile: $FLAGFILE"