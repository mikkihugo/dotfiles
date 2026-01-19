# Process cleanup hooks for Zsh
# Automatically terminates orphaned development processes on disconnect

_cleanup_processes() {
    local user="$(whoami)"

    # Kill orphaned Node processes
    pkill -u "$user" -f "node.*" 2>/dev/null || true

    # Kill orphaned code-cli processes
    pkill -u "$user" -f "code-cli" 2>/dev/null || true

    # Kill orphaned Claude processes
    pkill -u "$user" -f "claude" 2>/dev/null || true

    # Kill orphaned npm processes
    pkill -u "$user" -f "npm" 2>/dev/null || true
}

# Hook on exit
ZSHEXIT=(_cleanup_processes)

# Also on session close
trap '_cleanup_processes' EXIT
