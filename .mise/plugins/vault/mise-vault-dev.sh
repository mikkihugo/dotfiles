#!/bin/bash
# Mise plugin for development tools - editors, databases, containers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/vault-client/vault-client.sh"

mise_vault_dev_setup() {
    echo "🛠️  Loading development credentials from vault..."
    
    # Docker Hub
    local docker_user=$(vault_get "docker_username")
    local docker_pass=$(vault_get "docker_password")
    if [ -n "$docker_user" ] && [ -n "$docker_pass" ]; then
        echo "$docker_pass" | docker login -u "$docker_user" --password-stdin 2>/dev/null
        echo "  ✓ Docker Hub configured"
    fi
    
    # NPM Registry
    local npm_token=$(vault_get "npm_token")
    if [ -n "$npm_token" ]; then
        npm config set //registry.npmjs.org/:_authToken "$npm_token"
        echo "  ✓ NPM configured"
    fi
    
    # Cargo/crates.io
    local cargo_token=$(vault_get "cargo_token")
    if [ -n "$cargo_token" ]; then
        mkdir -p ~/.cargo
        echo "[registry]" > ~/.cargo/credentials
        echo "token = \"$cargo_token\"" >> ~/.cargo/credentials
        echo "  ✓ Cargo configured"
    fi
    
    # PyPI
    local pypi_token=$(vault_get "pypi_token")
    if [ -n "$pypi_token" ]; then
        mkdir -p ~/.config/pip
        cat > ~/.config/pip/pip.conf << EOF
[global]
index-url = https://pypi.org/simple
extra-index-url = https://pypi.org/simple

[pypi]
username = __token__
password = $pypi_token
EOF
        echo "  ✓ PyPI configured"
    fi
    
    # Database connections
    local pg_host=$(vault_get "postgres_host")
    local pg_user=$(vault_get "postgres_user")
    local pg_pass=$(vault_get "postgres_password")
    local pg_db=$(vault_get "postgres_database")
    if [ -n "$pg_host" ]; then
        export DATABASE_URL="postgresql://${pg_user}:${pg_pass}@${pg_host}:5432/${pg_db}"
        export PGHOST="$pg_host"
        export PGUSER="$pg_user"
        export PGPASSWORD="$pg_pass"
        export PGDATABASE="$pg_db"
        echo "  ✓ PostgreSQL configured"
    fi
    
    # Redis
    local redis_url=$(vault_get "redis_url")
    if [ -n "$redis_url" ]; then
        export REDIS_URL="$redis_url"
        echo "  ✓ Redis configured"
    fi
    
    # Neovim Copilot
    local copilot_token=$(vault_get "github_copilot_token")
    if [ -n "$copilot_token" ]; then
        mkdir -p ~/.config/github-copilot
        echo "{\"token\": \"$copilot_token\"}" > ~/.config/github-copilot/hosts.json
        echo "  ✓ GitHub Copilot configured"
    fi
}

# Install development tools
mise_vault_dev_install() {
    echo "📦 Installing development tools..."
    
    # Code editors
    if ! command -v nvim &> /dev/null; then
        mise use -g neovim@latest
    fi
    
    # Database clients
    if ! command -v pgcli &> /dev/null; then
        pip install pgcli
    fi
    
    if ! command -v redis-cli &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y redis-tools
    fi
    
    # HTTP clients
    if ! command -v httpie &> /dev/null; then
        pip install httpie
    fi
    
    if ! command -v curlie &> /dev/null; then
        cargo install curlie
    fi
    
    # JSON tools
    if ! command -v jq &> /dev/null; then
        mise use -g jq@latest
    fi
    
    if ! command -v fx &> /dev/null; then
        go install github.com/antonmedv/fx@latest
    fi
    
    # Container tools
    if ! command -v dive &> /dev/null; then
        mise use -g dive@latest
    fi
    
    if ! command -v ctop &> /dev/null; then
        wget https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
        chmod +x /usr/local/bin/ctop
    fi
}

# Configure development environment
mise_vault_dev_config() {
    # Neovim plugins and config
    if [ ! -d ~/.config/nvim ]; then
        git clone https://github.com/mikkihugo/dotfiles.git /tmp/dotfiles
        cp -r /tmp/dotfiles/.config/nvim ~/.config/
        rm -rf /tmp/dotfiles
    fi
    
    # Docker buildx
    docker buildx create --name hugo-builder --use 2>/dev/null || true
    
    # Rust toolchain
    rustup component add rustfmt clippy rust-analyzer 2>/dev/null || true
    
    # Node.js global packages
    npm install -g pnpm yarn tsx 2>/dev/null || true
    
    # Python development tools
    pip install black flake8 mypy pytest 2>/dev/null || true
}

# Setup project templates
mise_vault_dev_templates() {
    mkdir -p ~/templates
    
    # Rust project template
    cat > ~/templates/rust-init.sh << 'EOF'
#!/bin/bash
cargo init --name $1
cat > .gitignore << 'GITIGNORE'
/target
**/*.rs.bk
Cargo.lock
GITIGNORE

cat > rustfmt.toml << 'RUSTFMT'
edition = "2021"
max_width = 100
RUSTFMT
EOF
    
    # Node.js project template
    cat > ~/templates/node-init.sh << 'EOF'
#!/bin/bash
npm init -y
npm install -D typescript @types/node tsx prettier eslint
npx tsc --init
echo "node_modules" > .gitignore
EOF
    
    chmod +x ~/templates/*.sh
}

case "${1:-setup}" in
    setup)
        mise_vault_dev_setup
        ;;
    install)
        mise_vault_dev_install
        ;;
    config)
        mise_vault_dev_config
        ;;
    templates)
        mise_vault_dev_templates
        ;;
    all)
        mise_vault_dev_setup
        mise_vault_dev_install
        mise_vault_dev_config
        mise_vault_dev_templates
        ;;
    *)
        echo "Usage: $0 {setup|install|config|templates|all}"
        ;;
esac