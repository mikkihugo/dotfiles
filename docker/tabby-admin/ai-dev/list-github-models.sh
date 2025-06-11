#!/bin/bash
#
# List available GitHub Models
# Purpose: Show all models available through GitHub's Azure endpoint
# Version: 1.0.0

echo "🔍 Fetching available GitHub Models..."
echo ""

# GitHub Models endpoint (no auth required for listing)
MODELS_ENDPOINT="https://models.inference.ai.azure.com/v1/models"

# Fetch models list
echo "GitHub Models (Azure-hosted):"
echo "============================"
curl -s "$MODELS_ENDPOINT" | jq -r '.data[] | "• \(.id) - \(.owned_by)"' 2>/dev/null || {
    # Fallback if jq not available
    curl -s "$MODELS_ENDPOINT" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sed 's/^/• /'
}

echo ""
echo "To use these models:"
echo "1. Set your GitHub token: export GITHUB_TOKEN=your_token"
echo "2. Use with aichat: aichat -m github:model-name"
echo "3. Use with aider: aider --model github/model-name"
echo ""

# Check if we have a token to test access
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "✅ GitHub token found - testing access..."
    
    # Test with a simple completion
    response=$(curl -s -X POST "$MODELS_ENDPOINT/../chat/completions" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "Say OK"}],
            "max_tokens": 10
        }')
    
    if echo "$response" | grep -q "OK"; then
        echo "✅ Token valid - you can use all models above"
    else
        echo "⚠️  Token might not have access to models"
    fi
else
    echo "ℹ️  No GITHUB_TOKEN set - you can still see the list but can't use models"
fi

# Also show GitHub Copilot models if available
echo ""
echo "GitHub Copilot Chat Models:"
echo "=========================="
echo "• copilot:gpt-4"
echo "• copilot:gpt-3.5-turbo"
echo ""
echo "Note: Copilot models require GitHub Copilot subscription"