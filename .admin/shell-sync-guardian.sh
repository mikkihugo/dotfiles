#!/bin/bash
# Shell Sync Guardian - Keeps bash, zsh, and fish configs in sync
# This is the ADMIN version - maintains consistency across all shells

set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles"
ADMIN_DIR="$DOTFILES_DIR/.admin"
LOG_FILE="$ADMIN_DIR/sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Ensure admin directory exists
mkdir -p "$ADMIN_DIR"

# Core PATH components that ALL shells need
CORE_PATHS=(
    "/usr/local/sbin"
    "/usr/local/bin"
    "/usr/sbin"
    "/usr/bin"
    "/sbin"
    "/bin"
    "\$HOME/.local/bin"
    "\$HOME/bin"
    "\$HOME/.npm-global/bin"
    "\$HOME/.scripts"
    "\$HOME/.dotfiles/tools"
    "\$HOME/.cargo/bin"
    "\$HOME/.local/share/mise/shims"
)

# Tools that need initialization
INIT_TOOLS=(
    "mise:activate"
    "starship:init"
    "zoxide:init"
    "direnv:hook"
)

# Generate PATH export for any shell
generate_path_export() {
    local shell=$1
    echo "# Essential PATH"
    echo "export PATH=\"${CORE_PATHS[0]}\""
    for path in "${CORE_PATHS[@]:1}"; do
        echo "export PATH=\"\$PATH:$path\""
    done
}

# Generate tool initialization for specific shell
generate_tool_init() {
    local shell=$1
    
    echo -e "\n# Tool initialization"
    
    # Mise needs special handling
    echo "if [ -f \"\$HOME/.local/bin/mise\" ]; then"
    echo "  eval \"\$(mise activate $shell)\""
    echo "  export PATH=\"\$HOME/.local/share/mise/shims:\$PATH\""
    echo "fi"
    
    echo -e "\n# Add all mise tool paths"
    cat << 'EOF'
for tool_path in $HOME/.local/share/mise/installs/*/*; do
  if [ -d "$tool_path" ] && [ -x "$tool_path" ]; then
    case "$tool_path" in
      */bin) export PATH="$tool_path:$PATH" ;;
      *) export PATH="$tool_path:$PATH" ;;
    esac
  fi
done
EOF
    
    # Other tools
    for tool_spec in "${INIT_TOOLS[@]:1}"; do
        IFS=':' read -r tool cmd <<< "$tool_spec"
        echo -e "\nif command -v $tool &>/dev/null; then"
        echo "  eval \"\$($tool $cmd $shell)\""
        echo "fi"
    done
}

# Sync bashrc
sync_bash() {
    log "Syncing bash configuration..."
    
    # Create a consistent bashrc section
    local bash_config="$ADMIN_DIR/bash-core.sh"
    cat > "$bash_config" << 'EOF'
# Core shell configuration - managed by shell-sync-guardian
# DO NOT EDIT THIS SECTION MANUALLY

# Exit early if not running interactively
[[ $- != *i* ]] && return

EOF
    
    generate_path_export bash >> "$bash_config"
    generate_tool_init bash >> "$bash_config"
    
    cat >> "$bash_config" << 'EOF'

# Load tokens
if [ -f "$HOME/.env_tokens" ]; then
    set -a
    source "$HOME/.env_tokens" 2>/dev/null || true
    set +a
fi

# Load aliases AFTER tools are initialized
if [ -f "$HOME/.dotfiles/.aliases" ]; then
    source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Claude CLI
if [ -f "$HOME/.claude/local/claude" ]; then
    alias claude="$HOME/.claude/local/claude"
fi

# Shell upgrade for SSH (fish > zsh > bash)
if [ -n "$SSH_CONNECTION" ] && [ -z "$SHELL_UPGRADED" ]; then
    export SHELL_UPGRADED=1
    if command -v fish >/dev/null 2>&1; then
        echo "🐟 Upgrading to fish..."
        exec fish
    elif command -v zsh >/dev/null 2>&1; then
        echo "🚀 Upgrading to zsh..."
        exec zsh
    fi
fi
EOF
    
    log "Bash config generated"
}

# Sync zshrc
sync_zsh() {
    log "Syncing zsh configuration..."
    
    local zsh_config="$ADMIN_DIR/zsh-core.sh"
    cat > "$zsh_config" << 'EOF'
#!/usr/bin/env zsh
# Core shell configuration - managed by shell-sync-guardian
# DO NOT EDIT THIS SECTION MANUALLY

# Skip system-wide configs
setopt no_global_rcs

EOF
    
    generate_path_export zsh >> "$zsh_config"
    generate_tool_init zsh >> "$zsh_config"
    
    cat >> "$zsh_config" << 'EOF'

# Zsh-specific settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt append_history share_history hist_ignore_dups

# Load tokens
if [ -f "$HOME/.env_tokens" ]; then
  set -a
  source "$HOME/.env_tokens" 2>/dev/null || true
  set +a
fi

# Load aliases AFTER tools are initialized
if [ -f "$HOME/.dotfiles/.aliases" ]; then
  source "$HOME/.dotfiles/.aliases" 2>/dev/null || true
fi

# Claude aliases
if [ -f "$HOME/.npm-global/bin/claude-yolo" ]; then
  alias claude-yolo="$HOME/.npm-global/bin/claude-yolo"
fi

if [ -f "$HOME/.claude/local/claude" ]; then
  alias claude="$HOME/.claude/local/claude"
fi

# FZF
if command -v fzf &>/dev/null; then
  eval "$(fzf --zsh)" 2>/dev/null || true
fi
EOF
    
    log "Zsh config generated"
}

