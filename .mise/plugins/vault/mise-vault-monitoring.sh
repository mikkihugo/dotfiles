#!/bin/bash
# Mise plugin for monitoring and alerting - Datadog, Sentry, PagerDuty, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/vault-client/vault-client.sh"

mise_vault_monitoring_setup() {
    echo "📊 Loading monitoring credentials from vault..."
    
    # Datadog
    local dd_api_key=$(vault_get "datadog_api_key")
    local dd_app_key=$(vault_get "datadog_app_key")
    if [ -n "$dd_api_key" ]; then
        export DD_API_KEY="$dd_api_key"
        export DD_APP_KEY="$dd_app_key"
        export DATADOG_API_KEY="$dd_api_key"
        export DATADOG_APP_KEY="$dd_app_key"
        echo "  ✓ Datadog configured"
    fi
    
    # Sentry
    local sentry_dsn=$(vault_get "sentry_dsn")
    local sentry_auth=$(vault_get "sentry_auth_token")
    if [ -n "$sentry_dsn" ]; then
        export SENTRY_DSN="$sentry_dsn"
        export SENTRY_AUTH_TOKEN="$sentry_auth"
        echo "  ✓ Sentry configured"
    fi
    
    # PagerDuty
    local pd_token=$(vault_get "pagerduty_token")
    local pd_routing=$(vault_get "pagerduty_routing_key")
    if [ -n "$pd_token" ]; then
        export PAGERDUTY_TOKEN="$pd_token"
        export PAGERDUTY_ROUTING_KEY="$pd_routing"
        echo "  ✓ PagerDuty configured"
    fi
    
    # Prometheus/Grafana
    local prom_url=$(vault_get "prometheus_url")
    local grafana_url=$(vault_get "grafana_url")
    local grafana_token=$(vault_get "grafana_api_token")
    if [ -n "$prom_url" ]; then
        export PROMETHEUS_URL="$prom_url"
        export GRAFANA_URL="$grafana_url"
        export GRAFANA_API_TOKEN="$grafana_token"
        echo "  ✓ Prometheus/Grafana configured"
    fi
    
    # Slack webhooks
    local slack_webhook=$(vault_get "slack_webhook_url")
    local slack_token=$(vault_get "slack_bot_token")
    if [ -n "$slack_webhook" ]; then
        export SLACK_WEBHOOK_URL="$slack_webhook"
        export SLACK_BOT_TOKEN="$slack_token"
        echo "  ✓ Slack configured"
    fi
    
    # Discord webhooks
    local discord_webhook=$(vault_get "discord_webhook_url")
    if [ -n "$discord_webhook" ]; then
        export DISCORD_WEBHOOK_URL="$discord_webhook"
        echo "  ✓ Discord configured"
    fi
    
    # Twilio (SMS alerts)
    local twilio_sid=$(vault_get "twilio_account_sid")
    local twilio_auth=$(vault_get "twilio_auth_token")
    local twilio_from=$(vault_get "twilio_phone_number")
    if [ -n "$twilio_sid" ]; then
        export TWILIO_ACCOUNT_SID="$twilio_sid"
        export TWILIO_AUTH_TOKEN="$twilio_auth"
        export TWILIO_PHONE_NUMBER="$twilio_from"
        echo "  ✓ Twilio configured"
    fi
}

# Install monitoring tools
mise_vault_monitoring_install() {
    echo "📦 Installing monitoring tools..."
    
    # Datadog CLI
    if ! command -v dog &> /dev/null; then
        pip install datadog
    fi
    
    # Sentry CLI
    if ! command -v sentry-cli &> /dev/null; then
        curl -sL https://sentry.io/get-cli/ | bash
    fi
    
    # k9s for Kubernetes monitoring
    if ! command -v k9s &> /dev/null; then
        mise use -g k9s@latest
    fi
    
    # htop/btop for system monitoring
    if ! command -v btop &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y btop
    fi
    
    # netdata agent
    if ! command -v netdata &> /dev/null; then
        bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait --dont-start-it
    fi
}

