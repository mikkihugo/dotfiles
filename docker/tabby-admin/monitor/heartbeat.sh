#!/bin/bash
#
# Heartbeat monitor for admin stack
# Alerts when services are down

set -euo pipefail

# Services to check
SERVICES=(
    "warpgate:8888:/health"
    "tabby-web:9090:/api/health"
    "gitea:3000:/api/v1/version"
    "drone:80:/healthz"
)

# Heartbeat endpoint (Cloudflare Worker)
HEARTBEAT_URL="${HEARTBEAT_URL:-https://admin.hugo.dk/heartbeat}"
ALERT_EMAIL="${ALERT_EMAIL:-mikki@hugo.dk}"

# Check each service
all_healthy=true
failed_services=()

for service in "${SERVICES[@]}"; do
    IFS=':' read -r name port path <<< "$service"
    
    if curl -sf "http://${name}:${port}${path}" > /dev/null; then
        echo "✓ ${name} is healthy"
    else
        echo "✗ ${name} is DOWN"
        all_healthy=false
        failed_services+=("${name}")
    fi
done

# Send heartbeat
if $all_healthy; then
    curl -X POST "${HEARTBEAT_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "status": "healthy",
            "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
            "services": "all"
        }'
else
    # Alert on failure
    curl -X POST "${HEARTBEAT_URL}" \
        -H "Content-Type: application/json" \
        -d '{
            "status": "unhealthy",
            "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",
            "failed": ["'"${failed_services[*]}"'"],
            "alert": "'"${ALERT_EMAIL}"'"
        }'
fi