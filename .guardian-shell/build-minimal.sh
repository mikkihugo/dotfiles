#!/bin/bash
# Minimal build - just what works

cd "$(dirname "$0")"

# Build
echo "Building guardian..."
rustc -O shell-guardian-final.rs -o shell-guardian || exit 1

# Install
echo "Installing..."
install -m 755 shell-guardian ~/.local/bin/

# Test
echo "Testing..."
~/.local/bin/shell-guardian echo "Guardian works!"

echo "Done. Installed to ~/.local/bin/shell-guardian"