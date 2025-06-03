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
else
    # Always create a new session with timestamp
    new_session="ssh-$(date +%Y%m%d-%H%M%S)"
    echo "🚀 Creating new tmux session: $new_session"
    tmux new-session -s "$new_session"
fi