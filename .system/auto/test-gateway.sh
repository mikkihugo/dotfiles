#!/bin/bash

# Test Tabby Gateway connectivity

GATEWAY_URL="ws://51.38.127.98:9000"
GATEWAY_HOST="51.38.127.98"
GATEWAY_PORT="9000"

echo "🔍 Testing Tabby Gateway: $GATEWAY_URL"
echo ""

# 1. Check if running locally
echo "1️⃣ Local container check:"
if docker ps | grep -q tabby-gateway; then
    echo "   ✅ Container is running"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep tabby
else
    echo "   ❌ Container not found"
fi

echo ""
echo "2️⃣ Port binding check:"
if ss -tlnp 2>/dev/null | grep -q ":$GATEWAY_PORT"; then
    echo "   ✅ Port $GATEWAY_PORT is listening"
    ss -tlnp 2>/dev/null | grep ":$GATEWAY_PORT" | sed 's/^/   /'
else
    echo "   ❌ Port $GATEWAY_PORT not listening"
fi

echo ""
echo "3️⃣ HTTP connectivity test:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$GATEWAY_HOST:$GATEWAY_PORT" 2>/dev/null)
if [ "$HTTP_CODE" = "426" ]; then
    echo "   ✅ Gateway responds correctly (426 = WebSocket upgrade required)"
elif [ -n "$HTTP_CODE" ]; then
    echo "   ⚠️  Unexpected response: HTTP $HTTP_CODE"
else
    echo "   ❌ No response - check firewall"
fi

echo ""
echo "4️⃣ WebSocket test with curl:"
if command -v websocat &>/dev/null; then
    echo "   Testing with websocat..."
    timeout 2 websocat -t "$GATEWAY_URL" 2>&1 | head -5
else
    # Try basic WebSocket handshake with curl
    echo "   Testing WebSocket upgrade..."
    curl -i -N \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Version: 13" \
        -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" \
        "http://$GATEWAY_HOST:$GATEWAY_PORT" 2>&1 | head -20
fi

echo ""
echo "5️⃣ Python connectivity test:"
if command -v python3 &>/dev/null; then
    python3 -c "
import socket
import sys
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    result = s.connect_ex(('$GATEWAY_HOST', $GATEWAY_PORT))
    if result == 0:
        print('   ✅ Python socket connection successful')
    else:
        print(f'   ❌ Python socket connection failed (error {result})')
    s.close()
except Exception as e:
    print(f'   ❌ Python test error: {e}')
"
fi

echo ""
echo "6️⃣ External test command (run from your local machine):"
echo "   curl http://$GATEWAY_HOST:$GATEWAY_PORT"
echo "   Expected: HTTP 426 Upgrade Required"

echo ""
echo "7️⃣ Firewall status:"
if sudo -n iptables -L -n 2>/dev/null | grep -q "$GATEWAY_PORT"; then
    echo "   ℹ️  iptables rules found for port $GATEWAY_PORT"
else
    echo "   ⚠️  No iptables rules or need sudo to check"
    echo "   To open port: sudo firewall-cmd --add-port=$GATEWAY_PORT/tcp --permanent && sudo firewall-cmd --reload"
fi