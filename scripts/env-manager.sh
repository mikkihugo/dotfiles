#!/bin/bash
# 🔐 Secure Environment Variable Manager
# Handles sensitive tokens and environment variables

ENV_FILE="$HOME/.env"
ENV_ENCRYPTED="$HOME/.env.gpg"

show_help() {
    echo "🔐 Environment Variable Manager"
    echo ""
    echo "Usage: env-manager.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  setup     - Initial setup with encryption"
    echo "  encrypt   - Encrypt .env file"
    echo "  decrypt   - Decrypt .env file"
    echo "  edit      - Edit encrypted environment file"
    echo "  load      - Load environment variables"
    echo "  backup    - Backup encrypted env to git"
    echo "  restore   - Restore env from backup"
    echo "  help      - Show this help"
    echo ""
    echo "Examples:"
    echo "  env-manager.sh setup"
    echo "  env-manager.sh edit"
    echo "  source <(env-manager.sh load)"
}

setup_env() {
    echo "🔧 Setting up secure environment management..."
    
    # Check if GPG is available
    if ! command -v gpg >/dev/null; then
        echo "❌ GPG not found. Install with: sudo dnf install gnupg"
        exit 1
    fi
    
    # Create .env from template if it doesn't exist
    if [[ ! -f "$ENV_FILE" ]]; then
        cp "$HOME/dotfiles/.env.example" "$ENV_FILE"
        echo "📝 Created $ENV_FILE from template"
        echo "✏️  Please edit it with your actual values"
    fi
    
    echo "🔑 Encrypting environment file..."
    encrypt_env
    
    echo "✅ Setup complete!"
    echo "💡 Use 'env-manager.sh edit' to modify variables"
}

encrypt_env() {
    if [[ -f "$ENV_FILE" ]]; then
        gpg --cipher-algo AES256 --compress-algo 1 --symmetric --output "$ENV_ENCRYPTED" "$ENV_FILE"
        rm "$ENV_FILE"  # Remove unencrypted version
        echo "🔒 Environment encrypted to $ENV_ENCRYPTED"
    else
        echo "❌ No .env file found to encrypt"
        exit 1
    fi
}

decrypt_env() {
    if [[ -f "$ENV_ENCRYPTED" ]]; then
        gpg --quiet --decrypt --output "$ENV_FILE" "$ENV_ENCRYPTED"
        echo "🔓 Environment decrypted to $ENV_FILE"
    else
        echo "❌ No encrypted environment file found"
        exit 1
    fi
}

edit_env() {
    echo "✏️  Editing environment variables..."
    
    # Decrypt temporarily
    decrypt_env
    
    # Edit with user's preferred editor
    ${EDITOR:-nano} "$ENV_FILE"
    
    # Re-encrypt
    encrypt_env
    
    echo "✅ Environment updated and encrypted"
}

load_env() {
    # Temporarily decrypt and source
    if [[ -f "$ENV_ENCRYPTED" ]]; then
        gpg --quiet --decrypt "$ENV_ENCRYPTED" 2>/dev/null | while IFS= read -r line; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ $line =~ ^[[:space:]]*$ ]] && continue
            echo "export $line"
        done
    else
        echo "❌ No encrypted environment file found" >&2
        exit 1
    fi
}

backup_env() {
    if [[ -f "$ENV_ENCRYPTED" ]]; then
        cp "$ENV_ENCRYPTED" "$HOME/dotfiles/config/.env.gpg"
        echo "💾 Backed up encrypted environment to dotfiles"
    else
        echo "❌ No encrypted environment to backup"
        exit 1
    fi
}

restore_env() {
    if [[ -f "$HOME/dotfiles/config/.env.gpg" ]]; then
        cp "$HOME/dotfiles/config/.env.gpg" "$ENV_ENCRYPTED"
        echo "📥 Restored encrypted environment from dotfiles"
    else
        echo "❌ No backup found in dotfiles"
        exit 1
    fi
}

# Main command handling
case "${1:-help}" in
    setup)
        setup_env
        ;;
    encrypt)
        encrypt_env
        ;;
    decrypt)
        decrypt_env
        ;;
    edit)
        edit_env
        ;;
    load)
        load_env
        ;;
    backup)
        backup_env
        ;;
    restore)
        restore_env
        ;;
    help|*)
        show_help
        ;;
esac