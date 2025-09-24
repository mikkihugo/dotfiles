#!/bin/bash
# Helper for PostgreSQL-backed vault integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vault-client.sh"

vault_env_setup() {
    echo "Loading secrets from PostgreSQL vault..."

    local anthropic_key=$(vault_get "anthropic_api_key")
    local openai_key=$(vault_get "openai_api_key")
    local github_token=$(vault_get "github_token")
    local cloudflare_token=$(vault_get "cloudflare_api_token")

    [[ -n "$anthropic_key" ]] && export ANTHROPIC_API_KEY="$anthropic_key"
    [[ -n "$openai_key" ]] && export OPENAI_API_KEY="$openai_key"
    [[ -n "$github_token" ]] && export GITHUB_TOKEN="$github_token"
    [[ -n "$cloudflare_token" ]] && export CLOUDFLARE_API_TOKEN="$cloudflare_token"

    if [[ -n "$github_token" ]]; then
        git config --global credential.helper store
        printf 'https://mikkihugo:%s@github.com\n' "$github_token" > ~/.git-credentials
    fi
}

vault_env_sync() {
    local env_file="${1:-.env}"
    [[ -f "$env_file" ]] || return

    echo "Syncing $env_file to vault..."
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# ]] && continue
        [[ -z "$key" ]] && continue

        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        vault_set "$key" "$value"
        echo "  stored: $key"
    done < "$env_file"
}

vault_env_export() {
    local output_file="${1:-.env}"
    local filter="${2:-}"

    echo "Generating $output_file from vault..."
    {
        echo "# Generated from PostgreSQL vault"
        echo "# $(date)"
        echo

        if [[ -n "$filter" ]]; then
            vault_list | grep -i "$filter" | while read -r key; do
                value=$(vault_get "$key")
                printf '%s="%s"\n' "$key" "$value"
            done
        else
            while IFS='|' read -r key value; do
                printf '%s="%s"\n' "$key" "$value"
            done < <(PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -t -c "SELECT key, value FROM vault ORDER BY key;" 2>/dev/null | sed 's/ //g')
        fi
    } > "$output_file"

    echo "Written to $output_file"
}

case "${1:-}" in
    setup)
        vault_env_setup
        ;;
    sync)
        vault_env_sync "$2"
        ;;
    env)
        vault_env_export "$2" "$3"
        ;;
    *)
        cat <<'USAGE'
Vault helper
Usage: vault-env.sh {setup|sync|env}
  setup              Load secrets from vault into environment
  sync <file>        Push key/value pairs from .env file into vault
  env [file] [filter]  Generate .env file from vault contents
USAGE
        ;;
esac
