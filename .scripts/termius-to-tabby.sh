#!/bin/bash

# Convert Termius export to Tabby config format

set -e

TERMIUS_FILE="${1:-termius.json}"
TABBY_CONFIG="$HOME/.config/tabby/config.yaml"

if [ ! -f "$TERMIUS_FILE" ]; then
    echo "❌ Termius export file not found: $TERMIUS_FILE"
    echo "Export with: termius export --output termius.json"
    exit 1
fi

echo "🔄 Converting Termius to Tabby format..."

# Backup existing Tabby config
if [ -f "$TABBY_CONFIG" ]; then
    cp "$TABBY_CONFIG" "$TABBY_CONFIG.bak"
fi

# Create Tabby config directory
mkdir -p "$HOME/.config/tabby"

# Generate Tabby config
cat > "$TABBY_CONFIG" << 'EOF'
version: 3
hotkeys:
  split-right:
    - Ctrl-Shift-D
  split-down:
    - Ctrl-D
ssh:
  connections: []
terminal:
  fontSize: 14
  shell: default
  colorScheme:
    name: Material
    foreground: '#eceff1'
    background: '#263238'
EOF

# Convert Termius hosts to Tabby SSH connections
echo "  connections:" >> "$TABBY_CONFIG"

jq -r '.hosts[]? | 
    "  - type: ssh\n" +
    "    name: \"\(.label // .address)\"\n" +
    "    group: \"Termius Import\"\n" +
    "    options:\n" +
    "      host: \"\(.address)\"\n" +
    "      port: \(.port // 22)\n" +
    "      user: \"\(.username // "root")\"\n" +
    (if .ssh_key then "      privateKey: \"\(.ssh_key)\"\n" else "" end) +
    "      algorithms: {}\n" +
    "      scripts:\n" +
    "        - expect: \"$\"\n" +
    "          send: \"tmux attach || tmux new -s main\\n\"\n"' \
    "$TERMIUS_FILE" >> "$TABBY_CONFIG" 2>/dev/null || true

# Also convert groups
jq -r '.groups[]? as $group | $group.hosts[]? | 
    "  - type: ssh\n" +
    "    name: \"\(.label // .address)\"\n" +
    "    group: \"\($group.label)\"\n" +
    "    options:\n" +
    "      host: \"\(.address)\"\n" +
    "      port: \(.port // 22)\n" +
    "      user: \"\(.username // "root")\"\n"' \
    "$TERMIUS_FILE" >> "$TABBY_CONFIG" 2>/dev/null || true

echo "✅ Conversion complete!"
echo "📁 Tabby config: $TABBY_CONFIG"
echo ""
echo "Next steps:"
echo "1. Open Tabby"
echo "2. Your Termius hosts are under 'SSH' tab"
echo "3. Install 'Cloud Sync Settings' plugin for sync"
echo ""
echo "To sync with GitHub Gist:"
echo "1. Settings → Plugins → Available → Cloud Sync Settings"
echo "2. Configure with your GitHub token"
echo "3. Choose 'GitHub Gist' as storage"