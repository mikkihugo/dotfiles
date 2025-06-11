#!/bin/bash
#
# Copyright 2024 Mikki Hugo. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# FZF-based launcher menu system
# Purpose: Provide fuzzy searchable launcher for commands and tools
# Version: 1.0.0
# Dependencies: fzf

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available commands with descriptions
get_commands() {
    cat << 'EOF'
safe-exec → Run commands with resource protection
shell-switcher → Switch between bash/zsh/fish/nu
zj → Quick zellij session creator
zellij list-sessions → Show existing zellij sessions
zellij attach → Attach to session (with tab completion)
mise install → Install missing development tools
mise upgrade → Upgrade all tools to latest
claude → Launch Claude Code assistant
EOF
}

# System commands
get_system_commands() {
    cat << 'EOF'
systemctl --user status → Show user service status
journalctl --user -f → Follow user service logs
top → System monitor
btop → Better system monitor (if available)
df -h → Disk usage
free -h → Memory usage
EOF
}

main() {
    local choice
    
    case "${1:-}" in
        --system)
            choice=$(get_system_commands | fzf --prompt="System Command: " --height=40% --reverse)
            ;;
        --all)
            choice=$({ get_commands; echo "---"; get_system_commands; } | fzf --prompt="Command: " --height=40% --reverse)
            ;;
        *)
            choice=$(get_commands | fzf --prompt="Tool: " --height=40% --reverse)
            ;;
    esac
    
    if [ -n "$choice" ] && [ "$choice" != "---" ]; then
        # Extract command from "command → description" format
        cmd=$(echo "$choice" | cut -d'→' -f1 | xargs)
        echo -e "${GREEN}Running:${NC} $cmd"
        eval "$cmd"
    fi
}

main "$@"