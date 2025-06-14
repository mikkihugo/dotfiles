#!/bin/bash
# Key Guardian Helper - Easy interface to key-guardian

KEY_GUARDIAN_BIN="$HOME/.local/bin/key-guardian"
KEY_GUARDIAN_SOCKET="/tmp/key-guardian.sock"

# Start key guardian daemon
start_key_guardian() {
    if pgrep -f "key-guardian daemon" >/dev/null; then
        echo "Key guardian already running"
        return 0
    fi
    
    # Check if binary exists
    if [ ! -f "$KEY_GUARDIAN_BIN" ]; then
        echo "Key guardian not installed. Run: guardian-control.sh rebuild"
        return 1
    fi
    
    # Determine provider
    local provider="${KEY_GUARDIAN_PROVIDER:-file}"
    
    if command -v doppler &>/dev/null && doppler configure get token &>/dev/null; then
        provider="doppler"
        echo "Starting key guardian with Doppler..."
    else
        echo "Starting key guardian with file provider..."
    fi
    
    # Start daemon
    nohup "$KEY_GUARDIAN_BIN" daemon "$provider" > /tmp/key-guardian.log 2>&1 &
    
    # Wait for startup
    sleep 2
    
    if [ -S "$KEY_GUARDIAN_SOCKET" ]; then
        echo "✓ Key guardian started (PID: $(pgrep -f 'key-guardian daemon'))"
        "$KEY_GUARDIAN_BIN" status
    else
        echo "❌ Failed to start key guardian"
        tail -10 /tmp/key-guardian.log
        return 1
    fi
}

# Stop key guardian
stop_key_guardian() {
    if pgrep -f "key-guardian daemon" >/dev/null; then
        pkill -f "key-guardian daemon"
        rm -f "$KEY_GUARDIAN_SOCKET"
        echo "✓ Key guardian stopped"
    else
        echo "Key guardian not running"
    fi
}

# Load environment from key guardian
load_env_from_guardian() {
    if [ ! -S "$KEY_GUARDIAN_SOCKET" ]; then
        echo "# Key guardian not running, falling back to file" >&2
        if [ -f "$HOME/.env_tokens" ]; then
            cat "$HOME/.env_tokens" | grep -v '^#' | grep '='
        fi
        return
    fi
    
    "$KEY_GUARDIAN_BIN" env
}

# Get specific key
get_key() {
    local key="$1"
    if [ -z "$key" ]; then
        echo "Usage: get_key KEY_NAME" >&2
        return 1
    fi
    
    if [ ! -S "$KEY_GUARDIAN_SOCKET" ]; then
        # Fallback to grep from file
        if [ -f "$HOME/.env_tokens" ]; then
            grep "^export $key=" "$HOME/.env_tokens" | cut -d= -f2- | tr -d '"'
        fi
        return
    fi
    
    "$KEY_GUARDIAN_BIN" get "$key"
}

# Shell integration function
setup_shell_integration() {
    cat << 'EOF'
# Key Guardian Integration
if [ -S "/tmp/key-guardian.sock" ]; then
    # Load from key guardian
    eval "$(key-guardian env 2>/dev/null)"
elif [ -f "$HOME/.env_tokens" ]; then
    # Fallback to file
    set -a
    source "$HOME/.env_tokens" 2>/dev/null || true
    set +a
fi

# Helper function for getting keys
get_secret() {
    if command -v key-guardian &>/dev/null; then
        key-guardian get "$1"
    else
        grep "^export $1=" "$HOME/.env_tokens" 2>/dev/null | cut -d= -f2- | tr -d '"'
    fi
}
EOF
}

# Main command handler
case "${1:-help}" in
    start)
        start_key_guardian
        ;;
    stop)
        stop_key_guardian
        ;;
    restart)
        stop_key_guardian
        sleep 1
        start_key_guardian
        ;;
    status)
        if [ -S "$KEY_GUARDIAN_SOCKET" ]; then
            "$KEY_GUARDIAN_BIN" status
        else
            echo "Key guardian not running"
        fi
        ;;
    env)
        load_env_from_guardian
        ;;
    get)
        get_key "$2"
        ;;
    shell-integration)
        setup_shell_integration
        ;;
    test)
        echo "Testing key guardian..."
        if [ -S "$KEY_GUARDIAN_SOCKET" ]; then
            echo "Socket: ✓ Connected"
            echo ""
            "$KEY_GUARDIAN_BIN" status
            echo ""
            echo "Sample keys:"
            for key in GITHUB_TOKEN OPENAI_API_KEY GOOGLE_AI_API_KEY; do
                value=$("$KEY_GUARDIAN_BIN" get "$key" 2>/dev/null)
                if [ -n "$value" ]; then
                    echo "  $key: ${value:0:10}..."
                fi
            done
        else
            echo "Socket: ✗ Not found"
            echo "Run: $0 start"
        fi
        ;;
    *)
        echo "Key Guardian Helper"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start             Start key guardian daemon"
        echo "  stop              Stop key guardian daemon"
        echo "  restart           Restart key guardian"
        echo "  status            Check daemon status"
        echo "  env               Get all environment variables"
        echo "  get KEY           Get specific key value"
        echo "  shell-integration Show shell integration code"
        echo "  test              Test key guardian connection"
        echo ""
        echo "Environment:"
        echo "  KEY_GUARDIAN_PROVIDER  Set to 'doppler' or 'file' (default: auto-detect)"
        ;;
esac