#!/bin/bash
# Build minimal guardian

cd "$(dirname "$0")"

echo "Building guardian..."
rustc -O shell-guardian.rs -o shell-guardian || exit 1

echo "Installing to ~/.local/bin/"
mkdir -p ~/.local/bin
install -m 755 shell-guardian ~/.local/bin/

echo "✓ Guardian installed"