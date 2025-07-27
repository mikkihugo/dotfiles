#!/bin/bash

# SSH Login Zellij Session Manager
# This script manages Zellij sessions on SSH login

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if zellij is installed
if ! command -v zellij &> /dev/null; then
    echo -e "${RED}Zellij is not installed. Please install it first.${NC}"
    return 0
fi

# Check if we're already in a zellij session
if [ -n "$ZELLIJ" ]; then
    return 0
fi

# Function to create a new session with dual-pane layout
create_dual_pane_session() {
    local session_name="$1"
    local left_cmd="$2"
    local right_cmd="$3"
    
    # Create session with custom layout
    zellij --session "$session_name" --layout <(cat <<EOF
layout {
    pane split_direction="vertical" {
        pane {
            command "$SHELL"
            args "-c" "$left_cmd"
        }
        pane {
            command "$SHELL"
            args "-c" "$right_cmd"
        }
    }
}
EOF
    )
}

# Function to detect if we're in a git repository
is_git_repo() {
    git rev-parse --git-dir &>/dev/null
}

# Function to get repository name
get_repo_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown"
}

# Get list of existing sessions
sessions=$(zellij list-sessions 2>/dev/null | grep -v "^$" || echo "")

if [ -n "$sessions" ]; then
    echo -e "${BLUE}=== Existing Zellij Sessions ===${NC}"
    echo "$sessions" | nl -w2 -s'. '
    echo ""
    echo -e "${GREEN}Options:${NC}"
    echo "  - Enter session number to attach"
    echo "  - Enter 'n' to create a new session"
    echo "  - Enter 'q' to continue without Zellij"
    echo ""
    
    read -r -p "Your choice: " choice
    
    case "$choice" in
        q|Q)
            return 0
            ;;
        n|N)
            # Continue to session creation
            ;;
        [0-9]*)
            # Get session name from number
            session_name=$(echo "$sessions" | sed -n "${choice}p" | awk '{print $1}')
            if [ -n "$session_name" ]; then
                echo -e "${GREEN}Attaching to session: $session_name${NC}"
                exec zellij attach "$session_name"
            else
                echo -e "${RED}Invalid session number${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            return 1
            ;;
    esac
fi

# Create new session
echo -e "${BLUE}=== Create New Zellij Session ===${NC}"
echo ""

# Default session name
default_name="ssh-$(date +%Y%m%d-%H%M%S)"
read -r -p "Session name (default: $default_name): " session_name
session_name="${session_name:-$default_name}"

# Check if we're in a git repository
if is_git_repo; then
    repo_name=$(get_repo_name)
    echo -e "${YELLOW}Detected git repository: $repo_name${NC}"
    echo ""
fi

echo -e "${GREEN}Layout Options:${NC}"
echo "1. Dual pane with claude-yolo -r (repository mode)"
echo "2. Dual pane with normal bash shells"
echo "3. Single pane with claude-yolo -r"
echo "4. Single pane with normal bash"
echo "5. Custom commands for each pane"
echo ""

read -r -p "Choose layout (1-5): " layout_choice

case "$layout_choice" in
    1)
        # Dual pane with claude-yolo
        if is_git_repo; then
            echo -e "${GREEN}Creating dual-pane session with claude-yolo in repository mode...${NC}"
            create_dual_pane_session "$session_name" "claude-yolo -r" "claude-yolo -r"
        else
            echo -e "${YELLOW}Not in a git repository. Creating with normal claude-yolo...${NC}"
            create_dual_pane_session "$session_name" "claude-yolo" "claude-yolo"
        fi
        ;;
    2)
        # Dual pane with bash
        echo -e "${GREEN}Creating dual-pane session with bash shells...${NC}"
        create_dual_pane_session "$session_name" "bash" "bash"
        ;;
    3)
        # Single pane with claude-yolo
        if is_git_repo; then
            echo -e "${GREEN}Creating single-pane session with claude-yolo in repository mode...${NC}"
            exec zellij --session "$session_name" options --default-shell bash -- claude-yolo -r
        else
            echo -e "${GREEN}Creating single-pane session with claude-yolo...${NC}"
            exec zellij --session "$session_name" options --default-shell bash -- claude-yolo
        fi
        ;;
    4)
        # Single pane with bash
        echo -e "${GREEN}Creating single-pane session...${NC}"
        exec zellij --session "$session_name"
        ;;
    5)
        # Custom commands
        echo ""
        read -r -p "Left pane command (default: bash): " left_cmd
        left_cmd="${left_cmd:-bash}"
        read -r -p "Right pane command (default: bash): " right_cmd
        right_cmd="${right_cmd:-bash}"
        echo -e "${GREEN}Creating dual-pane session with custom commands...${NC}"
        create_dual_pane_session "$session_name" "$left_cmd" "$right_cmd"
        ;;
    *)
        echo -e "${RED}Invalid choice. Creating default single-pane session...${NC}"
        exec zellij --session "$session_name"
        ;;
esac