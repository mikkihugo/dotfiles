#!/bin/bash

# Tmux to Zellij Migration Script
# Preserves session names and working directories

set -e

echo "🔄 Migrating tmux sessions to zellij..."

# Get current tmux sessions with their directories
declare -A session_dirs
while IFS=: read -r session_name window_name directory; do
    session_dirs["$session_name"]="$directory"
done < <(tmux list-sessions -F "#{session_name}" 2>/dev/null | while read session; do
    dir=$(tmux list-windows -t "$session" -F "#{pane_current_path}" 2>/dev/null | head -1)
    echo "$session:$dir"
done)

echo "Found ${#session_dirs[@]} tmux sessions:"
for session in "${!session_dirs[@]}"; do
    echo "  • $session → ${session_dirs[$session]}"
done

echo ""
echo "Creating zellij sessions..."

# Create zellij sessions with same names and directories
for session_name in "${!session_dirs[@]}"; do
    directory="${session_dirs[$session_name]}"
    
    echo "🚀 Creating zellij session: $session_name"
    echo "   Directory: $directory"
    
    # Create detached zellij session in the correct directory
    cd "$directory"
    zellij -s "$session_name" -d
    
    echo "   ✅ Created"
done

echo ""
echo "🎉 Migration complete!"
echo ""
echo "Your sessions:"
zellij list-sessions

echo ""
echo "To attach to a session: zellij attach <session-name>"
echo "To kill old tmux sessions: tmux kill-server"
echo ""
echo "Zellij sessions are persistent and will survive reboots!"