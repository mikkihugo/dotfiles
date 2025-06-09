#!/bin/bash
# Install system dependencies that mise can't handle

set -e

echo "🔧 Installing system dependencies..."

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

# Install tmux if not available
if ! command -v tmux >/dev/null 2>&1; then
    echo "🖥️  Installing tmux..."
    case $PKG_MANAGER in
        apt)
            $INSTALL_CMD tmux
            ;;
        yum|dnf)
            $INSTALL_CMD tmux
            ;;
        pacman)
            $INSTALL_CMD tmux
            ;;
    esac
else
    echo "✅ tmux already installed: $(tmux -V)"
fi

# Install other useful system packages
echo "📚 Installing additional system packages..."
case $PKG_MANAGER in
    apt)
        $INSTALL_CMD curl wget git build-essential ncurses-dev libevent-dev
        ;;
    yum)
        $INSTALL_CMD curl wget git gcc make ncurses-devel libevent-devel
        ;;
    dnf)
        $INSTALL_CMD curl wget git gcc make ncurses-devel libevent-devel
        ;;
    pacman)
        $INSTALL_CMD curl wget git base-devel ncurses libevent
        ;;
esac

echo "✅ System dependencies installed!"