#!/bin/bash
# Enhanced mosh wrapper with better defaults

# Default mosh options for better experience
MOSH_OPTS=(
    "--predict=adaptive"           # Smart prediction
    "--server-timeout=86400"       # 24 hour timeout  
    "--ssh-pty-name=/dev/pts/0"   # Better PTY handling
)

# Add port range if specified
if [[ -n "$MOSH_PORT_RANGE" ]]; then
    MOSH_OPTS+=("--port=$MOSH_PORT_RANGE")
fi

# Execute mosh with enhanced options
exec mosh "${MOSH_OPTS[@]}" "$@"