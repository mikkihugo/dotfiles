#!/bin/bash
# Auto tmux session manager

# Don't run if already inside tmux
if [[ -n "$TMUX" ]]; then
    return 0
fi

# Don't run if non-interactive (scp, rsync, etc.)
if [[ $- != *i* ]]; then
    return 0
fi

# Count existing sessions
session_count=$(tmux list-sessions 2>/dev/null | wc -l)

if [[ $session_count -eq 0 ]]; then
    # No sessions - create new one
    echo "🚀 Creating new tmux session..."
    tmux new-session -d -s "main"
    tmux attach-session -t "main"
elif [[ $session_count -eq 1 ]]; then
    # One session - attach to it
    session_name=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
    echo "📎 Attaching to existing session: $session_name"
    tmux attach-session -t "$session_name"
else
    # Multiple sessions - show menu
    echo "🔗 Multiple tmux sessions found:"
    tmux list-sessions
    echo ""
    echo "Commands:"
    echo "  tmux attach -t SESSION_NAME  # Attach to specific session"
    echo "  tmux new -s SESSION_NAME     # Create new session"
    echo "  tmux list-sessions           # List all sessions"
    echo ""
    read -p "Enter session name to attach (or press Enter to skip): " choice
    if [[ -n "$choice" ]]; then
        tmux attach-session -t "$choice" 2>/dev/null || echo "❌ Session '$choice' not found"
    fi
fi