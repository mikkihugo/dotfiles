#!/bin/bash

# Setup Nix environment for individual repos
echo "🔗 Setting up Nix environment for $(basename $(pwd))..."

# Check if we're in a git repo
if [ ! -d ".git" ]; then
    echo "❌ Not in a git repository. Please run this from your repo root."
    exit 1
fi

# Create .envrc if it doesn't exist
if [ ! -f ".envrc" ]; then
    echo "📝 Creating .envrc..."
    cp ~/.dotfiles/nix/.envrc-template .envrc
    echo "✅ .envrc created!"
else
    echo "⚠️  .envrc already exists. Please merge manually."
fi

# Allow direnv
echo "🔓 Allowing direnv..."
direnv allow

# Create repo-specific flake.nix if needed
if [ ! -f "flake.nix" ]; then
    echo "📝 Creating repo-specific flake.nix..."
    cat > flake.nix << 'EOF'
{
  description = "Project-specific development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
          };
        };
      in {
        devShells.default = pkgs.mkShell {
          name = "project-dev";
          packages = [
            # Inherit from global environment
            pkgs.nodejs_22
            pkgs.pnpm
            pkgs.git
            pkgs.moonrepo
            
            # AI Tools
            pkgs.claude-code
            pkgs.gemini-cli
            pkgs.codex
            
            # Development tools
            pkgs.jq
            pkgs.ripgrep
            pkgs.fd
            pkgs.bat
            pkgs.btop
          ];
          shellHook = ''
            echo "🚀 $(basename $(pwd)) Development Environment"
            echo "=========================================="
            echo "📦 Available tools:"
            echo "  🌙 Moon:      $(moon --version)"
            echo "  📦 Node.js:   $(node --version)"
            echo "  📦 pnpm:      $(pnpm --version)"
            echo "  🤖 Claude:    $(claude --version 2>/dev/null || echo 'Not installed')"
            echo "  🔮 Gemini:    $(gemini --version 2>/dev/null || echo 'Not installed')"
            echo "  🧠 Codex:     $(codex --version 2>/dev/null || echo 'Not installed')"
            echo "  🚀 Copilot:   $(copilot --version 2>/dev/null || echo 'Not installed')"
            echo "  🤖 Cursor:   $(cursor-agent --version 2>/dev/null || echo 'Not installed')"
            echo "=========================================="
          '';
        };
      }
    );
}
EOF
    echo "✅ flake.nix created!"
fi

echo ""
echo "✅ Nix environment setup complete for $(basename $(pwd))!"
echo ""
echo "📋 Next steps:"
echo "1. Review .envrc and flake.nix"
echo "2. Commit to git: git add .envrc flake.nix"
echo "3. Enter directory: cd . && direnv allow"
echo "4. Test: moon --version, claude --version"
