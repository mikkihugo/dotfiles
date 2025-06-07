#!/bin/bash
# Auto-name tmux sessions based on current directory/project

get_project_name() {
    local dir="$PWD"
    
    # If in a git repo, use the repo name
    if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        basename "$(git rev-parse --show-toplevel)"
    # If in a project directory (has package.json, Cargo.toml, etc.)
    elif [ -f "package.json" ] || [ -f "Cargo.toml" ] || [ -f "pyproject.toml" ] || [ -f "go.mod" ]; then
        basename "$dir"
    # Otherwise use the current directory name
    else
        basename "$dir"
    fi
}

# Create new session with auto-generated name
create_auto_session() {
    local base_name=$(get_project_name)
    local session_name="$base_name"
    local counter=1
    
    # If session already exists, append a number
    while tmux has-session -t "$session_name" 2>/dev/null; do
        session_name="${base_name}-${counter}"
        ((counter++))
    done
    
    if command -v gum &>/dev/null; then
        # Let user confirm or edit the name
        session_name=$(gum input --value "$session_name" --placeholder "Session name" --header "Create TMUX Session")
    fi
    
    if [ ! -z "$session_name" ]; then
        tmux new-session -s "$session_name"
    fi
}

# Main
case "${1:-new}" in
    new)
        create_auto_session
        ;;
    name)
        get_project_name
        ;;
esac