#!/bin/bash
# Mosh connection quality monitor

echo "🌐 Mosh Connection Quality Report"
echo "================================="

if [[ -n "$MOSH_CONNECTION_STRING" ]]; then
    echo "✅ Mosh session active"
    echo "📡 Connection: $MOSH_CONNECTION_STRING"
else
    echo "❌ Not in a mosh session"
    exit 1
fi

echo ""
echo "📊 Network Statistics:"
echo "Current time: $(date)"
echo "Uptime: $(uptime -p)"

if command -v ss >/dev/null; then
    MOSH_CONNS=$(ss -u | grep -c mosh || echo "0")
    echo "🔗 Active mosh UDP connections: $MOSH_CONNS"
fi

echo ""
echo "💡 Tips for better mosh experience:"
echo "  - Use tmux for scrollback: tmux"
echo "  - Check latency: ping -c 3 \$HOST"
echo "  - View this guide: cat ~/.mosh-tips.md"