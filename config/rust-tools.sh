#!/bin/bash
# Force rust-based tools system-wide

# Export tool paths for scripts that use full paths
export GREP_COMMAND="rg"
export FIND_COMMAND="fd"
export LS_COMMAND="eza"
export CAT_COMMAND="bat"

# Set environment variables that some tools respect
export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"

# Configure ripgrep defaults
export RIPGREP_CONFIG_PATH="$HOME/.dotfiles/config/ripgreprc"

# Configure bat defaults
export BAT_THEME="OneHalfDark"
export BAT_STYLE="numbers,changes,header"

# Configure eza defaults
export EZA_COLORS="uu=36:gu=37:sn=32:sb=32:da=34:ur=34:uw=35:ux=36:ue=36:gr=34:gw=35:gx=36:tr=34:tw=35:tx=36"

# Function to check if rust tools are available
check_rust_tools() {
    local tools=(rg fd eza bat procs dust duf sd btop delta hx)
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing rust tools: ${missing[*]}"
        echo "Install with: mise install ${missing[*]}"
    fi
}

# Override common tool detection functions
which() {
    case "$1" in
        grep) echo "rg" ;;
        find) echo "fd" ;;
        ls) echo "eza" ;;
        cat) echo "bat" ;;
        *) command which "$@" ;;
    esac
}

# Export the override
export -f which