#!/bin/bash
# Safe execution wrapper to prevent runaway processes

# Default limits
MAX_PROCS=${MAX_PROCS:-1000}
MAX_THREADS=${MAX_THREADS:-2000}
MAX_CPU_TIME=${MAX_CPU_TIME:-300}  # 5 minutes
MAX_MEM_MB=${MAX_MEM_MB:-4096}     # 4GB

# Parse arguments
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --max-procs)
            MAX_PROCS="$2"
            shift 2
            ;;
        --max-threads)
            MAX_THREADS="$2"
            shift 2
            ;;
        --max-cpu)
            MAX_CPU_TIME="$2"
            shift 2
            ;;
        --max-mem)
            MAX_MEM_MB="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: $0 [options] -- command [args...]"
    echo "Options:"
    echo "  --max-procs N    Max processes (default: $MAX_PROCS)"
    echo "  --max-threads N  Max threads (default: $MAX_THREADS)"
    echo "  --max-cpu N      Max CPU seconds (default: $MAX_CPU_TIME)"
    echo "  --max-mem N      Max memory in MB (default: $MAX_MEM_MB)"
    echo "  --verbose|-v     Show limits being applied"
    exit 1
fi

if [ $VERBOSE -eq 1 ]; then
    echo "🛡️  Running with resource limits:"
    echo "   Max processes: $MAX_PROCS"
    echo "   Max threads: $MAX_THREADS"
    echo "   Max CPU time: ${MAX_CPU_TIME}s"
    echo "   Max memory: ${MAX_MEM_MB}MB"
    echo "   Command: $*"
    echo ""
fi

# Apply resource limits
(
    # Limit number of processes
    ulimit -u "$MAX_PROCS"
    
    # Limit CPU time
    ulimit -t "$MAX_CPU_TIME"
    
    # Limit memory (in KB)
    ulimit -v $((MAX_MEM_MB * 1024))
    
    # Limit file descriptors
    ulimit -n 4096
    
    # For Rust programs specifically, set thread limits
    export RUST_MIN_STACK=2097152  # 2MB per thread
    export RUST_THREADS="$MAX_THREADS"
    
    # Execute the command
    exec "$@"
)