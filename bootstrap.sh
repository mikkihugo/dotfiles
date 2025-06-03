#!/bin/bash
# 🚀 Bootstrap dotfiles without Git
# Can be run with: curl -sSL https://raw.githubusercontent.com/mikkihugo/dotfiles/main/bootstrap.sh | bash

set -e

DOTFILES_REPO="mikkihugo/dotfiles"
DOTFILES_DIR="$HOME/dotfiles"

echo "🚀 Bootstrapping dotfiles..."

# Method 1: Try git first
if command -v git >/dev/null 2>&1; then
    echo "✅ Git found, cloning repository..."
    git clone "https://github.com/$DOTFILES_REPO.git" "$DOTFILES_DIR"
    cd "$DOTFILES_DIR" && ./install.sh
    exit 0
fi

# Method 2: Download as tarball without git
echo "📦 Git not found, downloading as archive..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download repository as tarball
echo "⬇️  Downloading dotfiles..."
curl -sL "https://github.com/$DOTFILES_REPO/archive/main.tar.gz" -o dotfiles.tar.gz

# Extract
echo "📂 Extracting files..."
tar -xzf dotfiles.tar.gz
mv dotfiles-main "$DOTFILES_DIR"

# Install git first if possible
echo "🔧 Attempting to install git..."
if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y git || echo "⚠️  Could not install git"
elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y git || echo "⚠️  Could not install git"
fi

# Run installation
cd "$DOTFILES_DIR"
echo "🎯 Running installation..."
./install.sh

# Convert to git repo if git is now available
if command -v git >/dev/null 2>&1; then
    echo "🔄 Converting to git repository..."
    git init
    git remote add origin "https://github.com/$DOTFILES_REPO.git"
    git fetch
    git reset origin/main
    git branch -m main
    git branch --set-upstream-to=origin/main main
    echo "✅ Converted to git repository"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo "✨ Dotfiles bootstrapped successfully!"