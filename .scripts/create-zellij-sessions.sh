#!/bin/bash

# Create clean zellij sessions from tmux sessions
# This version handles session names properly

echo "🔄 Creating clean zellij sessions..."

# Define sessions and their directories
declare -A sessions=(
    ["agent"]="/home/mhugo/singularity-engine"
    ["mcp"]="/home/mhugo/architecturemcp" 
    ["temp"]="/home/mhugo"
    ["work"]="/home/mhugo/.dotfiles"
)

echo "Creating ${#sessions[@]} zellij sessions:"

for session_name in "${!sessions[@]}"; do
    directory="${sessions[$session_name]}"
    
    echo "🚀 Creating session: $session_name"
    echo "   Directory: $directory"
    
    # Create session using a subshell to avoid terminal issues
    (
        cd "$directory" 2>/dev/null || cd "$HOME"
        # Create session in background, let it start properly
        nohup zellij -s "$session_name" >/dev/null 2>&1 &
        sleep 0.5
        # Detach from it immediately 
        zellij action quit 2>/dev/null || true
    ) &
    
    echo "   ✅ Queued"
done

# Wait for all sessions to start
sleep 2

echo ""
echo "🎉 Sessions created!"
echo ""
echo "Your clean sessions:"
zellij list-sessions | grep -E "(agent|mcp|temp|work)" | grep -v "EXITED" || echo "Sessions starting..."

echo ""
echo "Usage:"
echo "  zellij attach agent"
echo "  zellij attach mcp" 
echo "  zellij attach temp"
echo "  zellij attach work"