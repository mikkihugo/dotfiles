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
    echo ""
    read -p "Enter your choice [1-3]: " choice

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
            bash
            ;;
        *)
            echo "Invalid option. Starting bash shell."
            bash
            ;;
    esac
}

# Run the function on startup
manage_tmux_sessions