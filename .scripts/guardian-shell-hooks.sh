#!/bin/bash
# Universal shell hooks for shell-guardian
# This creates hook files for all supported shells

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Creating universal shell hooks for guardian...${NC}"

# Check if shell-guardian exists or can be built
if [ ! -f "$HOME/.local/bin/shell-guardian" ]; then
    if [ -f "$HOME/.dotfiles/.scripts/shell-guardian.rs" ] && command -v rustc &>/dev/null; then
        echo -e "${YELLOW}⚠️ Building shell-guardian from source...${NC}"
        mkdir -p "$HOME/.local/bin"
        rustc -O "$HOME/.dotfiles/.scripts/shell-guardian.rs" -o "$HOME/.local/bin/shell-guardian"
        chmod +x "$HOME/.local/bin/shell-guardian"
    else
        echo -e "${RED}❌ shell-guardian not found and cannot be built${NC}"
        exit 1
    fi
fi

# 1. Create bash hook
echo -e "${YELLOW}📝 Creating bash hook...${NC}"
cat > "$HOME/.bash_profile" << 'EOF'
# .bash_profile with Shell Guardian integration

# If Shell Guardian is available and not already active, use it
if command -v shell-guardian &> /dev/null && [ -z "$SHELL_GUARDIAN_ACTIVE" ]; then
    # Start shell with guardian
    exec shell-guardian bash
else
    # Source bashrc directly if guardian is not available or already active
    if [ -f ~/.bashrc ]; then
        . ~/.bashrc
    fi
fi

# User specific environment and startup programs
EOF

echo -e "${GREEN}✅ Bash hook created${NC}"

# 2. Create zsh hook if zsh is installed
if command -v zsh &>/dev/null; then
    echo -e "${YELLOW}📝 Creating zsh hook...${NC}"
    # Make sure directory exists
    mkdir -p "$HOME/.zsh"
    
    # Create .zshenv with guardian hook
    cat > "$HOME/.zshenv" << 'EOF'
# Shell Guardian integration for zsh

# If Shell Guardian is available and not already active, use it
if command -v shell-guardian &> /dev/null && [ -z "$SHELL_GUARDIAN_ACTIVE" ]; then
    if [[ -o interactive ]]; then
        # Only redirect interactive shells
        exec shell-guardian zsh
    fi
fi

# Continue with normal zsh startup
EOF

    # Create minimal .zshrc if it doesn't exist
    if [ ! -f "$HOME/.zshrc" ]; then
        ln -sf "$HOME/.dotfiles/config/zshrc" "$HOME/.zshrc" 2>/dev/null || cat > "$HOME/.zshrc" << 'EOF'
# Minimal zshrc for recovery
if [ -n "$SHELL_GUARDIAN_ACTIVE" ]; then
    # Minimal prompt for failsafe mode
    PS1="%F{red}[FAILSAFE]%f %~ %# "
    # Basic path
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin"
else
    # Source dotfiles zshrc if it exists
    if [ -f "$HOME/.dotfiles/config/zshrc" ]; then
        source "$HOME/.dotfiles/config/zshrc"
    fi
fi
EOF
    fi
    
    echo -e "${GREEN}✅ Zsh hook created${NC}"
fi

# 3. Create fish hook if fish is installed
if command -v fish &>/dev/null; then
    echo -e "${YELLOW}📝 Creating fish hook...${NC}"
    # Make sure directory exists
    mkdir -p "$HOME/.config/fish"
    
    # Create fish config.fish with guardian hook
    cat > "$HOME/.config/fish/config.fish" << 'EOF'
# Shell Guardian integration for fish

# Function to check if a command exists
function command_exists
    type -q $argv[1]
end

# Only apply guardian in interactive mode
if status is-interactive
    # Check if Shell Guardian is available and not already active
    if command_exists shell-guardian; and not set -q SHELL_GUARDIAN_ACTIVE
        # Fish can't exec so we need a different approach
        if test -z "$FISH_GUARDIAN_CHECKED"
            # Mark as checked to prevent loops
            set -gx FISH_GUARDIAN_CHECKED 1
            # Start fish with guardian
            shell-guardian fish
            # Exit this instance
            exit
        end
    end
end

# Continue with normal fish startup
if set -q SHELL_GUARDIAN_ACTIVE
    # Minimal prompt for failsafe mode
    function fish_prompt
        echo -n (set_color red)"[FAILSAFE]"(set_color normal)" "(pwd)" > "
    end
    # Basic path
    set -gx PATH /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin $HOME/.local/bin
else
    # Source dotfiles fish config if it exists
    if test -f "$HOME/.dotfiles/config/fish/config.fish"
        source "$HOME/.dotfiles/config/fish/config.fish"
    end
end
EOF
    
    echo -e "${GREEN}✅ Fish hook created${NC}"
fi

# 4. Create a universal shell wrapper for all shells
echo -e "${YELLOW}📝 Creating universal shell wrapper...${NC}"

cat > "$HOME/.local/bin/shell-safe" << 'EOF'
#!/bin/bash
# Universal shell wrapper that uses guardian with any shell

# Get the requested shell
SHELL_NAME="${1:-bash}"
shift 1

# Check if shell-guardian exists
if command -v shell-guardian &>/dev/null; then
    # Start shell with guardian
    exec shell-guardian "$SHELL_NAME" "$@"
else
    # Fall back to regular shell
    echo -e "\033[33m⚠️ Shell Guardian not found, using regular $SHELL_NAME\033[0m"
    exec "$SHELL_NAME" "$@"
fi
EOF

chmod +x "$HOME/.local/bin/shell-safe"

echo -e "${GREEN}✅ Universal shell wrapper created${NC}"
echo -e "${BLUE}🚀 To use a protected shell, run: shell-safe <shell-name>${NC}"
echo -e "${BLUE}   Example: shell-safe bash${NC}"
echo -e "${BLUE}   Example: shell-safe zsh${NC}"
echo -e "${BLUE}   Example: shell-safe fish${NC}"