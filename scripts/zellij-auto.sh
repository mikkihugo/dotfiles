#!/bin/bash
# Auto zellij session manager

# Don't run if already inside zellij
if [[ -n "$ZELLIJ" ]]; then
    return 0
fi

# Don't run if non-interactive (scp, rsync, etc.)
if [[ $- != *i* ]]; then
    return 0
fi

# Count existing sessions
session_count=$(zellij list-sessions 2>/dev/null | grep -v "EXITED" | wc -l)

if [[ $session_count -eq 0 ]]; then
    # No sessions - create new one
    echo "🚀 Creating new zellij session..."
    zellij -s main
else
    # Always create a new session with timestamp
    new_session="ssh-$(date +%Y%m%d-%H%M%S)"
    echo "🚀 Creating new zellij session: $new_session"
    zellij -s "$new_session"
fi