#!/bin/bash

# Termius sync script - sync hosts and settings with gist
# Requires: termius CLI, gh CLI, jq

set -e

GIST_ID="${TERMIUS_GIST_ID:-}"
SYNC_FILE="$HOME/.termius-sync.json"
TEMP_FILE="/tmp/termius-export-$$.json"

# Check dependencies
check_deps() {
    local missing=()
    
    command -v termius &>/dev/null || missing+=("termius")
    command -v gh &>/dev/null || missing+=("gh")
    command -v jq &>/dev/null || missing+=("jq")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing[*]}"
        echo "Install with:"
        echo "  pip install termius"
        echo "  mise install gh jq"
        exit 1
    fi
    
    if [ -z "$GIST_ID" ]; then
        echo "Error: TERMIUS_GIST_ID not set in ~/.env_tokens"
        exit 1
    fi
}

# Export from Termius
export_termius() {
    echo "Exporting Termius data..."
    
    # Check if logged in
    if ! termius account 2>/dev/null | grep -q "Email:"; then
        echo "Not logged into Termius. Run: termius login"
        exit 1
    fi
    
    # Export everything
    termius export --output "$TEMP_FILE"
    
    # Add metadata
    jq '. + {
        "export_date": now | strftime("%Y-%m-%d %H:%M:%S"),
        "export_host": env.HOSTNAME,
        "version": "1.0"
    }' "$TEMP_FILE" > "$SYNC_FILE"
    
    rm -f "$TEMP_FILE"
    echo "Export complete: $SYNC_FILE"
}

# Import to Termius
import_termius() {
    echo "Importing Termius data..."
    
    if [ ! -f "$SYNC_FILE" ]; then
        echo "No sync file found. Run 'sync pull' first."
        exit 1
    fi
    
    # Backup current data
    termius export --output "$HOME/.termius-backup-$(date +%Y%m%d-%H%M%S).json"
    
    # Import
    termius import --input "$SYNC_FILE"
    echo "Import complete"
}

# Push to gist
push_gist() {
    echo "Pushing to gist..."
    
    if [ ! -f "$SYNC_FILE" ]; then
        export_termius
    fi
    
    # Encrypt if key is set
    if [ ! -z "$TERMIUS_ENCRYPT_KEY" ]; then
        echo "Encrypting data..."
        openssl enc -aes-256-cbc -salt -in "$SYNC_FILE" -out "${SYNC_FILE}.enc" -k "$TERMIUS_ENCRYPT_KEY"
        gh gist edit "$GIST_ID" "${SYNC_FILE}.enc"
        rm -f "${SYNC_FILE}.enc"
    else
        gh gist edit "$GIST_ID" "$SYNC_FILE"
    fi
    
    echo "Pushed to gist: $GIST_ID"
}

# Pull from gist
pull_gist() {
    echo "Pulling from gist..."
    
    # Download
    if [ ! -z "$TERMIUS_ENCRYPT_KEY" ]; then
        gh gist view "$GIST_ID" > "${SYNC_FILE}.enc"
        echo "Decrypting data..."
        openssl enc -d -aes-256-cbc -in "${SYNC_FILE}.enc" -out "$SYNC_FILE" -k "$TERMIUS_ENCRYPT_KEY"
        rm -f "${SYNC_FILE}.enc"
    else
        gh gist view "$GIST_ID" > "$SYNC_FILE"
    fi
    
    echo "Pulled from gist: $GIST_ID"
}

# Apply default settings to all hosts
apply_defaults() {
    echo "Applying default settings to all hosts..."
    
    local startup_cmd="${1:-tmux attach || tmux new -s main}"
    
    # Get all host IDs
    termius hosts list --format json | jq -r '.[].id' | while read -r host_id; do
        echo "Updating host $host_id..."
        termius host update "$host_id" \
            --startup-script "$startup_cmd" \
            --terminal-type "xterm-256color" || true
    done
    
    echo "Default settings applied"
}

# List hosts
list_hosts() {
    echo "Termius hosts:"
    termius hosts list --format table
}

# Show usage
usage() {
    cat << EOF
Termius Sync Manager

Usage: termius-sync <command> [options]

Commands:
  export          Export Termius data to local file
  import          Import Termius data from local file
  push            Export and push to gist
  pull            Pull from gist
  sync            Pull from gist and import
  apply-defaults  Apply default settings to all hosts
  list            List all hosts
  
Options:
  --startup-cmd   Custom startup command for apply-defaults
  
Environment variables:
  TERMIUS_GIST_ID      Required: Gist ID for sync
  TERMIUS_ENCRYPT_KEY  Optional: Encryption key
  
Examples:
  termius-sync push                    # Backup to gist
  termius-sync sync                    # Restore from gist
  termius-sync apply-defaults          # Apply default tmux command
  termius-sync apply-defaults "bash"   # Apply custom startup
EOF
}

# Main
check_deps

case "${1:-help}" in
    export)
        export_termius
        ;;
    import)
        import_termius
        ;;
    push)
        export_termius
        push_gist
        ;;
    pull)
        pull_gist
        ;;
    sync)
        pull_gist
        import_termius
        ;;
    apply-defaults)
        apply_defaults "$2"
        ;;
    list)
        list_hosts
        ;;
    *)
        usage
        ;;
esac