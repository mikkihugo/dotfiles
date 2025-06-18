#!/bin/bash
# Lightweight PostgreSQL vault client
# Can be used by any system to fetch secrets

# Default connection parameters
VAULT_HOST="${VAULT_HOST:-db}"
VAULT_USER="${VAULT_USER:-hugo}"
VAULT_PASSWORD="${VAULT_PASSWORD:-hugo}"
VAULT_DB="${VAULT_DB:-hugo}"
VAULT_PORT="${VAULT_PORT:-5432}"

# Function to get a secret
vault_get() {
    local key="$1"
    PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -t -c "SELECT value FROM vault WHERE key = '$key';" 2>/dev/null | xargs
}

# Function to set a secret
vault_set() {
    local key="$1"
    local value="$2"
    PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -c "INSERT INTO vault (key, value) VALUES ('$key', '$value') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;" 2>/dev/null
}

# Function to list secrets
vault_list() {
    PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -t -c "SELECT key FROM vault ORDER BY key;" 2>/dev/null
}

# Function to delete a secret
vault_delete() {
    local key="$1"
    PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -c "DELETE FROM vault WHERE key = '$key';" 2>/dev/null
}

# Function to export all secrets as environment variables
vault_export() {
    local prefix="${1:-}"
    while IFS='|' read -r key value; do
        if [ -n "$prefix" ]; then
            export "${prefix}_${key^^}=$value"
        else
            export "${key^^}=$value"
        fi
    done < <(PGPASSWORD="$VAULT_PASSWORD" psql -h "$VAULT_HOST" -p "$VAULT_PORT" -U "$VAULT_USER" -d "$VAULT_DB" -t -c "SELECT key, value FROM vault;" 2>/dev/null | sed 's/ //g')
}

# Main command handler
case "${1:-}" in
    get)
        vault_get "$2"
        ;;
    set)
        vault_set "$2" "$3"
        ;;
    list)
        vault_list
        ;;
    delete)
        vault_delete "$2"
        ;;
    export)
        vault_export "$2"
        ;;
    *)
        echo "Usage: $0 {get|set|list|delete|export} [args...]"
        echo "  get <key>           - Get a secret value"
        echo "  set <key> <value>   - Set a secret value"
        echo "  list                - List all secret keys"
        echo "  delete <key>        - Delete a secret"
        echo "  export [prefix]     - Export all secrets as env vars"
        exit 1
        ;;
esac