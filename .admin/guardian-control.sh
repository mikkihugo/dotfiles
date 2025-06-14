#!/bin/bash
# Guardian Control - Manage shell guardian system

GUARDIAN_SOURCE="$HOME/.dotfiles/.guardian-shell/shell-guardian"
GUARDIAN_DEST="$HOME/.local/bin/shell-guardian"
GUARDIAN_LOG="$HOME/.guardian.log"
KEEPER_SOURCE="$HOME/.dotfiles/.guardian-shell/guardian-keeper"
KEEPER_DEST="$HOME/.local/bin/guardian-keeper"

status() {
    echo "=== Shell Guardian Status ==="
    echo ""
    
    if [ -f "$GUARDIAN_SOURCE" ]; then
        echo "Source binary: ✓ Available"
    else
        echo "Source binary: ✗ Not found"
    fi
    
    if [ -f "$GUARDIAN_DEST" ]; then
        echo "Guardian: ✓ Installed"
        echo "Location: $GUARDIAN_DEST"
    else
        echo "Guardian: ✗ Not installed"
    fi
    
    if [ -f "$KEEPER_DEST" ]; then
        echo "Keeper: ✓ Installed (watching guardian)"
        # Check if keeper is running
        if pgrep -f guardian-keeper >/dev/null 2>&1; then
            echo "Keeper status: ✓ Running"
        else
            echo "Keeper status: ✗ Not running"
        fi
    else
        echo "Keeper: ✗ Not installed"
    fi
    
    if [ -n "$ENABLE_SHELL_GUARDIAN" ]; then
        echo "Auto-enable: ✓ Yes (ENABLE_SHELL_GUARDIAN=$ENABLE_SHELL_GUARDIAN)"
    else
        echo "Auto-enable: ✗ No"
    fi
    
    if [ -f "$GUARDIAN_LOG" ]; then
        echo ""
        echo "Recent activity:"
        tail -5 "$GUARDIAN_LOG" 2>/dev/null | sed 's/^/  /'
    fi
}

enable() {
    echo "Enabling shell guardian..."
    
    if [ ! -f "$GUARDIAN_SOURCE" ]; then
        echo "❌ Guardian source not found!"
        echo "Run: $HOME/.dotfiles/.guardian-shell/build.sh"
        return 1
    fi
    
    # Install guardian
    mkdir -p "$(dirname "$GUARDIAN_DEST")"
    cp "$GUARDIAN_SOURCE" "$GUARDIAN_DEST"
    chmod +x "$GUARDIAN_DEST"
    
    # Set environment variable
    echo 'export ENABLE_SHELL_GUARDIAN=1' >> ~/.bashrc
    
    echo "✓ Guardian enabled!"
    echo "  Binary installed to: $GUARDIAN_DEST"
    echo "  Auto-start enabled in .bashrc"
    echo ""
    echo "Restart your shell or run: source ~/.bashrc"
}

disable() {
    echo "Disabling shell guardian..."
    
    # Remove binary
    if [ -f "$GUARDIAN_DEST" ]; then
        rm -f "$GUARDIAN_DEST"
        echo "✓ Guardian binary removed"
    fi
    
    # Remove from bashrc
    if grep -q "ENABLE_SHELL_GUARDIAN" ~/.bashrc; then
        sed -i '/ENABLE_SHELL_GUARDIAN/d' ~/.bashrc
        echo "✓ Auto-start disabled"
    fi
    
    # Clean up log
    if [ -f "$GUARDIAN_LOG" ]; then
        rm -f "$GUARDIAN_LOG"
        echo "✓ Guardian log cleaned"
    fi
    
    echo ""
    echo "Guardian fully disabled. Restart shell to apply."
}

enable_keeper() {
    echo "Enabling guardian keeper..."
    
    if [ ! -f "$KEEPER_SOURCE" ]; then
        # Build keeper first
        cd "$HOME/.dotfiles/.guardian-shell" || return 1
        if [ -f "guardian-keeper.rs" ]; then
            if command -v rustc &>/dev/null; then
                echo "Building keeper..."
                rustc -O guardian-keeper.rs -o guardian-keeper
                KEEPER_SOURCE="$HOME/.dotfiles/.guardian-shell/guardian-keeper"
            else
                echo "❌ Rust compiler not found"
                return 1
            fi
        else
            echo "❌ Keeper source not found"
            return 1
        fi
    fi
    
    # Install keeper
    cp "$KEEPER_SOURCE" "$KEEPER_DEST"
    chmod +x "$KEEPER_DEST"
    
    # Start keeper service
    nohup "$KEEPER_DEST" service > /dev/null 2>&1 &
    
    echo "✓ Keeper enabled and running!"
    echo "  PID: $(pgrep -f guardian-keeper)"
}

