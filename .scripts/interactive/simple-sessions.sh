#!/bin/bash

# Simple session management - no complex menus, just quick commands

# Function to create or attach to session
s() {
    local session_name="${1:-$(basename $(pwd))}"
    
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "📎 Attaching to existing session: $session_name"
        tmux attach-session -t "$session_name"
    else
        echo "🚀 Creating new session: $session_name"
        tmux new-session -s "$session_name"
    fi
}

# Function to list sessions
sl() {
    echo "📋 Active sessions:"
    tmux list-sessions 2>/dev/null || echo "No sessions running"
}

# Function to kill session
sk() {
    local session_name="$1"
    if [ -z "$session_name" ]; then
        echo "Usage: sk <session-name>"
        return 1
    fi
    tmux kill-session -t "$session_name" 2>/dev/null && echo "🗑️  Killed session: $session_name"
}

# Quick session shortcuts
alias sa='s agent && cd ~/singularity-engine'
alias sm='s mcp && cd ~/architecturemcp'  
alias sw='s work && cd ~/.dotfiles'
alias st='s temp'

# Only show this message on SSH login, not local bash
if [ -z "$SIMPLE_SESSIONS_LOADED" ] && [ -n "$SSH_CONNECTION" ]; then
    export SIMPLE_SESSIONS_LOADED=1
    echo "🎛️  Simple session commands loaded:"
    echo "  s [name]  - Create/attach session (defaults to current dir name)"
    echo "  sl        - List sessions"
    echo "  sk <name> - Kill session"
    echo "  sa/sm/sw/st - Quick shortcuts for main sessions"
fi