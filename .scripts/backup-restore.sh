#!/bin/bash
# Enhanced backup/restore system for tmux sessions and shell history

BACKUP_DIR="$HOME/.dotfiles-backups"
mkdir -p "$BACKUP_DIR"

# Backup everything
backup_all() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/backup-$timestamp.tar.gz"
    
    echo "🔄 Creating backup..."
    
    # Create temporary directory for backup
    local temp_dir=$(mktemp -d)
    
    # Backup tmux sessions
    if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
        mkdir -p "$temp_dir/tmux"
        ~/.dotfiles/.scripts/tmux-save-restore.sh save
        cp -r ~/.tmux-sessions/* "$temp_dir/tmux/" 2>/dev/null || true
    fi
    
    # Backup shell history
    mkdir -p "$temp_dir/history"
    [ -f ~/.bash_history ] && cp ~/.bash_history "$temp_dir/history/"
    [ -f ~/.zsh_history ] && cp ~/.zsh_history "$temp_dir/history/"
    
    # Backup SSH config and keys
    if [ -d ~/.ssh ]; then
        mkdir -p "$temp_dir/ssh"
        cp ~/.ssh/config "$temp_dir/ssh/" 2>/dev/null || true
        cp ~/.ssh/known_hosts "$temp_dir/ssh/" 2>/dev/null || true
    fi
    
    # Backup current directory list (for zoxide)
    if command -v zoxide >/dev/null 2>&1; then
        mkdir -p "$temp_dir/zoxide"
        zoxide query -l > "$temp_dir/zoxide/directories.txt" 2>/dev/null || true
    fi
    
    # Create archive
    tar -czf "$backup_file" -C "$temp_dir" . 2>/dev/null
    rm -rf "$temp_dir"
    
    # Keep only last 10 backups
    ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
    
    echo "✅ Backup saved: $backup_file"
}

# Restore from backup
restore_backup() {
    local backup_file
    
    # Select backup file
    if command -v gum &>/dev/null; then
        backup_file=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | \
                     gum choose --header "Select backup to restore:")
    else
        backup_file=$(ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | head -1)
    fi
    
    if [ -z "$backup_file" ]; then
        echo "❌ No backups found"
        return 1
    fi
    
    echo "🔄 Restoring from $(basename "$backup_file")..."
    
    # Extract to temp directory
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null
    
    # Restore tmux sessions
    if [ -d "$temp_dir/tmux" ]; then
        cp -r "$temp_dir/tmux"/* ~/.tmux-sessions/ 2>/dev/null || true
        echo "📋 Tmux sessions restored"
    fi
    
    # Restore shell history (with backup)
    if [ -d "$temp_dir/history" ]; then
        [ -f "$temp_dir/history/.bash_history" ] && {
            [ -f ~/.bash_history ] && cp ~/.bash_history ~/.bash_history.backup
            cp "$temp_dir/history/.bash_history" ~/.bash_history
        }
        [ -f "$temp_dir/history/.zsh_history" ] && {
            [ -f ~/.zsh_history ] && cp ~/.zsh_history ~/.zsh_history.backup
            cp "$temp_dir/history/.zsh_history" ~/.zsh_history
        }
        echo "📚 Shell history restored"
    fi
    
    # Restore zoxide data
    if [ -f "$temp_dir/zoxide/directories.txt" ] && command -v zoxide >/dev/null 2>&1; then
        while read -r dir; do
            [ -d "$dir" ] && zoxide add "$dir" 2>/dev/null
        done < "$temp_dir/zoxide/directories.txt"
        echo "📁 Directory history restored"
    fi
    
    rm -rf "$temp_dir"
    echo "✅ Restore complete!"
}

# Auto-backup on logout (if enabled)
auto_backup() {
    if [ "${AUTO_BACKUP:-false}" = "true" ]; then
        echo "🔄 Auto-backup on logout..."
        backup_all
    fi
}

# Main menu
case "${1:-menu}" in
    backup)
        backup_all
        ;;
    restore)
        restore_backup
        ;;
    auto)
        auto_backup
        ;;
    menu)
        if command -v gum &>/dev/null; then
            choice=$(gum choose "💾 Create backup" "📦 Restore backup" "📋 List backups" "🗑️  Delete old backups" "❌ Cancel")
            case "$choice" in
                "💾 Create backup") backup_all ;;
                "📦 Restore backup") restore_backup ;;
                "📋 List backups") 
                    echo "📋 Available backups:"
                    ls -lah "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null || echo "No backups found"
                    ;;
                "🗑️  Delete old backups")
                    ls -t "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
                    echo "🗑️  Deleted old backups (kept 5 most recent)"
                    ;;
            esac
        else
            echo "1) Create backup"
            echo "2) Restore backup"  
            echo "3) List backups"
            echo "4) Cancel"
            read -p "Choice: " choice
            case "$choice" in
                1) backup_all ;;
                2) restore_backup ;;
                3) ls -lah "$BACKUP_DIR"/backup-*.tar.gz 2>/dev/null || echo "No backups found" ;;
            esac
        fi
        ;;
esac