#!/bin/bash

# Enhanced SSH/Session Menu
# Combines tmux sessions with SSH connections from tabby-sync

set -e

# Enhanced menu with SSH + tmux
show_enhanced_menu() {
    local force="$1"
    
    # Debug info (comment out in production)
    # echo "DEBUG: Interactive: $-"
    # echo "DEBUG: TMUX: $TMUX"
    # echo "DEBUG: MENU_ENABLED: $MENU_ENABLED"
    
    # Exit if not interactive (unless forced)
    if [ "$force" != "force" ]; then
        [[ $- != *i* ]] && return
        
        # Only skip if we're actually inside a tmux pane (not just inherited TMUX var)
        if [ ! -z "$TMUX" ] && [ ! -z "$TMUX_PANE" ]; then
            return
        fi
        
        # Skip if disabled
        [ "${MENU_ENABLED}" = "false" ] && return
    fi
    
    # Check if we have a proper TTY for gum
    if command -v gum &>/dev/null && [ -t 0 ] && [ -t 1 ] && [ -c /dev/tty ]; then
        show_gum_menu
    else
        show_basic_menu
    fi
}

# Gum-powered menu
show_gum_menu() {
    local options=()
    local header="🚀 SESSION & CONNECTION MANAGER"
    
    # Add tmux sessions with better formatting
    local sessions=$(tmux list-sessions -F "#{session_name}:#{?session_attached,[ATTACHED],[FREE]}:#{session_windows}w:#{session_created_string}" 2>/dev/null)
    if [ ! -z "$sessions" ]; then
        options+=("📋 TMUX SESSIONS")
        while IFS= read -r session; do
            local name=$(echo "$session" | cut -d: -f1)
            local status=$(echo "$session" | cut -d: -f2)
            local windows=$(echo "$session" | cut -d: -f3)
            local created=$(echo "$session" | cut -d: -f4)
            if [[ "$status" == "[ATTACHED]" ]]; then
                options+=("  🟢 $name $status $windows")
            else
                options+=("  🔵 $name $status $windows")
            fi
        done <<< "$sessions"
        options+=("")
    fi
    
    # Add SSH hosts from tabby-sync
    if [ -f "$HOME/.tabby-hosts.json" ]; then
        local ssh_count=$(jq -r '.hosts | length' "$HOME/.tabby-hosts.json" 2>/dev/null || echo "0")
        if [ "$ssh_count" -gt 0 ]; then
            options+=("🌐 SSH CONNECTIONS ($ssh_count hosts)")
            jq -r '.hosts[] | "  🔗 \(.alias) → \(.user)@\(.hostname)"' "$HOME/.tabby-hosts.json" 2>/dev/null | head -10 | while read -r host; do
                options+=("$host")
            done
            options+=("")
        fi
    fi
    
    # Add actions
    options+=(
        "✨ New tmux session"
        "🔄 Kill tmux session"
        "🐚 Plain bash shell"
        "💾 Restore tmux sessions"
        "🔄 Sync SSH hosts"
        "⚙️  Quick tools"
        "🧹 Clear screen"
        "❌ Exit"
    )
    
    local choice=$(printf '%s\n' "${options[@]}" | gum choose \
        --header "$header" \
        --header.foreground="212" \
        --cursor.foreground="212" \
        --selected.foreground="212" \
        --height=20)
    
    handle_choice "$choice"
}

# Handle menu choice
handle_choice() {
    local choice="$1"
    
    case "$choice" in
        "  🟢 "* | "  🔵 "*)
            # Attach to tmux session
            local session_name=$(echo "$choice" | awk '{print $2}')
            tmux attach-session -t "$session_name"
            exit
            ;;
        "  🔗 "*)
            # SSH connection
            local alias=$(echo "$choice" | sed 's/.*🔗 \([^ ]*\) →.*/\1/')
            echo "🔗 Connecting to $alias..."
            ssh "$alias"
            ;;
        "✨ New tmux session")
            local name=$(gum input --placeholder "Session name" --header "New TMUX Session")
            if [ ! -z "$name" ]; then
                tmux new-session -s "$name"
                exit
            fi
            ;;
        "🔄 Kill tmux session")
            local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
            if [ ! -z "$sessions" ]; then
                local session=$(echo "$sessions" | gum choose --header "Select session to kill")
                if [ ! -z "$session" ]; then
                    tmux kill-session -t "$session"
                    echo "🗑️  Killed session: $session"
                    sleep 1
                fi
            fi
            show_gum_menu
            ;;
        "🐚 Plain bash shell")
            exec bash --login
            ;;
        "💾 Restore tmux sessions")
            ~/.dotfiles/.scripts/tmux-save-restore.sh restore
            ;;
        "🔄 Sync SSH hosts")
            echo "🔄 Syncing SSH hosts..."
            tabby-sync pull
            echo "✅ Sync complete!"
            show_gum_menu
            ;;
        "⚙️  Quick tools")
            show_tools_menu
            ;;
        "🧹 Clear screen")
            clear
            show_gum_menu
            ;;
        "❌ Exit")
            exit 0
            ;;
        "")
            # Empty choice, show menu again
            show_gum_menu
            ;;
    esac
}

# Tools submenu
show_tools_menu() {
    local tools_options=(
        "📊 System info (htop/btop)"
        "📁 File manager (ranger/lf)"
        "🔍 Find files (fzf)"
        "📝 Edit dotfiles"
        "🏠 Back to main menu"
    )
    
    local tool_choice=$(printf '%s\n' "${tools_options[@]}" | gum choose \
        --header "⚙️ QUICK TOOLS" \
        --height=8)
    
    case "$tool_choice" in
        "📊 System info"*)
            if command -v btop &>/dev/null; then
                btop
            elif command -v htop &>/dev/null; then
                htop
            else
                top
            fi
            ;;
        "📁 File manager"*)
            if command -v ranger &>/dev/null; then
                ranger
            elif command -v lf &>/dev/null; then
                lf
            else
                echo "No file manager found. Install: mise install ranger"
                read -p "Press Enter to continue..."
            fi
            show_gum_menu
            ;;
        "🔍 Find files"*)
            if command -v fzf &>/dev/null; then
                local file=$(find . -type f 2>/dev/null | fzf --preview 'bat --color=always {}' --height=50%)
                if [ ! -z "$file" ]; then
                    ${EDITOR:-nano} "$file"
                fi
            else
                echo "fzf not found. Install: mise install fzf"
                read -p "Press Enter to continue..."
            fi
            show_gum_menu
            ;;
        "📝 Edit dotfiles")
            cd ~/.dotfiles
            ${EDITOR:-nano} .
            show_gum_menu
            ;;
        "🏠 Back to main menu")
            show_gum_menu
            ;;
    esac
}

# Basic fallback menu
show_basic_menu() {
    echo "
🚀 SESSION MANAGER

TMUX Sessions:"
    tmux list-sessions 2>/dev/null | nl || echo "  No sessions"
    
    echo "
Actions:
  1) Attach to session
  2) New session  
  3) Plain shell
  4) Exit
"
    read -p "Choice: " choice
    
    case $choice in
        1)
            read -p "Session name: " session
            tmux attach -t "$session" 2>/dev/null || echo "Session not found"
            ;;
        2)
            read -p "New session name: " name
            tmux new-session -s "$name"
            ;;
        3)
            exec bash --login
            ;;
        4)
            exit 0
            ;;
    esac
}

# Auto-run if sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    show_enhanced_menu "$1"
fi

# Export for sourcing
export -f show_enhanced_menu