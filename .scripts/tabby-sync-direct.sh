#!/bin/bash
# Direct Tabby sync - bypasses retro-login menu

set -e

CONFIG_DIR="$HOME/.config/retro-login"
CONNECTIONS_FILE="$CONFIG_DIR/servers.conf"
TABBY_CONFIG="$HOME/.config/tabby/config.yaml"

echo "🔄 Direct Tabby Sync Starting..."

# Create Tabby config directory
mkdir -p ~/.config/tabby

# Create basic Tabby config if it doesn't exist
if [[ ! -f "$TABBY_CONFIG" ]]; then
    cat > "$TABBY_CONFIG" << 'EOF'
version: 1
ssh:
  connections: []
EOF
    echo "📝 Created new Tabby config"
fi

# Read servers and sync
if [[ -f "$CONNECTIONS_FILE" ]]; then
    synced=0
    while IFS='|' read -r name type host port user key desc; do
        [[ "$name" =~ ^#.*$ ]] && continue  # Skip comments
        [[ -z "$name" ]] && continue        # Skip empty lines
        
        if [[ "$type" == "ssh" ]]; then
            echo "📡 Processing: $name"
            
            # Expand tilde in key path
            if [[ "$key" == "~/"* ]]; then
                key="${key/#\~/$HOME}"
            fi
            
            # Check if already exists
            if grep -q "name: \"$name\"" "$TABBY_CONFIG" 2>/dev/null; then
                echo "   📱 Already exists - skipping"
            else
                # Add to config
                cat >> "$TABBY_CONFIG" << EOF

  - name: "$name"
    host: "$host"
    port: $port
    user: "$user"
    privateKey: "$key"
EOF
                echo "   ✅ Added to Tabby config"
                ((synced++))
            fi
        fi
    done < "$CONNECTIONS_FILE"
    
    echo ""
    echo "✅ Synced $synced new SSH connections to Tabby"
else
    echo "❌ No connections file found at $CONNECTIONS_FILE"
    exit 1
fi

# Show current config
echo ""
echo "📄 Current Tabby config:"
cat "$TABBY_CONFIG"

# Backup to gist if configured
if [[ -n "${TABBY_GIST_ID:-}" ]]; then
    echo ""
    echo "💾 Backing up to gist: $TABBY_GIST_ID"
    if gh gist edit "$TABBY_GIST_ID" "$TABBY_CONFIG" 2>/dev/null; then
        echo "✅ Backup to gist complete"
    else
        echo "❌ Gist backup failed"
    fi
else
    echo ""
    echo "💡 To enable gist backup, set TABBY_GIST_ID in ~/.env_tokens"
fi

echo ""
echo "🎯 Sync complete! Check Tabby for new connections."