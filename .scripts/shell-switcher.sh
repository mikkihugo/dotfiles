#!/bin/bash
# Shell switcher - select and launch different shells

# Available shells with descriptions
declare -A SHELLS=(
    ["bash"]="Bash - Bourne Again Shell (default)"
    ["zsh"]="Z Shell - Extended bash with more features"
    ["fish"]="Fish - Friendly Interactive Shell"
    ["nu"]="Nushell - Modern shell with structured data"
    ["dunesh"]="Dune Shell - A shell by the beach 🏖️"
    ["sh"]="POSIX Shell - Minimal shell"
)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check which shells are installed
available_shells=()
for shell in "${!SHELLS[@]}"; do
    if command -v "$shell" &> /dev/null; then
        available_shells+=("$shell:${SHELLS[$shell]}")
    fi
done

# If no argument, show menu
if [ $# -eq 0 ]; then
    echo -e "${BLUE}🐚 Available Shells:${NC}"
    echo ""
    
    # Use gum if available, otherwise fzf, otherwise basic select
    if command -v gum &> /dev/null; then
        selected=$(printf '%s\n' "${available_shells[@]}" | gum choose --header "Select a shell:")
    elif command -v fzf &> /dev/null; then
        selected=$(printf '%s\n' "${available_shells[@]}" | fzf --prompt="Select shell: " --height=40% --reverse)
    else
        PS3="Select shell: "
        select selected in "${available_shells[@]}" "Cancel"; do
            if [[ "$selected" == "Cancel" || -z "$selected" ]]; then
                exit 0
            fi
            break
        done
    fi
    
    # Extract shell name
    shell_name="${selected%%:*}"
else
    shell_name="$1"
fi

# Validate shell
if ! command -v "$shell_name" &> /dev/null; then
    echo -e "${YELLOW}⚠️  Shell '$shell_name' not found${NC}"
    echo "Available shells: ${!SHELLS[*]}"
    exit 1
fi

# Load appropriate config based on shell
echo -e "${GREEN}🚀 Launching $shell_name...${NC}"

case "$shell_name" in
    bash)
        exec bash --login
        ;;
    zsh)
        # Source zsh config if it exists
        if [ -f "$HOME/.dotfiles/config/zshrc" ]; then
            ZDOTDIR="$HOME/.dotfiles/config" exec zsh
        else
            exec zsh
        fi
        ;;
    fish)
        # Set fish config directory
        XDG_CONFIG_HOME="$HOME/.dotfiles/config" exec fish
        ;;
    nu)
        # Nushell uses config directory
        XDG_CONFIG_HOME="$HOME/.dotfiles/config" exec nu
        ;;
    dunesh)
        # Dune shell
        exec dunesh
        ;;
    *)
        exec "$shell_name"
        ;;
esac