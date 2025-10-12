#!/bin/bash

# 🚀 PrimeCode One-Command Setup
# Usage: curl -fsSL https://raw.githubusercontent.com/mhugo/.dotfiles/main/nix/install.sh | bash

echo "🚀 PrimeCode Development Environment"
echo "===================================="
echo ""
echo "This will install:"
echo "  🤖 AI tools (Claude, Gemini, Codex, Copilot)"
echo "  🛠️  Development tools (Node.js, pnpm, Moonrepo)"
echo "  🔄 Daily auto-updates"
echo "  🔗 Repo integration scripts"
echo ""
echo "Note: Nix package manager must be installed first"
echo ""
echo "Press Enter to continue or Ctrl+C to cancel..."
read

# Download and run the bootstrap script
curl -fsSL https://raw.githubusercontent.com/mhugo/.dotfiles/main/nix/bootstrap.sh | bash