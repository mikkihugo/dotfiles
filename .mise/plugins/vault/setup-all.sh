#!/bin/bash
# Master setup script for all mise vault plugins

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Hugo Vault Mise Integration Setup"
echo "===================================="

# Check if vault is accessible
echo "🔍 Checking vault connection..."
if ! PGPASSWORD=hugo psql -h ${VAULT_HOST:-db} -U hugo -d hugo -c '\q' 2>/dev/null; then
    echo "❌ Cannot connect to vault database"
    echo "   Make sure PostgreSQL is running and accessible"
    exit 1
fi
echo "✅ Vault connection OK"

# Make all plugins executable
echo "🔧 Setting up plugins..."
chmod +x $SCRIPT_DIR/mise-vault-*.sh
chmod +x $SCRIPT_DIR/../../../tools/vault-client/*.sh

# Install mise if not present
if ! command -v mise &> /dev/null; then
    echo "📦 Installing mise..."
    curl https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# Run setup for each plugin
plugins=(
    "ai:🤖 AI Tools"
    "cloud:☁️  Cloud Providers"
    "git:🔧 Git & Version Control"
    "dev:🛠️  Development Environment"
    "monitoring:📊 Monitoring & Alerts"
)

for plugin_info in "${plugins[@]}"; do
    IFS=':' read -r plugin name <<< "$plugin_info"
    echo ""
    echo "Setting up $name..."
    
    if [ -f "$SCRIPT_DIR/mise-vault-$plugin.sh" ]; then
        # Run setup
        $SCRIPT_DIR/mise-vault-$plugin.sh setup
        
        # Optionally install tools
        read -p "Install $name tools? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            $SCRIPT_DIR/mise-vault-$plugin.sh install
        fi
    fi
done

# Create global mise configuration
echo ""
echo "📝 Creating global mise configuration..."
mkdir -p ~/.config/mise
cat > ~/.config/mise/config.toml << 'EOF'
[settings]
experimental = true
legacy_version_file = true

[tools]
# Global tools available everywhere
node = "latest"
python = "latest"
rust = "latest"

[env]
# Vault configuration
VAULT_HOST = "${VAULT_HOST:-db}"
VAULT_USER = "${VAULT_USER:-hugo}"
VAULT_PASSWORD = "${VAULT_PASSWORD:-hugo}"
VAULT_DB = "${VAULT_DB:-hugo}"

# Plugin directory
MISE_VAULT_PLUGINS = "$HOME/.dotfiles/.mise/plugins/vault"
EOF

# Add vault integration to shell profile
echo ""
echo "🐚 Adding vault integration to shell profiles..."

# Bash
if [ -f ~/.bashrc ]; then
    if ! grep -q "mise-vault" ~/.bashrc; then
        cat >> ~/.bashrc << 'EOF'

# Hugo Vault Integration
if [ -f ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh ]; then
    source ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh setup 2>/dev/null
fi
EOF
    fi
fi

# Fish
if [ -d ~/.config/fish ]; then
    cat > ~/.config/fish/conf.d/mise-vault.fish << 'EOF'
# Hugo Vault Integration
if test -f ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh
    bash -c "source ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh setup && env" | grep -E '^[A-Z_]+=' | while read -l var
        set -x (echo $var | cut -d= -f1) (echo $var | cut -d= -f2-)
    end
end
EOF
fi

# Zsh
if [ -f ~/.zshrc ]; then
    if ! grep -q "mise-vault" ~/.zshrc; then
        cat >> ~/.zshrc << 'EOF'

# Hugo Vault Integration
if [ -f ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh ]; then
    source ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh setup 2>/dev/null
fi
EOF
    fi
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Available commands:"
echo "  vault-client get <key>     - Get a secret"
echo "  vault-client set <key> <value> - Set a secret"
echo "  vault-client list          - List all keys"
echo "  mise-vault setup           - Load all secrets to environment"
echo "  mise-vault sync <file>     - Sync .env file to vault"
echo ""
echo "To use in your projects, add this to .mise.toml:"
echo '  [hooks]'
echo '  enter = "source ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh setup"'
echo ""
echo "🎉 Happy coding with Hugo Vault!"