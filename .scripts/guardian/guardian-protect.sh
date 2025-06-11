#!/bin/bash
# guardian-protect.sh - Apply or remove filesystem-level protection
# This makes guardian files immutable at the filesystem level
# for the strongest possible protection against accidental modification

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Protected directory
GUARDIAN_DIR="${HOME}/.dotfiles/.guardian-shell"

# Check if chattr is available
if ! command -v chattr &>/dev/null || ! command -v lsattr &>/dev/null; then
    echo -e "${RED}❌ chattr/lsattr not available on this system${NC}"
    echo -e "${YELLOW}💡 Cannot apply filesystem-level protection${NC}"
    exit 1
fi

# Function to show current attributes
show_attributes() {
    echo -e "${BLUE}🔒 Current file attributes:${NC}"
    lsattr "${GUARDIAN_DIR}"/*
}

# Function to apply protection
protect() {
    echo -e "${BLUE}🔒 Applying filesystem-level protection...${NC}"
    
    # Ensure we have the files to protect
    if [ ! -d "${GUARDIAN_DIR}" ] || [ -z "$(ls -A "${GUARDIAN_DIR}" 2>/dev/null)" ]; then
        echo -e "${RED}❌ Protected directory not found or empty${NC}"
        exit 1
    fi
    
    # Make files immutable
    for file in "${GUARDIAN_DIR}"/*; do
        echo -e "${YELLOW}🔒 Protecting: $(basename "$file")${NC}"
        sudo chattr +i "$file" 2>/dev/null || {
            # Try without sudo if sudo fails
            chattr +i "$file" 2>/dev/null || {
                echo -e "${RED}❌ Failed to protect: $(basename "$file")${NC}"
                continue
            }
        }
    done
    
    # Create a marker file to indicate protection is active
    touch "${GUARDIAN_DIR}/.protected"
    
    echo -e "${GREEN}✅ Protection applied successfully${NC}"
    show_attributes
}

# Function to remove protection
unprotect() {
    echo -e "${BLUE}🔓 Removing filesystem-level protection...${NC}"
    
    # Make files mutable again
    for file in "${GUARDIAN_DIR}"/*; do
        echo -e "${YELLOW}🔓 Unprotecting: $(basename "$file")${NC}"
        sudo chattr -i "$file" 2>/dev/null || {
            # Try without sudo if sudo fails
            chattr -i "$file" 2>/dev/null || {
                echo -e "${RED}❌ Failed to unprotect: $(basename "$file")${NC}"
                continue
            }
        }
    done
    
    # Remove marker file
    rm -f "${GUARDIAN_DIR}/.protected"
    
    echo -e "${GREEN}✅ Protection removed successfully${NC}"
    show_attributes
}

# Function to create recovery script
create_recovery() {
    echo -e "${BLUE}📝 Creating recovery script...${NC}"
    
    # Create a recovery script in /tmp
    cat > "/tmp/guardian-recovery.sh" << 'EOF'
#!/bin/bash
# Emergency guardian recovery script
# This script can restore guardian files even if the dotfiles repo is damaged

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create minimal bash guardian
create_minimal_guardian() {
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/shell-guardian" << 'EOFGUARDIAN'
#!/bin/bash
# Minimal emergency guardian

# Log file for crash detection
LOG_FILE="$HOME/.shell-guardian.log"

# Check args
if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [args...]"
    exit 1
fi

# Launch minimal bash
if [ -n "$SHELL_GUARDIAN_RECOVERY" ]; then
    echo -e "\033[31m⚠️ Already in recovery mode!\033[0m"
    exit 1
fi

# Run the requested shell in recovery mode
command="$1"
shift
SHELL_GUARDIAN_ACTIVE=1 \
SHELL_GUARDIAN_RECOVERY=1 \
PS1="\[\033[31m\][RECOVERY]\[\033[0m\] \w \$ " \
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin" \
TERM="xterm-256color" \
"$command" "$@"
EOFGUARDIAN

    chmod +x "$HOME/.local/bin/shell-guardian"
    echo -e "${GREEN}✅ Created minimal emergency guardian${NC}"
}

# Fix bash profile
fix_bash_profile() {
    if [ -f "$HOME/.bash_profile" ]; then
        # Check if it's already fixed
        if grep -q "shell-guardian" "$HOME/.bash_profile"; then
            echo -e "${YELLOW}⚠️ .bash_profile already contains guardian hook${NC}"
            return
        fi
        
        # Backup existing profile
        cp "$HOME/.bash_profile" "$HOME/.bash_profile.bak"
    fi
    
    # Create fixed profile
    cat > "$HOME/.bash_profile" << 'EOFPROFILE'
# Emergency recovery bash_profile

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
EOFPROFILE

    echo -e "${GREEN}✅ Fixed .bash_profile${NC}"
}

# Main recovery function
recover() {
    echo -e "${BLUE}🔄 Running emergency guardian recovery...${NC}"
    
    # Create the minimal guardian
    create_minimal_guardian
    
    # Fix bash profile
    fix_bash_profile
    
    echo -e "${GREEN}✅ Recovery complete!${NC}"
    echo -e "${YELLOW}💡 Log out and back in to use the recovered environment${NC}"
    echo -e "${YELLOW}💡 Or run: shell-guardian bash${NC}"
}

# Run recovery
recover
EOF

    chmod +x "/tmp/guardian-recovery.sh"
    
    # Copy it to a few key locations for redundancy
    cp "/tmp/guardian-recovery.sh" "${HOME}/guardian-recovery.sh"
    cp "/tmp/guardian-recovery.sh" "${HOME}/.local/bin/guardian-recovery"
    chmod +x "${HOME}/guardian-recovery.sh" "${HOME}/.local/bin/guardian-recovery"
    
    echo -e "${GREEN}✅ Recovery script created at:${NC}"
    echo -e "  ${YELLOW}${HOME}/guardian-recovery.sh${NC}"
    echo -e "  ${YELLOW}${HOME}/.local/bin/guardian-recovery${NC}"
    echo -e "${BLUE}💡 Run this script if you ever need to recover the guardian${NC}"
}

# Parse command line arguments
case "$1" in
    "protect")
        protect
        create_recovery
        ;;
    "unprotect")
        unprotect
        ;;
    "status")
        show_attributes
        ;;
    "recovery")
        create_recovery
        ;;
    *)
        echo -e "${BLUE}Guardian Protection System${NC}"
        echo -e "${YELLOW}Usage:${NC}"
        echo "  $0 protect   - Apply filesystem-level protection"
        echo "  $0 unprotect - Remove protection (for updates)"
        echo "  $0 status    - Show current protection status"
        echo "  $0 recovery  - Create emergency recovery script"
        ;;
esac