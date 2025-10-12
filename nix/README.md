# 🚀 PrimeCode Development Environment

One-command setup for consistent AI-powered development across all machines.

## 🎯 Quick Start

**Prerequisites:** Nix package manager must be installed first

**New Computer Setup:**
```bash
curl -fsSL https://raw.githubusercontent.com/mhugo/.dotfiles/main/nix/install.sh | bash
```

**That's it!** Everything gets installed automatically.

## 📦 What Gets Installed

### Core Tools
- **Node.js 22** - JavaScript runtime
- **pnpm** - Fast package manager
- **Git** - Version control
- **Moonrepo** - Monorepo orchestration

### AI Development Tools
- **Claude Code** - Anthropic's AI coding assistant
- **Gemini CLI** - Google's AI tools
- **Codex CLI** - OpenAI's code generation
- **Copilot CLI** - GitHub's AI pair programmer
- **Cursor Agent** - Cursor IDE integration

### Development Utilities
- **btop** - Modern system monitor
- **ripgrep** - Fast text search
- **fd** - Fast file finder
- **bat** - Better cat with syntax highlighting
- **jq** - JSON processor

## 🔄 Daily Auto-Updates

All tools update automatically every day at 9 AM. Manual updates:
```bash
~/.local/bin/nix-daily-update.sh
```

## 🏗️ Individual Repo Setup

After global setup, set up any repo:
```bash
cd ~/code/your-project
setup-repo.sh
direnv allow
```

This creates:
- `.envrc` - Loads Nix environment
- `flake.nix` - Repo-specific packages
- Auto-installs cursor-agent

## 📁 File Structure

```
~/.dotfiles/nix/
├── bootstrap.sh          # Main installation script
├── install.sh            # One-liner installer
├── flake.nix             # Global Nix environment
├── nixpkgs-config.nix    # Allow unfree packages
├── nix-daily-update.sh   # Daily update script
├── setup-repo.sh         # Repo setup script
├── .envrc-template       # Template for repo .envrc
└── README.md             # This file
```

## 🎛️ Configuration

### Global Environment
- **Location**: `~/.dotfiles/nix/flake.nix`
- **Purpose**: Shared tools across all repos
- **Updates**: Via daily script

### Repo-Specific Environment
- **Location**: `./flake.nix` in each repo
- **Purpose**: Project-specific packages
- **Updates**: Manual or via moonrepo

### Environment Variables
- **Global**: `~/.dotfiles/nix/.envrc-template`
- **Repo**: `./.envrc` in each repo
- **Purpose**: Project-specific environment setup

## 🔧 Manual Commands

```bash
# Update all tools
nix profile upgrade

# Install specific tool
nix profile install nixpkgs#tool-name

# Remove tool
nix profile remove tool-name

# Check installed packages
nix profile list
```

## 🐛 Troubleshooting

### Nix not found after installation
```bash
source ~/.bashrc
# or restart terminal
```

### AI tools not working
```bash
# Check if unfree packages are allowed
cat ~/.config/nixpkgs/config.nix

# Reinstall with unfree allowed
nix profile install nixpkgs#claude-code
```

### Direnv not loading
```bash
# Allow direnv in repo
direnv allow

# Check .envrc syntax
direnv status
```

## 🔗 Integration with Existing Workflow

### Moonrepo Integration
```bash
# All repos use moonrepo for orchestration
moon run :build    # Build all packages
moon run :test     # Test all packages
moon run :lint      # Lint all packages
```

### VSCode Integration
- Install VSCode direnv extension
- VSCode automatically loads Nix environments
- All tools available in integrated terminal

### Git Integration
- Each repo tracks its own Nix configuration
- Global tools shared via symlinks
- Version controlled environment setup

## 🚀 Advanced Usage

### Custom AI Tools
Add to repo's `flake.nix`:
```nix
packages = [
  pkgs.your-custom-tool
  # ... other packages
];
```

### Environment Variables
Add to repo's `.envrc`:
```bash
export PROJECT_SPECIFIC_VAR="value"
```

### CI/CD Integration
Use Nix in GitHub Actions:
```yaml
- uses: cachix/install-nix-action@v20
- run: nix develop --command moon run :build
```

## 📚 More Information

- [Nix Documentation](https://nixos.org/learn.html)
- [Moonrepo Documentation](https://moonrepo.dev/docs)
- [Direnv Documentation](https://direnv.net/)
- [PrimeCode Architecture](https://github.com/mhugo/zenflow)

---

**🎉 Happy coding with PrimeCode!** 🚀