#!/bin/bash
# Tmux session save/restore functionality using mise-managed tools

TMUX_SESSIONS_DIR="$HOME/.tmux-sessions"
mkdir -p "$TMUX_SESSIONS_DIR"

# Save current tmux state
save_sessions() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local save_file="$TMUX_SESSIONS_DIR/tmux-state-$timestamp.txt"
    
    echo "Saving tmux sessions to $save_file..."
    
    # Save each session's state
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r session; do
        echo "SESSION:$session" >> "$save_file"
        
        # Save windows for this session
        tmux list-windows -t "$session" -F '#{window_index}:#{window_name}:#{pane_current_path}' | while read -r window; do
            echo "  WINDOW:$window" >> "$save_file"
            
            # Save panes for this window
            local window_index=$(echo "$window" | cut -d: -f1)
            tmux list-panes -t "$session:$window_index" -F '#{pane_index}:#{pane_current_command}:#{pane_current_path}' | while read -r pane; do
                echo "    PANE:$pane" >> "$save_file"
            done
        done
    done
    
    # Keep only last 10 saves
    ls -t "$TMUX_SESSIONS_DIR"/tmux-state-*.txt 2>/dev/null | tail -n +11 | xargs -r rm
    
    echo "Sessions saved!"
}

# Restore tmux state from file
restore_sessions() {
    local restore_file
    
    # Use gum to select a save file
    if command -v gum &> /dev/null; then
        restore_file=$(ls -t "$TMUX_SESSIONS_DIR"/tmux-state-*.txt 2>/dev/null | \
                      gum choose --header "Select a session state to restore:")
    else
        # Fallback to most recent
        restore_file=$(ls -t "$TMUX_SESSIONS_DIR"/tmux-state-*.txt 2>/dev/null | head -1)
    fi
    
    if [ -z "$restore_file" ]; then
        echo "No saved sessions found."
        return 1
    fi
    
    echo "Restoring sessions from $restore_file..."
    
    local current_session=""
    local current_window=""
    
    while IFS= read -r line; do
        if [[ $line =~ ^SESSION:(.+)$ ]]; then
            current_session="${BASH_REMATCH[1]}"
            # Create session if it doesn't exist
            if ! tmux has-session -t "$current_session" 2>/dev/null; then
                tmux new-session -d -s "$current_session"
            fi
        elif [[ $line =~ ^[[:space:]]+WINDOW:([0-9]+):([^:]+):(.*)$ ]]; then
            local window_index="${BASH_REMATCH[1]}"
            local window_name="${BASH_REMATCH[2]}"
            local window_path="${BASH_REMATCH[3]}"
            current_window="$window_index"
            
            # Create window if needed
            if ! tmux list-windows -t "$current_session" -F '#{window_index}' | grep -q "^$window_index$"; then
                tmux new-window -t "$current_session:$window_index" -n "$window_name" -c "$window_path"
            fi
        fi
    done < "$restore_file"
    
    echo "Sessions restored!"
}

# Main menu
case "${1:-menu}" in
    save)
        save_sessions
        ;;
    restore)
        restore_sessions
        ;;
    menu)
        if command -v gum &> /dev/null; then
            choice=$(gum choose "Save current sessions" "Restore sessions" "Cancel")
            case "$choice" in
                "Save current sessions")
                    save_sessions
                    ;;
                "Restore sessions")
                    restore_sessions
                    ;;
            esac
        else
            echo "1) Save current sessions"
            echo "2) Restore sessions"
            echo "3) Cancel"
            read -p "Choice: " choice
            case "$choice" in
                1) save_sessions ;;
                2) restore_sessions ;;
            esac
        fi
        ;;
esac