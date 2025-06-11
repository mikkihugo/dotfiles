#!/bin/bash
# Failsafe Integrity Verification System
# Ensures the failsafe system remains intact and functional

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔒 Verifying failsafe integrity...${NC}"

# Critical paths to verify
GUARDIAN_BIN="${HOME}/.local/bin/shell-guardian"
GUARDIAN_FALLBACK="${HOME}/.local/bin/shell-guardian-fallback"
PROTECTED_DIR="${HOME}/.dotfiles/.guardian-shell"
GUARDIAN_RS="${PROTECTED_DIR}/shell-guardian.rs"
GUARDIAN_SH="${PROTECTED_DIR}/bash-guardian-fallback.sh"
GUARDIAN_BIN_BACKUP="${PROTECTED_DIR}/shell-guardian.bin"
FAILSAFE_MODULE="${HOME}/.dotfiles/config/bash.d/01-failsafe.sh"
INSTALLER="${HOME}/.dotfiles/.scripts/guardian/install-shell-guardian.sh"
INTEGRITY_CHECKER="${HOME}/.dotfiles/.scripts/guardian/verify-failsafe-integrity.sh"
HOOKS_SCRIPT="${HOME}/.dotfiles/.scripts/guardian/guardian-shell-hooks.sh"
BASH_PROFILE="${HOME}/.bash_profile"

# Checksum storage
CHECKSUM_DIR="${HOME}/.config/failsafe"
CHECKSUM_FILE="${CHECKSUM_DIR}/checksums.sha256"
mkdir -p "${CHECKSUM_DIR}"

# Store original checksums if they don't exist yet
if [ ! -f "${CHECKSUM_FILE}" ]; then
    echo -e "${YELLOW}📝 Creating initial checksums...${NC}"
    
    # Initialize checksums file
    > "${CHECKSUM_FILE}"
    
    # Only store checksums for files that exist
    if [ -f "${GUARDIAN_RS}" ]; then
        sha256sum "${GUARDIAN_RS}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${FAILSAFE_MODULE}" ]; then
        sha256sum "${FAILSAFE_MODULE}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${INSTALLER}" ]; then
        sha256sum "${INSTALLER}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${INTEGRITY_CHECKER}" ]; then
        sha256sum "${INTEGRITY_CHECKER}" >> "${CHECKSUM_FILE}"
    fi
    
    # Store bash_profile reference only if it contains shell-guardian
    if [ -f "${BASH_PROFILE}" ] && grep -q "shell-guardian" "${BASH_PROFILE}"; then
        sha256sum "${BASH_PROFILE}" >> "${CHECKSUM_FILE}"
    fi
    
    chmod 600 "${CHECKSUM_FILE}"
    echo -e "${GREEN}✅ Initial checksums created${NC}"
fi

# Verify and repair if necessary
echo -e "${BLUE}🔍 Checking integrity...${NC}"

integrity_issue=false

# Check if guardian binary exists
if [ ! -f "${GUARDIAN_BIN}" ] && [ -f "${GUARDIAN_RS}" ] && [ -f "${INSTALLER}" ]; then
    echo -e "${YELLOW}⚠️ Shell Guardian binary missing, rebuilding...${NC}"
    bash "${INSTALLER}" > /dev/null
    echo -e "${GREEN}✅ Shell Guardian reinstalled${NC}"
    integrity_issue=true
fi

# Verify bash_profile integration
if [ -f "${BASH_PROFILE}" ] && ! grep -q "shell-guardian" "${BASH_PROFILE}" && [ -f "${INSTALLER}" ]; then
    echo -e "${YELLOW}⚠️ Shell Guardian not integrated in .bash_profile, fixing...${NC}"
    bash "${INSTALLER}" > /dev/null
    echo -e "${GREEN}✅ Shell Guardian integration restored${NC}"
    integrity_issue=true
fi

# Verify checksums of critical files
if [ -f "${CHECKSUM_FILE}" ]; then
    while IFS= read -r line; do
        checksum=$(echo "$line" | awk '{print $1}')
        file_path=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')
        
        if [ -f "$file_path" ]; then
            current_checksum=$(sha256sum "$file_path" | awk '{print $1}')
            
            # If the file was modified, restore from git if possible
            if [ "$checksum" != "$current_checksum" ]; then
                echo -e "${YELLOW}⚠️ Modified failsafe file detected: $(basename "$file_path")${NC}"
                
                # Check if we can restore from git
                if [[ "$file_path" == *".dotfiles"* ]] && cd "${HOME}/.dotfiles"; then
                    rel_path="${file_path#$HOME/.dotfiles/}"
                    echo -e "${BLUE}🔄 Restoring from git: $rel_path${NC}"
                    git checkout HEAD -- "$rel_path" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✅ Restored: $rel_path${NC}"
                    else
                        echo -e "${RED}❌ Failed to restore: $rel_path${NC}"
                    fi
                else
                    echo -e "${RED}❌ Cannot restore: $file_path${NC}"
                fi
                
                integrity_issue=true
            fi
        else
            echo -e "${YELLOW}⚠️ Missing failsafe file: $(basename "$file_path")${NC}"
            
            # Check if we can restore from git
            if [[ "$file_path" == *".dotfiles"* ]] && cd "${HOME}/.dotfiles"; then
                rel_path="${file_path#$HOME/.dotfiles/}"
                echo -e "${BLUE}🔄 Restoring from git: $rel_path${NC}"
                git checkout HEAD -- "$rel_path" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ Restored: $rel_path${NC}"
                else
                    echo -e "${RED}❌ Failed to restore: $rel_path${NC}"
                fi
            else
                echo -e "${RED}❌ Cannot restore: $file_path${NC}"
            fi
            
            integrity_issue=true
        fi
    done < "${CHECKSUM_FILE}"
fi

# Reinstall guardian if needed
if [ "$integrity_issue" = true ] && [ -f "${INSTALLER}" ]; then
    echo -e "${YELLOW}🔧 Integrity issues detected, reinstalling Shell Guardian...${NC}"
    bash "${INSTALLER}"
    echo -e "${GREEN}✅ Shell Guardian reinstalled${NC}"
fi

# Update checksums after repairs
if [ "$integrity_issue" = true ]; then
    echo -e "${BLUE}📝 Updating checksums after repairs...${NC}"
    > "${CHECKSUM_FILE}"
    
    # Only store checksums for files that exist
    if [ -f "${GUARDIAN_RS}" ]; then
        sha256sum "${GUARDIAN_RS}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${FAILSAFE_MODULE}" ]; then
        sha256sum "${FAILSAFE_MODULE}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${INSTALLER}" ]; then
        sha256sum "${INSTALLER}" >> "${CHECKSUM_FILE}"
    fi
    
    if [ -f "${INTEGRITY_CHECKER}" ]; then
        sha256sum "${INTEGRITY_CHECKER}" >> "${CHECKSUM_FILE}"
    fi
    
    # Store bash_profile reference only if it contains shell-guardian
    if [ -f "${BASH_PROFILE}" ] && grep -q "shell-guardian" "${BASH_PROFILE}"; then
        sha256sum "${BASH_PROFILE}" >> "${CHECKSUM_FILE}"
    fi
    
    chmod 600 "${CHECKSUM_FILE}"
    echo -e "${GREEN}✅ Checksums updated${NC}"
else
    echo -e "${GREEN}✅ All failsafe systems intact${NC}"
fi