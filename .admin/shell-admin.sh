#!/bin/bash
# Hidden admin shell tasks - accessed via user shell
# Usage: admin <task> [args]

set -euo pipefail

ADMIN_LOG="$HOME/.dotfiles/.admin/admin.log"
ADMIN_AUTH="$HOME/.dotfiles/.admin/.auth"

# Log all admin actions
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$$] $*" >> "$ADMIN_LOG"
}

# Simple auth check
check_auth() {
    if [ ! -f "$ADMIN_AUTH" ]; then
        echo "🔐 Admin mode not unlocked"
        echo "Run: echo 'admin-$(date +%Y%m%d)' > ~/.dotfiles/.admin/.auth"
        exit 1
    fi
    
    local token=$(cat "$ADMIN_AUTH" 2>/dev/null || echo "")
    local expected="admin-$(date +%Y%m%d)"
    
    if [ "$token" != "$expected" ]; then
        echo "🔐 Admin token expired or invalid"
        echo "Run: echo 'admin-$(date +%Y%m%d)' > ~/.dotfiles/.admin/.auth"
        exit 1
    fi
}

# System maintenance tasks
task_system() {
    case "${2:-}" in
        "cleanup")
            log_action "SYSTEM cleanup"
            echo "🧹 System cleanup..."
            
            # Clean package cache
            echo "  • Cleaning package cache..."
            sudo dnf clean all 2>/dev/null || echo "    (skipped - no sudo)"
            
            # Clean old logs
            echo "  • Cleaning old logs..."
            find ~/.cache -type f -atime +30 -delete 2>/dev/null || true
            find ~/.local/share/Trash -type f -mtime +7 -delete 2>/dev/null || true
            
            # Clean temp files
            echo "  • Cleaning temp files..."
            find /tmp -user $(whoami) -type f -mtime +1 -delete 2>/dev/null || true
            
            echo "✅ Cleanup complete"
            ;;
            
        "update")
            log_action "SYSTEM update"
            echo "🔄 System update..."
            
            # Update mise tools
            echo "  • Updating mise tools..."
            mise upgrade
            
            # Update dotfiles
            echo "  • Updating dotfiles..."
            cd ~/.dotfiles && git pull --rebase
            
            echo "✅ Update complete"
            ;;
            
        "status")
            log_action "SYSTEM status"
            echo "📊 System status..."
            
            echo "  • Disk usage:"
            df -h / | tail -n1 | awk '{print "    Root: " $5 " used (" $3 "/" $2 ")"}'
            df -h "$HOME" 2>/dev/null | tail -n1 | awk '{print "    Home: " $5 " used (" $3 "/" $2 ")"}' || echo "    Home: same as root"
            
            echo "  • Memory usage:"
            free -h | awk 'NR==2{printf "    RAM: %.0f%% used (%s/%s)\n", $3/$2*100, $3, $2}'
            
            echo "  • Load average:"
            uptime | awk -F'load average:' '{print "    " $2}'
            
            echo "  • Services:"
            systemctl --user is-active guardian-keeper 2>/dev/null | sed 's/^/    Guardian: /' || echo "    Guardian: not installed"
            ;;
            
        *)
            echo "System tasks: cleanup, update, status"
            ;;
    esac
}

# Guardian management
task_guardian() {
    case "${2:-}" in
        "install")
            log_action "GUARDIAN install"
            echo "🛡️ Installing guardian..."
            cd ~/.dotfiles/.guardian-shell
            ./build.sh
            echo "✅ Guardian installed"
            ;;
            
        "logs")
            log_action "GUARDIAN logs"
            echo "📋 Guardian logs:"
            if [ -f ~/.guardian.log ]; then
                echo "  Recent activity:"
                tail -10 ~/.guardian.log | while read -r line; do
                    if [[ "$line" =~ ^[0-9]+$ ]]; then
                        echo "    $(date -d @$line '+%Y-%m-%d %H:%M:%S') - Shell started"
                    else
                        echo "    $line"
                    fi
                done
            else
                echo "  No guardian log found"
            fi
            ;;
            
        "test")
            log_action "GUARDIAN test"
            echo "🧪 Testing guardian..."
            ~/.local/bin/shell-guardian echo "Guardian test successful!"
            ;;
            
        "reset")
            log_action "GUARDIAN reset"
            echo "🔄 Resetting guardian logs..."
            rm -f ~/.guardian.log
            echo "✅ Guardian logs cleared"
            ;;
            
        *)
            echo "Guardian tasks: install, logs, test, reset"
            ;;
    esac
}

