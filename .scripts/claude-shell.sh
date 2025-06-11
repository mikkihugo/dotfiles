#!/bin/bash
# Claude Shell - Resource-controlled environment for AI code execution
# Prevents runaway processes by throttling instead of killing

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
CLAUDE_SHELL_NAME="claude-controlled"
MAX_CPU_PERCENT=50
MAX_MEM_MB=2048
MAX_PROCS=500
MAX_THREADS=1000
NICE_LEVEL=10

# Check if running as claude shell already
if [[ "${CLAUDE_SHELL:-}" == "active" ]]; then
    echo -e "${YELLOW}Already in Claude Shell environment${NC}"
    exec bash "$@"
fi

echo -e "${BLUE}🤖 Claude Shell - Resource-Controlled Environment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Function to create cgroup v2 limits (if available)
setup_cgroup_v2() {
    local cgroup_path="/sys/fs/cgroup/user.slice/user-$(id -u).slice/claude-shell"
    
    if [ -d "/sys/fs/cgroup/user.slice" ] && [ -w "/sys/fs/cgroup/user.slice/user-$(id -u).slice" ]; then
        # Try to create cgroup
        if mkdir -p "$cgroup_path" 2>/dev/null; then
            # Set memory limit
            echo "$((MAX_MEM_MB * 1024 * 1024))" > "$cgroup_path/memory.max" 2>/dev/null || true
            # Set CPU limit (in microseconds per 100ms)
            echo "$((MAX_CPU_PERCENT * 1000))" > "$cgroup_path/cpu.max" 2>/dev/null || true
            
            # Add current process to cgroup
            echo $$ > "$cgroup_path/cgroup.procs" 2>/dev/null || true
            
            echo -e "${GREEN}✓ cgroup v2 limits applied${NC}"
            return 0
        fi
    fi
    return 1
}

# Function to monitor and throttle processes
monitor_resources() {
    local pid=$1
    local monitored_pids=()
    
    while kill -0 "$pid" 2>/dev/null; do
        # Get all child processes
        local all_pids=$(pgrep -P "$pid" 2>/dev/null || true)
        all_pids="$pid $all_pids"
        
        for p in $all_pids; do
            if [[ ! " ${monitored_pids[@]} " =~ " $p " ]]; then
                # Apply nice level to new processes
                renice -n "$NICE_LEVEL" -p "$p" &>/dev/null || true
                ionice -c 3 -p "$p" &>/dev/null || true
                monitored_pids+=("$p")
            fi
            
            # Check CPU usage and throttle if needed
            local cpu_usage=$(ps -p "$p" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "0")
            if (( $(echo "$cpu_usage > $MAX_CPU_PERCENT" | bc -l 2>/dev/null || echo 0) )); then
                # Send SIGSTOP briefly to throttle
                kill -STOP "$p" 2>/dev/null || true
                sleep 0.1
                kill -CONT "$p" 2>/dev/null || true
            fi
        done
        
        sleep 1
    done
}

# Display current limits
echo -e "${BLUE}Resource Limits:${NC}"
echo -e "  CPU: ${GREEN}${MAX_CPU_PERCENT}%${NC} (throttled, not killed)"
echo -e "  Memory: ${GREEN}${MAX_MEM_MB}MB${NC}"
echo -e "  Processes: ${GREEN}${MAX_PROCS}${NC}"
echo -e "  Threads: ${GREEN}${MAX_THREADS}${NC}"
echo -e "  Nice Level: ${GREEN}+${NICE_LEVEL}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Try to set up cgroup v2 (non-fatal if it fails)
setup_cgroup_v2 || echo -e "${YELLOW}! Using fallback resource control${NC}"

# Create a new shell with resource limits
export CLAUDE_SHELL="active"
export PS1="\[\033[0;35m\]🤖 claude-shell\[\033[0m\] \w $ "

# Resource limits that won't kill processes
ulimit -u "$MAX_PROCS"      # Max user processes
ulimit -n 4096              # Max open files
ulimit -s 8192              # Stack size (KB)

# Soft memory limit (won't kill, but will slow down)
if command -v systemd-run &>/dev/null; then
    # Use systemd-run for better resource control
    exec systemd-run \
        --uid=$(id -u) \
        --gid=$(id -g) \
        --setenv=CLAUDE_SHELL=active \
        --setenv=HOME="$HOME" \
        --setenv=USER="$USER" \
        --setenv=PATH="$PATH" \
        --property=MemoryMax="${MAX_MEM_MB}M" \
        --property=MemorySwapMax=0 \
        --property=CPUQuota="${MAX_CPU_PERCENT}%" \
        --scope \
        --slice=user.slice \
        bash --rcfile <(echo '
            source ~/.bashrc
            export PS1="\[\033[0;35m\]🤖 claude-shell\[\033[0m\] \w $ "
            
            # Override dangerous commands
            alias find="fd --threads=2"
            alias fd="fd --threads=2"
            
            # Limit parallel execution
            export MAKEFLAGS="-j2"
            export CARGO_BUILD_JOBS=2
            export RUST_MIN_THREADS=1
            export RUST_MAX_THREADS=4
            
            echo -e "\033[0;32m✓ Claude Shell ready - processes will be throttled, not killed\033[0m"
        ')
else
    # Fallback to nice + monitor approach
    (
        # Start monitoring in background
        monitor_resources $$ &
        MONITOR_PID=$!
        
        # Cleanup on exit
        trap "kill $MONITOR_PID 2>/dev/null || true" EXIT
        
        # Start limited shell
        nice -n "$NICE_LEVEL" bash --rcfile <(echo '
            source ~/.bashrc
            export PS1="\[\033[0;35m\]🤖 claude-shell\[\033[0m\] \w $ "
            
            # Override dangerous commands
            alias find="fd --threads=2"
            alias fd="fd --threads=2"
            
            # Limit parallel execution
            export MAKEFLAGS="-j2"
            export CARGO_BUILD_JOBS=2
            export RUST_MIN_THREADS=1
            export RUST_MAX_THREADS=4
            
            echo -e "\033[0;32m✓ Claude Shell ready - processes will be throttled, not killed\033[0m"
        ')
    )
fi