# Sync fish config
sync_fish() {
    log "Syncing fish configuration..."
    
    local fish_config="$ADMIN_DIR/fish-core.fish"
    cat > "$fish_config" << 'EOF'
# Core shell configuration - managed by shell-sync-guardian
# DO NOT EDIT THIS SECTION MANUALLY

# Essential PATH
set -gx PATH /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin $HOME/.local/bin $HOME/bin
set -gx PATH $HOME/.npm-global/bin $PATH
set -gx PATH $HOME/.scripts $PATH
set -gx PATH $HOME/.dotfiles/tools $PATH
set -gx PATH $HOME/.cargo/bin $PATH

# Mise activation
if test -f "$HOME/.local/bin/mise"
    mise activate fish | source
    set -gx PATH $HOME/.local/share/mise/shims $PATH
end

# Add all mise tool paths
for tool_path in $HOME/.local/share/mise/installs/*/*
    if test -d "$tool_path" -a -x "$tool_path"
        set -gx PATH $tool_path $PATH
    end
end

# Tool initialization
if command -v starship &>/dev/null
    starship init fish | source
end

if command -v zoxide &>/dev/null
    zoxide init fish | source
end

if command -v direnv &>/dev/null
    direnv hook fish | source
end

# Load tokens
if test -f "$HOME/.env_tokens"
    export (cat $HOME/.env_tokens | grep -v '^#' | xargs -L 1)
end

# Load fish-specific aliases
if test -f "$HOME/.dotfiles/.config/fish/aliases.fish"
    source "$HOME/.dotfiles/.config/fish/aliases.fish"
end

# Claude CLI
if test -f "$HOME/.claude/local/claude"
    alias claude="$HOME/.claude/local/claude"
end
EOF
    
    log "Fish config generated"
}

# Verify and update actual config files
update_configs() {
    log "Updating actual configuration files..."
    
    # Update bashrc
    if [ -f "$DOTFILES_DIR/.bashrc" ]; then
        cp "$DOTFILES_DIR/.bashrc" "$DOTFILES_DIR/.bashrc.backup"
        cp "$ADMIN_DIR/bash-core.sh" "$DOTFILES_DIR/.bashrc"
        log "Updated .bashrc"
    fi
    
    # Update zshrc
    if [ -f "$DOTFILES_DIR/.config/zsh/.zshrc" ]; then
        cp "$DOTFILES_DIR/.config/zsh/.zshrc" "$DOTFILES_DIR/.config/zsh/.zshrc.backup"
        cp "$ADMIN_DIR/zsh-core.sh" "$DOTFILES_DIR/.config/zsh/.zshrc"
        log "Updated .zshrc"
    fi
    
    # Update fish config
    mkdir -p "$DOTFILES_DIR/.config/fish"
    if [ -f "$DOTFILES_DIR/.config/fish/config.fish" ]; then
        cp "$DOTFILES_DIR/.config/fish/config.fish" "$DOTFILES_DIR/.config/fish/config.fish.backup"
    fi
    cp "$ADMIN_DIR/fish-core.fish" "$DOTFILES_DIR/.config/fish/config.fish"
    log "Updated config.fish"
}

# Main sync operation
main() {
    log "Starting shell sync guardian..."
    
    sync_bash
    sync_zsh
    sync_fish
    
    # Ask before updating
    echo -e "\n${GREEN}Ready to update shell configurations.${NC}"
    echo "This will:"
    echo "  - Ensure consistent PATH across all shells"
    echo "  - Initialize all Rust tools properly"
    echo "  - Keep aliases and functions in sync"
    echo ""
    read -p "Update configurations now? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_configs
        log "Shell configurations synchronized successfully!"
        echo -e "\n${GREEN}✓ All shells synchronized!${NC}"
        echo "Please reload your shell or start a new terminal."
    else
        log "Update cancelled by user"
        echo "Generated configs saved in $ADMIN_DIR/"
        echo "Run this script again when ready to apply."
    fi
}

# Run with --auto to skip confirmation
if [[ "${1:-}" == "--auto" ]]; then
    sync_bash
    sync_zsh
    sync_fish
    update_configs
    log "Automatic sync completed"
else
    main
fi