# Network and security tasks
task_security() {
    case "${2:-}" in
        "ports")
            log_action "SECURITY ports"
            echo "🔌 Open ports:"
            ss -tuln | awk 'NR>1 {print "  " $1 " " $5}' | sort -u
            ;;
            
        "keys")
            log_action "SECURITY keys"
            echo "🔑 SSH keys:"
            ls -la ~/.ssh/*.pub 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}' || echo "  No SSH keys found"
            ;;
            
        "backup")
            log_action "SECURITY backup"
            echo "💾 Creating secure backup..."
            
            # Backup dotfiles
            cd ~/.dotfiles
            git add -A
            git commit -m "Admin backup - $(date)" || echo "  No changes to commit"
            git push || echo "  Push failed (offline?)"
            
            # Backup tokens to gist
            if [ -f ~/.env_tokens ]; then
                echo "  Backing up tokens to gist..."
                gh gist edit "$TABBY_GIST_ID" ~/.env_tokens 2>/dev/null || echo "  Gist backup failed"
            fi
            
            echo "✅ Backup complete"
            ;;
            
        *)
            echo "Security tasks: ports, keys, backup"
            ;;
    esac
}

# Development environment tasks
task_dev() {
    case "${2:-}" in
        "clean")
            log_action "DEV clean"
            echo "🧹 Cleaning development environment..."
            
            # Clean node modules
            find ~/code -name "node_modules" -type d -exec du -sh {} \; 2>/dev/null | head -5
            echo "  Found node_modules directories (use 'admin dev clean-npm' to remove)"
            
            # Clean cargo cache
            if [ -d ~/.cargo ]; then
                echo "  Cargo cache: $(du -sh ~/.cargo 2>/dev/null | cut -f1)"
            fi
            ;;
            
        "clean-npm")
            log_action "DEV clean-npm"
            echo "🗑️ Removing node_modules..."
            find ~/code -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null
            echo "✅ node_modules cleaned"
            ;;
            
        "projects")
            log_action "DEV projects"
            echo "📁 Development projects:"
            if [ -d ~/code ]; then
                ls -la ~/code | awk 'NR>3 {print "  " $9 " (modified " $6 " " $7 ")"}'
            else
                echo "  No ~/code directory found"
            fi
            ;;
            
        *)
            echo "Dev tasks: clean, clean-npm, projects"
            ;;
    esac
}

# Main task dispatcher
main() {
    check_auth
    
    case "${1:-}" in
        "system")
            task_system "$@"
            ;;
        "guardian")
            task_guardian "$@"
            ;;
        "security")
            task_security "$@"
            ;;
        "dev")
            task_dev "$@"
            ;;
        "logs")
            log_action "ADMIN logs"
            echo "📋 Admin logs:"
            tail -20 "$ADMIN_LOG" 2>/dev/null || echo "  No admin logs found"
            ;;
        "help"|"")
            echo "🔧 Admin Shell Tasks"
            echo ""
            echo "Categories:"
            echo "  system   - System maintenance (cleanup, update, status)"
            echo "  guardian - Guardian management (install, logs, test, reset)"
            echo "  security - Security tasks (ports, keys, backup)"
            echo "  dev      - Development environment (clean, projects)"
            echo "  logs     - Show admin activity logs"
            echo ""
            echo "Usage: admin <category> <task>"
            echo "Example: admin system cleanup"
            ;;
        *)
            echo "❌ Unknown task: $1"
            echo "Run 'admin help' for available tasks"
            exit 1
            ;;
    esac
}

main "$@"