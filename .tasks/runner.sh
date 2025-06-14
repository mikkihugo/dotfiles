#!/bin/bash
# Background task runner - no clutter, just results

TASK_DIR="$HOME/.dotfiles/.tasks"
TASK_LOG="$TASK_DIR/task.log"

# Run task in background, show minimal output
run_task() {
    local task="$1"
    local desc="$2"
    shift 2
    
    echo "⏳ $desc..."
    
    # Run task, capture output
    if "$@" > "$TASK_LOG" 2>&1; then
        echo "✅ $desc"
    else
        echo "❌ $desc failed"
        echo "   See: task log"
    fi
}

# Task definitions
task_update() {
    run_task "update" "Updating tools" mise upgrade
}

task_cleanup() {
    run_task "cleanup" "Cleaning up" sh -c "
        find ~/.cache -type f -atime +7 -delete 2>/dev/null || true
        find /tmp -user \$(whoami) -type f -mtime +1 -delete 2>/dev/null || true
        du -sh ~/.cache ~/.local/share/Trash 2>/dev/null | sed 's/^/  /'
    "
}

task_backup() {
    run_task "backup" "Syncing dotfiles" sh -c "
        cd ~/.dotfiles
        git add -A
        git commit -m 'Auto sync - \$(date)' || true
        git push
    "
}

task_status() {
    echo "📊 System Status"
    
    # Disk usage (simple)
    df -h / | awk 'NR==2{printf "   Disk: %s used\n", $5}'
    
    # Memory (simple)
    free -h | awk 'NR==2{printf "   RAM: %.0f%% used\n", $3/$2*100}'
    
    # Mise tools count
    echo "   Tools: $(mise list | wc -l) installed"
    
    # Recent tasks
    if [ -f "$TASK_LOG" ]; then
        echo "   Last task: $(stat -c %y "$TASK_LOG" | cut -d' ' -f1-2)"
    fi
}

task_log() {
    if [ -f "$TASK_LOG" ]; then
        echo "📋 Last Task Output:"
        echo "$(cat "$TASK_LOG")" | sed 's/^/   /'
    else
        echo "No task logs yet"
    fi
}

task_containers() {
    echo "🐳 Containers"
    docker ps --format "table {{.Names}}\t{{.Status}}" | sed 's/^/   /'
    local stopped=$(docker ps -a -q --filter "status=exited" | wc -l)
    [ "$stopped" -gt 0 ] && echo "   ⚠️  $stopped stopped"
}

task_fix() {
    run_task "fix" "Fixing containers" sh -c "
        # Restart exited containers
        for container in \$(docker ps -a --filter 'status=exited' --format '{{.Names}}'); do
            echo \"Restarting \$container...\"
            docker start \$container
        done
        
        # Show final status
        docker ps --format 'table {{.Names}}\t{{.Status}}'
    "
}

# Quick task shortcuts
case "${1:-}" in
    "up"|"update")
        task_update
        ;;
    "clean"|"cleanup")
        task_cleanup
        ;;
    "sync"|"backup")
        task_backup
        ;;
    "s"|"status")
        task_status
        ;;
    "log"|"logs")
        task_log
        ;;
    "c")
        task_containers
        ;;
    "fix")
        task_fix
        ;;
    "")
        echo "🎯 Quick Tasks"
        echo "   up     - Update tools"
        echo "   clean  - Cleanup cache/temp"
        echo "   sync   - Backup dotfiles"
        echo "   s      - System status"
        echo "   c      - Containers"
        echo "   fix    - Fix stopped containers"
        echo "   log    - Show last task output"
        ;;
    *)
        echo "Unknown task: $1"
        echo "Run 'task' for available tasks"
        ;;
esac