#!/usr/bin/env bash

# Test script for serverless relay endpoints
# Tests all three serverless implementations

set -euo pipefail

echo "🧪 Testing Serverless Secret Sync Relays..."
echo ""

# Configuration - update these with your deployed URLs
VERCEL_URL="${VERCEL_URL:-}"
NETLIFY_URL="${NETLIFY_URL:-}"
CLOUDFLARE_URL="${CLOUDFLARE_URL:-}"

# Test data
ROOM_ID="test-$(date +%s)"
DEVICE1="laptop-$(whoami)"
DEVICE2="phone-$(whoami)"
TEST_PAYLOAD="encrypted-test-data-$(date +%s)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_endpoint() {
    local name="$1"
    local base_url="$2"

    if [[ -z "$base_url" ]]; then
        echo -e "${YELLOW}⏭️  Skipping $name (URL not set)${NC}"
        return 0
    fi

    echo -e "${BLUE}🧪 Testing $name: $base_url${NC}"

    # Test 1: Health check
    echo -n "   Health check... "
    if curl -s -f "$base_url/health" > /dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
        return 1
    fi

    # Test 2: Send sync message
    echo -n "   Send message... "
    local send_response
    send_response=$(curl -s -X POST "$base_url/sync/$ROOM_ID" \
        -H "Content-Type: application/json" \
        -d "{
            \"from_device\": \"$DEVICE1\",
            \"encrypted_payload\": \"$TEST_PAYLOAD\",
            \"device_name\": \"Test Laptop\"
        }")

    if echo "$send_response" | grep -q '"success":true'; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
        echo "   Response: $send_response"
        return 1
    fi

    # Test 3: Retrieve messages
    echo -n "   Retrieve messages... "
    local receive_response
    receive_response=$(curl -s "$base_url/sync/$ROOM_ID?device_id=$DEVICE2")

    if echo "$receive_response" | grep -q "$TEST_PAYLOAD"; then
        echo -e "${GREEN}✅${NC}"
        local count=$(echo "$receive_response" | grep -o '"count":[0-9]*' | cut -d: -f2)
        echo "   📬 Received $count message(s)"
    else
        echo -e "${RED}❌${NC}"
        echo "   Response: $receive_response"
        return 1
    fi

    # Test 4: Messages should be consumed (empty on second fetch)
    echo -n "   Message consumption... "
    local second_fetch
    second_fetch=$(curl -s "$base_url/sync/$ROOM_ID?device_id=$DEVICE2")

    if echo "$second_fetch" | grep -q '"count":0'; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${YELLOW}⚠️  Messages not consumed (Netlify expected)${NC}"
    fi

    echo ""
}

# Check if any URLs are provided
if [[ -z "$VERCEL_URL" && -z "$NETLIFY_URL" && -z "$CLOUDFLARE_URL" ]]; then
    echo "❌ No relay URLs configured!"
    echo ""
    echo "Set environment variables with your deployed URLs:"
    echo "   export VERCEL_URL='https://your-app.vercel.app'"
    echo "   export NETLIFY_URL='https://your-app.netlify.app'"
    echo "   export CLOUDFLARE_URL='https://your-worker.your-subdomain.workers.dev'"
    echo ""
    echo "Then run: $0"
    exit 1
fi

# Test all configured endpoints
failed_tests=0

if [[ -n "$VERCEL_URL" ]]; then
    if ! test_endpoint "Vercel" "$VERCEL_URL"; then
        ((failed_tests++))
    fi
fi

if [[ -n "$NETLIFY_URL" ]]; then
    if ! test_endpoint "Netlify" "$NETLIFY_URL"; then
        ((failed_tests++))
    fi
fi

if [[ -n "$CLOUDFLARE_URL" ]]; then
    if ! test_endpoint "Cloudflare Workers" "$CLOUDFLARE_URL"; then
        ((failed_tests++))
    fi
fi

# Summary
echo "🎯 Test Summary:"
if [[ $failed_tests -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo "🚀 Your serverless relays are ready for secret sync!"
    echo ""
    echo "💡 Next steps:"
    echo "   1. Update your secret TUI configuration with the relay URL"
    echo "   2. Set a shared room ID between your devices"
    echo "   3. Start syncing secrets securely!"
else
    echo -e "${RED}❌ $failed_tests test(s) failed${NC}"
    echo ""
    echo "🔍 Check the deployment logs and endpoint URLs"
    exit 1
fi