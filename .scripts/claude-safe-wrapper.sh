#!/bin/bash
# Claude Safe Wrapper - Prevents runaway processes and resource exhaustion
# Wraps commands to enforce limits and monitor execution

set -euo pipefail

# Configuration
MAX_PROCS=100
MAX_THREADS=200
MAX_FD_THREADS=2  # Force fd to use only 2 threads
MAX_CPU_TIME=300  # 5 minutes
MAX_MEM_MB=2048
TIMEOUT_SECONDS=600  # 10 minutes max

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Parse command
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command> [args...]"
    echo "Safely executes commands with resource limits"
    exit 1
fi

CMD="$1"
shift

# Function to kill process tree
kill_tree() {
    local pid=$1
    local children=$(pgrep -P "$pid" 2>/dev/null || true)
    
    for child in $children; do
        kill_tree "$child"
    done
    
    kill -TERM "$pid" 2>/dev/null || true
}

# Function to monitor process
monitor_process() {
    local pid=$1
    local start_time=$(date +%s)
    local warned=0
    
    while kill -0 "$pid" 2>/dev/null; do
        # Check process count
        local proc_count=$(pgrep -u "$USER" | wc -l)
        if [ "$proc_count" -gt "$MAX_PROCS" ] && [ "$warned" -eq 0 ]; then
            echo -e "${YELLOW}⚠️  Warning: High process count ($proc_count)${NC}" >&2
            warned=1
        fi
        
        # Check timeout
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ "$elapsed" -gt "$TIMEOUT_SECONDS" ]; then
            echo -e "${RED}❌ Timeout: Killing process after ${TIMEOUT_SECONDS}s${NC}" >&2
            kill_tree "$pid"
            return 1
        fi
        
        sleep 1
    done
}

# Special handling for known problematic commands
case "$CMD" in
    fd|find)
        # Force limited threads for fd
        echo -e "${YELLOW}🔒 Limiting fd to $MAX_FD_THREADS threads${NC}" >&2
        export FD_THREADS=$MAX_FD_THREADS
        
        # Replace find with fd
        if [ "$CMD" = "find" ]; then
            CMD="fd"
            # Convert basic find syntax to fd
            # This is a simple conversion, may need enhancement
            set -- $(echo "$@" | sed 's/-name/-g/g; s/-type f/-t f/g; s/-type d/-t d/g')
        fi
        
        # Add thread limit to fd command
        if [ "$CMD" = "fd" ] && ! echo "$@" | grep -q -- "--threads"; then
            set -- "--threads=$MAX_FD_THREADS" "$@"
        fi
        ;;
    
    cargo)
        # Limit cargo parallelism
        export CARGO_BUILD_JOBS=2
        export RUST_MIN_THREADS=1
        export RUST_MAX_THREADS=4
        echo -e "${YELLOW}🔒 Limiting cargo to 2 parallel jobs${NC}" >&2
        ;;
    
    make)
        # Limit make parallelism
        if ! echo "$@" | grep -q -- "-j"; then
            set -- "-j2" "$@"
        fi
        echo -e "${YELLOW}🔒 Limiting make to 2 parallel jobs${NC}" >&2
        ;;
esac

# Create a temporary script to run with limits
TEMP_SCRIPT=$(mktemp)
trap "rm -f $TEMP_SCRIPT" EXIT

cat > "$TEMP_SCRIPT" << EOF
#!/bin/bash
# Apply resource limits
ulimit -u $MAX_PROCS      # Max processes
ulimit -t $MAX_CPU_TIME   # CPU time limit
ulimit -v $((MAX_MEM_MB * 1024))  # Memory limit
ulimit -n 1024            # File descriptors

# Export limits for child processes
export GOMAXPROCS=2
export OMP_NUM_THREADS=2
export MKL_NUM_THREADS=2
export NUMEXPR_NUM_THREADS=2
export VECLIB_MAXIMUM_THREADS=2

# Run the command
exec $CMD "\$@"
EOF

chmod +x "$TEMP_SCRIPT"

# Execute with monitoring
echo -e "${GREEN}🛡️  Running: $CMD $*${NC}" >&2
echo -e "${GREEN}   Limits: ${MAX_PROCS} procs, ${MAX_MEM_MB}MB mem, ${TIMEOUT_SECONDS}s timeout${NC}" >&2

# Run the command with monitoring
(
    "$TEMP_SCRIPT" "$@" &
    PID=$!
    
    # Monitor in background
    monitor_process "$PID" &
    MONITOR_PID=$!
    
    # Wait for command to finish
    wait "$PID"
    EXIT_CODE=$?
    
    # Kill monitor
    kill "$MONITOR_PID" 2>/dev/null || true
    
    exit "$EXIT_CODE"
)