disable_keeper() {
    echo "Disabling guardian keeper..."
    
    # Kill keeper process
    if pgrep -f guardian-keeper >/dev/null 2>&1; then
        pkill -f guardian-keeper
        echo "✓ Keeper process stopped"
    fi
    
    # Remove keeper binary
    if [ -f "$KEEPER_DEST" ]; then
        rm -f "$KEEPER_DEST"
        echo "✓ Keeper binary removed"
    fi
    
    # Clean up hidden copies
    echo "Cleaning hidden copies..."
    local locations=(
        ".cache/.guardian-survival"
        ".config/guardian"
        ".config/.guardian"
        ".config/.survival-guardian"
        ".ssh/.guardian-binary"
        ".mozilla/.guardian-backup"
        ".gnupg/.guardian-survival"
        ".local/share/guardian"
        ".local/state/.guardian-binary"
    )
    
    for loc in "${locations[@]}"; do
        if [ -e "$HOME/$loc" ]; then
            rm -rf "$HOME/$loc"
            echo "  ✓ Removed $loc"
        fi
    done
    
    echo "✓ Keeper fully disabled"
}

rebuild() {
    echo "Rebuilding guardian from source..."
    
    cd "$HOME/.dotfiles/.guardian-shell" || return 1
    
    # Build options
    echo "What to build?"
    echo "  1. Guardian only (shell-guardian.rs)"
    echo "  2. Keeper only (guardian-keeper.rs)"
    echo "  3. Both guardian and keeper"
    echo ""
    read -p "Choice [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            if [ -f "shell-guardian.rs" ]; then
                echo "Building guardian..."
                rustc -O shell-guardian.rs -o shell-guardian && echo "✓ Guardian built"
            fi
            ;;
        2)
            if [ -f "guardian-keeper.rs" ]; then
                echo "Building keeper..."
                rustc -O guardian-keeper.rs -o guardian-keeper && echo "✓ Keeper built"
            fi
            ;;
        3)
            if [ -f "shell-guardian.rs" ]; then
                echo "Building guardian..."
                rustc -O shell-guardian.rs -o shell-guardian && echo "✓ Guardian built"
            fi
            if [ -f "guardian-keeper.rs" ]; then
                echo "Building keeper..."
                rustc -O guardian-keeper.rs -o guardian-keeper && echo "✓ Keeper built"
            fi
            ;;
    esac
}

versions() {
    echo "=== Guardian Versions ==="
    echo ""
    
    cd "$HOME/.dotfiles/.guardian-shell" || return 1
    
    if [ -f "minimal-guardian.rs" ]; then
        echo "minimal-guardian.rs:"
        echo "  Lines: $(wc -l < minimal-guardian.rs)"
        echo "  Features: Ultra-minimal, self-repair, crash detection"
        echo "  Size: ~100 lines"
        echo ""
    fi
    
    if [ -f "shell-guardian.rs" ]; then
        echo "shell-guardian.rs:"
        echo "  Lines: $(wc -l < shell-guardian.rs)"
        echo "  Features: Full guardian with logging, recovery modes"
        echo "  Size: ~100-200 lines"
        echo ""
    fi
    
    if [ -f "shell-guardian" ]; then
        echo "Compiled binary:"
        ls -la shell-guardian
        echo "  Built from: $(strings shell-guardian | grep -i "guardian" | head -1 || echo "Unknown")"
    fi
}

case "${1:-status}" in
    status)
        status
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    enable-keeper)
        enable_keeper
        ;;
    disable-keeper)
        disable_keeper
        ;;
    rebuild)
        rebuild
        ;;
    versions)
        versions
        ;;
    *)
        echo "Guardian Control - Manage shell guardian system"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  status         Show guardian and keeper status (default)"
        echo "  enable         Install and enable guardian"
        echo "  disable        Remove and disable guardian"
        echo "  enable-keeper  Enable the keeper (watches guardian)"
        echo "  disable-keeper Remove keeper and hidden copies"
        echo "  rebuild        Rebuild guardian/keeper from source"
        echo "  versions       Show available guardian versions"
        echo ""
        echo "The keeper maintains hidden backup copies of the guardian"
        echo "and automatically restores it if deleted."
        ;;
esac