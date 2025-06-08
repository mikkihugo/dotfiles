#!/bin/bash

# Tmux session management script
# Set TMUX_STARTUP_ENABLED=false in your environment to disable

# Function to display tmux session menu
manage_tmux_sessions() {
    # Check if tmux startup is disabled
    if [ "${TMUX_STARTUP_ENABLED}" = "false" ]; then
        return
    fi

    # Exit if not in an interactive shell
    [[ $- != *i* ]] && return

    # Don't run if inside a tmux session already
    [ ! -z "$TMUX" ] && return

    # Check if gum is available for fancy UI
    if command -v gum &> /dev/null; then
        manage_tmux_sessions_gum
    else
        manage_tmux_sessions_basic
    fi
}

# Fancy UI version using gum
manage_tmux_sessions_gum() {
    # Get existing sessions
    local sessions=$(tmux list-sessions -F "#{session_name}:#{?session_attached,[ATTACHED],[FREE]}:#{session_windows} windows" 2>/dev/null | sed 's/:/ /g')
    
    local header="TMUX SESSION MANAGER"
    local options=()
    
    if [ ! -z "$sessions" ]; then
        while IFS= read -r session; do
            options+=("Attach to: $session")
        done <<< "$sessions"
    fi
    
    options+=(
        "Create new session"
        "Start bash shell"
        "Restore saved sessions"
    )
    
    # Show menu with gum
    local choice=$(printf '%s\n' "${options[@]}" | gum choose \
        --header "$header" \
        --header.foreground="212" \
        --cursor.foreground="212" \
        --selected.foreground="212" \
        --height=10)
    
    case "$choice" in
        "Attach to: "*)
            local session_name=$(echo "$choice" | awk '{print $3}')
            tmux attach-session -t "$session_name"
            exit
            ;;
        "Create new session")
            local new_name=$(gum input --placeholder "Enter session name" --header "New TMUX Session")
            if [ ! -z "$new_name" ]; then
                tmux new-session -s "$new_name"
                exit
            fi
            ;;
        "Restore saved sessions")
            ~/.scripts/tmux-save-restore.sh restore
            ;;
        "Start bash shell")
            exec bash --login
            ;;
    esac
}

# Basic UI version (fallback)
manage_tmux_sessions_basic() {
    # Get a list of all tmux sessions, their IDs, and attachment status
    sessions=$(tmux list-sessions -F "#{session_id}:#{?session_attached,Attached,Not Attached}:#{session_name}" 2>/dev/null)

    if [ -z "$sessions" ]; then
        echo "No existing tmux sessions found."
    else
        echo "Existing tmux sessions:"
        printf "%-20s %s\n" "Session Name" "Status"
        echo "---------------------- ------------"
        # Loop through sessions and print them
        while IFS= read -r line; do
            session_name=$(echo "$line" | cut -d: -f3)
            session_status=$(echo "$line" | cut -d: -f2)
            printf "%-20s %s\n" "$session_name" "$session_status"
        done <<< "$sessions"
        echo ""
    fi

    # Display menu
    echo "Select an option:"
    echo "  1) Attach to an existing session"
    echo "  2) Create a new tmux session"
    echo "  3) Start a standard bash shell"
    echo "  4) Restore saved sessions"
    echo ""
    read -p "Enter your choice [1-4]: " choice

    case "$choice" in
        1)
            read -p "Enter the name of the session to attach to: " attach_name
            if tmux has-session -t "$attach_name" 2>/dev/null; then
                tmux attach-session -t "$attach_name"
                # Exit/logout after detaching from tmux
                exit
            else
                echo "Error: Session '$attach_name' not found."
                bash
            fi
            ;;
        2)
            read -p "Enter a name for the new session: " new_session_name
            # If no name is provided, tmux will assign a default numeric name
            if [ -z "$new_session_name" ]; then
                echo "Error: Session name cannot be empty."
                read -p "Enter a name for the new session: " new_session_name
            fi
            tmux new-session -s "$new_session_name"
            # Exit/logout after detaching from tmux
            exit
            ;;
        3)
            echo "Starting bash shell..."
            exec bash --login
            ;;
        4)
            ~/.scripts/tmux-save-restore.sh restore
            ;;
        *)
            echo "Invalid option. Starting bash shell."
            exec bash --login
            ;;
    esac
}

# Run the function on startup
manage_tmux_sessions