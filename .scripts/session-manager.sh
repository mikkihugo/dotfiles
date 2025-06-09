#!/bin/bash

# Enhanced session manager with multiple tools support
# Supports: tmux, zellij, or plain shell

SESSION_MANAGER="${SESSION_MANAGER:-tmux}"  # Can be: tmux, zellij, shell

# Main entry point
manage_sessions() {
    # Skip if disabled
    [ "${SESSION_STARTUP_ENABLED}" = "false" ] && return
    
    # Skip if not interactive
    [[ $- != *i* ]] && return
    
    # Skip if already in a session
    [ ! -z "$TMUX" ] && return
    [ ! -z "$ZELLIJ" ] && return
    
    case "$SESSION_MANAGER" in
        tmux)
            manage_tmux_sessions
            ;;
        zellij)
            manage_zellij_sessions
            ;;
        shell)
            manage_shell_sessions
            ;;
        *)
            echo "Unknown session manager: $SESSION_MANAGER"
            ;;
    esac
}

# Tmux session management
manage_tmux_sessions() {
    local sessions=$(tmux list-sessions 2>/dev/null)
    
    if command -v gum &> /dev/null; then
        show_tmux_menu_gum
    elif command -v fzf &> /dev/null; then
        show_tmux_menu_fzf
    else
        show_tmux_menu_basic
    fi
}

# Tmux menu with gum (your existing implementation)
show_tmux_menu_gum() {
    local options=()
    local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
    
    # Add existing sessions
    if [ ! -z "$sessions" ]; then
        while IFS= read -r session; do
            options+=("📎 Attach: $session")
        done <<< "$sessions"
    fi
    
    # Add other options
    options+=(
        "✨ New session"
        "🐚 Plain shell" 
        "📂 Project session"
        "💾 Restore saved"
        "❌ Exit"
    )
    
    local choice=$(printf '%s\n' "${options[@]}" | gum choose \
        --header "🚀 SESSION MANAGER" \
        --header.foreground="212" \
        --cursor.foreground="212" \
        --height=12)
    
    case "$choice" in
        "📎 Attach:"*)
            local session=$(echo "$choice" | cut -d' ' -f3)
            tmux attach -t "$session"
            ;;
        "✨ New session")
            local name=$(gum input --placeholder "Session name (optional)")
            [ -z "$name" ] && name="session-$$"
            tmux new-session -s "$name"
            ;;
        "🐚 Plain shell")
            exec bash --login
            ;;
        "📂 Project session")
            create_project_session
            ;;
        "💾 Restore saved")
            ~/.scripts/tmux-save-restore.sh restore
            ;;
        "❌ Exit")
            exit 0
            ;;
    esac
}

# Tmux menu with fzf
show_tmux_menu_fzf() {
    local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
    local options="New session\nPlain shell\nExit"
    
    if [ ! -z "$sessions" ]; then
        options="$sessions\n$options"
    fi
    
    local choice=$(echo -e "$options" | fzf \
        --header="SESSION MANAGER" \
        --height=50% \
        --reverse \
        --border)
    
    case "$choice" in
        "New session")
            read -p "Session name: " name
            tmux new-session -s "${name:-session-$$}"
            ;;
        "Plain shell")
            exec bash --login
            ;;
        "Exit")
            exit 0
            ;;
        *)
            # Attach to existing session
            [ ! -z "$choice" ] && tmux attach -t "$choice"
            ;;
    esac
}

# Create project-specific session
create_project_session() {
    local project_dirs=(
        "$HOME/projects"
        "$HOME/work"
        "$HOME/code"
        "$HOME"
    )
    
    # Find project directories
    local projects=()
    for dir in "${project_dirs[@]}"; do
        if [ -d "$dir" ]; then
            while IFS= read -r project; do
                projects+=("$project")
            done < <(find "$dir" -maxdepth 2 -type d -name ".git" 2>/dev/null | xargs -r dirname | sort -u)
        fi
    done
    
    if [ ${#projects[@]} -eq 0 ]; then
        echo "No projects found"
        return
    fi
    
    # Select project
    local project=$(printf '%s\n' "${projects[@]}" | gum choose --header "Select project")
    [ -z "$project" ] && return
    
    local session_name=$(basename "$project")
    
    # Create session with project layout
    tmux new-session -d -s "$session_name" -c "$project"
    tmux rename-window -t "$session_name:1" "editor"
    tmux send-keys -t "$session_name:1" "$EDITOR ." C-m
    
    tmux new-window -t "$session_name:2" -n "shell" -c "$project"
    tmux new-window -t "$session_name:3" -n "git" -c "$project"
    tmux send-keys -t "$session_name:3" "lazygit 2>/dev/null || git status" C-m
    
    tmux select-window -t "$session_name:1"
    tmux attach-session -t "$session_name"
}

# Zellij session management
manage_zellij_sessions() {
    if ! command -v zellij &> /dev/null; then
        echo "Zellij not installed. Install with: cargo install zellij"
        exec bash --login
        return
    fi
    
    # Zellij has built-in session management
    zellij --session "main" attach -c
}

# Export for use
manage_sessions