# Configure monitoring alerts
mise_vault_monitoring_alerts() {
    mkdir -p ~/.monitoring
    
    # Create alert script
    cat > ~/.monitoring/send-alert.sh << 'EOF'
#!/bin/bash
# Universal alert sender

LEVEL="${1:-info}"  # info, warning, error, critical
MESSAGE="$2"
TITLE="${3:-Hugo.dk Alert}"

# Slack
if [ -n "$SLACK_WEBHOOK_URL" ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"[$LEVEL] $TITLE: $MESSAGE\"}" \
        "$SLACK_WEBHOOK_URL"
fi

# Discord
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    curl -X POST -H "Content-Type: application/json" \
        -d "{\"content\":\"**[$LEVEL]** $TITLE: $MESSAGE\"}" \
        "$DISCORD_WEBHOOK_URL"
fi

# PagerDuty (for critical only)
if [ "$LEVEL" = "critical" ] && [ -n "$PAGERDUTY_ROUTING_KEY" ]; then
    curl -X POST https://events.pagerduty.com/v2/enqueue \
        -H 'Content-Type: application/json' \
        -d "{
            \"routing_key\": \"$PAGERDUTY_ROUTING_KEY\",
            \"event_action\": \"trigger\",
            \"payload\": {
                \"summary\": \"$TITLE: $MESSAGE\",
                \"severity\": \"error\",
                \"source\": \"hugo.dk\"
            }
        }"
fi

# Twilio SMS (for critical only)
if [ "$LEVEL" = "critical" ] && [ -n "$TWILIO_ACCOUNT_SID" ]; then
    curl -X POST "https://api.twilio.com/2010-04-01/Accounts/$TWILIO_ACCOUNT_SID/Messages.json" \
        --data-urlencode "Body=[$LEVEL] $TITLE: $MESSAGE" \
        --data-urlencode "From=$TWILIO_PHONE_NUMBER" \
        --data-urlencode "To=$EMERGENCY_PHONE" \
        -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN"
fi
EOF
    
    chmod +x ~/.monitoring/send-alert.sh
    
    # Create health check script
    cat > ~/.monitoring/health-check.sh << 'EOF'
#!/bin/bash
# System health checker

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    ~/.monitoring/send-alert.sh critical "Disk space critical: ${DISK_USAGE}% used"
elif [ "$DISK_USAGE" -gt 80 ]; then
    ~/.monitoring/send-alert.sh warning "Disk space warning: ${DISK_USAGE}% used"
fi

# Check memory
MEM_USAGE=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$MEM_USAGE" -gt 90 ]; then
    ~/.monitoring/send-alert.sh critical "Memory usage critical: ${MEM_USAGE}%"
fi

# Check load average
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CORES=$(nproc)
if (( $(echo "$LOAD > $CORES * 2" | bc -l) )); then
    ~/.monitoring/send-alert.sh warning "High load average: $LOAD (${CORES} cores)"
fi

# Check services
for service in docker postgresql nginx; do
    if ! systemctl is-active --quiet $service; then
        ~/.monitoring/send-alert.sh error "Service $service is not running"
    fi
done
EOF
    
    chmod +x ~/.monitoring/health-check.sh
    
    # Setup cron job
    (crontab -l 2>/dev/null; echo "*/5 * * * * ~/.monitoring/health-check.sh") | crontab -
}

# Configure Datadog agent
mise_vault_monitoring_datadog() {
    if [ -n "$DD_API_KEY" ]; then
        # Install Datadog agent
        DD_API_KEY="$DD_API_KEY" DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"
        
        # Configure agent
        sudo sed -i "s/api_key:.*/api_key: $DD_API_KEY/" /etc/datadog-agent/datadog.yaml
        
        # Enable integrations
        sudo systemctl restart datadog-agent
    fi
}

case "${1:-setup}" in
    setup)
        mise_vault_monitoring_setup
        ;;
    install)
        mise_vault_monitoring_install
        ;;
    alerts)
        mise_vault_monitoring_alerts
        ;;
    datadog)
        mise_vault_monitoring_datadog
        ;;
    all)
        mise_vault_monitoring_setup
        mise_vault_monitoring_install
        mise_vault_monitoring_alerts
        ;;
    test)
        # Test alert sending
        ~/.monitoring/send-alert.sh info "Test alert from mise-vault-monitoring" "System Test"
        ;;
    *)
        echo "Usage: $0 {setup|install|alerts|datadog|all|test}"
        ;;
esac