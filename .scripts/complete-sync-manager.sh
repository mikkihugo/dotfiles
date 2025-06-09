#!/bin/bash

# Complete Sync Manager - One script to sync everything
# Termius ↔ Tabby ↔ SSH Config ↔ Gist

set -e

GIST_ID="${UNIFIED_HOSTS_GIST_ID}"
HOSTS_JSON="$HOME/.sync-hosts.json"

# Check if tools are available
check_tool() {
    local tool="$1"
    local install_cmd="$2"
    
    if ! command -v "$tool" &>/dev/null; then
        echo "⚠️  $tool not found"
        if [ ! -z "$install_cmd" ]; then
            echo "   Install with: $install_cmd"
        fi
        return 1
    fi
    return 0
}

# Sync status
sync_status() {
    echo "🔄 Sync Status:"
    echo ""
    
    # Check tools
    check_tool "termius" "pip install termius" && echo "✅ Termius CLI ready" || echo "❌ Termius CLI missing"
    check_tool "jq" "mise install jq" && echo "✅ jq ready" || echo "❌ jq missing"
    check_tool "yq" "mise install yq" && echo "✅ yq ready" || echo "❌ yq missing"
    check_tool "gh" "mise install gh" && echo "✅ GitHub CLI ready" || echo "❌ GitHub CLI missing"
    
    echo ""
    
    # Check files
    [ -f "$HOME/.ssh/config" ] && echo "✅ SSH config exists" || echo "❌ SSH config missing"
    [ -f "$HOME/.config/tabby/config.yaml" ] && echo "✅ Tabby config exists" || echo "❌ Tabby config missing"
    [ ! -z "$GIST_ID" ] && echo "✅ Gist ID configured" || echo "❌ Gist ID missing"
    
    echo ""
    
    # Check auth
    if termius account 2>/dev/null | grep -q "Email:"; then
        echo "✅ Termius logged in"
    else
        echo "❌ Termius not logged in"
    fi
    
    if gh auth status 2>/dev/null | grep -q "Logged in"; then
        echo "✅ GitHub CLI authenticated"
    else
        echo "❌ GitHub CLI not authenticated"
    fi
}

# Complete migration from Termius to everything
migrate_from_termius() {
    echo "🚀 Complete Migration: Termius → Everything"
    echo ""
    
    # Step 1: Export from Termius
    echo "1️⃣ Exporting from Termius..."
    termius export --output "$HOSTS_JSON"
    
    # Step 2: Push to Gist
    echo "2️⃣ Pushing to Gist..."
    gh gist edit "$GIST_ID" "$HOSTS_JSON"
    
    # Step 3: Generate SSH config
    echo "3️⃣ Generating SSH config..."
    ~/.dotfiles/.scripts/unified-hosts-sync.sh pull
    
    # Step 4: Setup Tabby
    echo "4️⃣ Setting up Tabby..."
    ~/.dotfiles/.scripts/tabby-gist-sync.sh pull
    
    echo ""
    echo "✅ Migration complete!"
    echo ""
    echo "📋 What's been created:"
    echo "  - ~/.ssh/config (SSH hosts)"
    echo "  - ~/.config/tabby/config.yaml (Tabby hosts)"  
    echo "  - Gist backup (cloud sync)"
    echo ""
    echo "📱 Next steps:"
    echo "  1. Install Tabby on all devices"
    echo "  2. Use 'tabby-gist-sync pull' on each device"
    echo "  3. Set up auto-sync with cron/systemd"
}

# Setup auto-sync
setup_auto_sync() {
    echo "⏰ Setting up auto-sync..."
    
    # Create sync script
    cat > "$HOME/.dotfiles/.scripts/auto-sync.sh" << 'EOF'
#!/bin/bash
# Auto-sync all hosts
set -e

# Only sync if connected to internet
if ! ping -c 1 github.com &>/dev/null; then
    exit 0
fi

# Sync from different sources based on what's available
if command -v termius &>/dev/null && termius account 2>/dev/null | grep -q "Email:"; then
    # Termius is primary - export and sync
    ~/.dotfiles/.scripts/termius-cloud-sync.sh sync
elif [ -f ~/.config/tabby/config.yaml ]; then
    # Tabby is primary - push any changes
    ~/.dotfiles/.scripts/tabby-gist-sync.sh sync
else
    # Just pull from gist
    ~/.dotfiles/.scripts/unified-hosts-sync.sh pull
fi
EOF
    
    chmod +x "$HOME/.dotfiles/.scripts/auto-sync.sh"
    
    # Add to bashrc
    if ! grep -q "auto-sync.sh" ~/.bashrc; then
        cat >> ~/.bashrc << 'EOF'

# Auto-sync hosts every 6 hours
SYNC_MARKER="$HOME/.last-host-sync"
if [ ! -f "$SYNC_MARKER" ] || [ $(find "$SYNC_MARKER" -mmin +360 2>/dev/null | wc -l) -gt 0 ]; then
    ~/.dotfiles/.scripts/auto-sync.sh && touch "$SYNC_MARKER" &
fi
EOF
    fi
    
    echo "✅ Auto-sync configured"
}

# Interactive sync all
sync_all() {
    echo "🔄 Syncing everything..."
    
    # Check what's available and sync accordingly
    if command -v termius &>/dev/null && termius account 2>/dev/null | grep -q "Email:"; then
        echo "📱 Syncing from Termius..."
        ~/.dotfiles/.scripts/termius-cloud-sync.sh sync
    fi
    
    if [ -f ~/.config/tabby/config.yaml ]; then
        echo "🖥️ Syncing Tabby..."
        ~/.dotfiles/.scripts/tabby-gist-sync.sh sync
    fi
    
    echo "🔧 Generating SSH config..."
    ~/.dotfiles/.scripts/unified-hosts-sync.sh sync
    
    echo "✅ All synced!"
}

# Main menu
main_menu() {
    while true; do
        echo "
🔄 Complete Sync Manager

Current gist: ${GIST_ID:-NOT SET}

1) Sync status
2) Migrate from Termius 
3) Sync everything
4) Setup auto-sync
5) Manual sync options
6) Exit

"
        read -p "Choose option: " choice
        
        case $choice in
            1)
                sync_status
                ;;
            2)
                migrate_from_termius
                ;;
            3)
                sync_all
                ;;
            4)
                setup_auto_sync
                ;;
            5)
                manual_sync_menu
                ;;
            6)
                exit 0
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Manual sync submenu
manual_sync_menu() {
    echo "
📋 Manual Sync Options

1) Termius → Gist
2) Gist → SSH config  
3) Gist → Tabby
4) Tabby → Gist
5) Back

"
    read -p "Choose option: " choice
    
    case $choice in
        1)
            ~/.dotfiles/.scripts/termius-cloud-sync.sh sync
            ;;
        2)
            ~/.dotfiles/.scripts/unified-hosts-sync.sh pull
            ;;
        3)
            ~/.dotfiles/.scripts/tabby-gist-sync.sh pull
            ;;
        4)
            ~/.dotfiles/.scripts/tabby-gist-sync.sh push
            ;;
        5)
            return
            ;;
    esac
}

# Command line mode
if [ $# -gt 0 ]; then
    case "$1" in
        status)
            sync_status
            ;;
        migrate)
            migrate_from_termius
            ;;
        sync)
            sync_all
            ;;
        setup)
            setup_auto_sync
            ;;
        *)
            echo "Usage: complete-sync-manager [status|migrate|sync|setup]"
            exit 1
            ;;
    esac
else
    main_menu
fi