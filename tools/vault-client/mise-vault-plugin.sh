#!/bin/bash
# Mise plugin for PostgreSQL vault integration
# This allows mise to fetch API keys and tokens from the vault

# Source the vault client
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vault-client.sh"

# Function to setup mise environment with vault secrets
mise_vault_setup() {
    echo "Loading secrets from PostgreSQL vault..."
    
    # API Keys for common services
    local anthropic_key=$(vault_get "anthropic_api_key")
    local openai_key=$(vault_get "openai_api_key")
    local github_token=$(vault_get "github_token")
    local cloudflare_token=$(vault_get "cloudflare_api_token")
    
    # Export for mise tools
    [ -n "$anthropic_key" ] && export ANTHROPIC_API_KEY="$anthropic_key"
    [ -n "$openai_key" ] && export OPENAI_API_KEY="$openai_key"
    [ -n "$github_token" ] && export GITHUB_TOKEN="$github_token"
    [ -n "$cloudflare_token" ] && export CLOUDFLARE_API_TOKEN="$cloudflare_token"
    
    # Set up git credentials
    if [ -n "$github_token" ]; then
        git config --global credential.helper store
        echo "https://mikkihugo:$github_token@github.com" > ~/.git-credentials
    fi
}

# Function to sync .env files with vault
mise_vault_sync() {
    local env_file="${1:-.env}"
    
    if [ -f "$env_file" ]; then
        echo "Syncing $env_file to vault..."
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [ -z "$key" ] && continue
            
            # Remove quotes from value
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            
            # Store in vault
            vault_set "$key" "$value"
            echo "  Stored: $key"
        done < "$env_file"
    fi
}

# Function to generate .env from vault
mise_vault_env() {
    local output_file="${1:-.env}"
    local filter="${2:-}"
    
    echo "Generating $output_file from vault..."
    {
        echo "# Generated from PostgreSQL vault"
        echo "# $(date)"
        echo
        
        if [ -n "$filter" ]; then
            vault_list | grep -i "$filter" | while read -r key; do
                value=$(vault_get "$key")
                echo "${key}=\"${value}\""
            done
        else
            while IFS='|' read -r key value; do
                echo "${key}=\"${value}\""
            done < <(PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -t -c "SELECT key, value FROM vault ORDER BY key;" 2>/dev/null | sed 's/ //g')
        fi
    } > "$output_file"
    
    echo "Written to $output_file"
}

# Main command
case "${1:-}" in
    setup)
        mise_vault_setup
        ;;
    sync)
        mise_vault_sync "$2"
        ;;
    env)
        mise_vault_env "$2" "$3"
        ;;
    *)
        echo "Mise Vault Plugin"
        echo "Usage: $0 {setup|sync|env} [args...]"
        echo "  setup           - Load secrets from vault into environment"
        echo "  sync <file>     - Sync .env file to vault"
        echo "  env [file] [filter] - Generate .env file from vault"
        ;;
esac