#!/bin/bash
# Test GitHub Models endpoints

echo "🔍 Testing GitHub Models (Azure) endpoint..."
echo "================================"

# Test without auth (should work according to user)
echo "1. Testing without auth:"
curl -s https://models.inference.ai.azure.com/models | jq '.' || echo "Failed to get models"

echo -e "\n================================"
echo "2. Testing with GitHub token:"
if [ -n "$GITHUB_TOKEN" ]; then
    curl -s https://models.inference.ai.azure.com/models \
        -H "Authorization: Bearer $GITHUB_TOKEN" | jq '.' || echo "Failed with token"
else
    echo "No GITHUB_TOKEN set"
fi

echo -e "\n================================"
echo "3. Testing GitHub Copilot endpoint:"
if [ -n "$COPILOT_TOKEN" ]; then
    curl -s https://api.githubcopilot.com/v1/models \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Accept: application/json" | jq '.' || echo "Failed to get Copilot models"
else
    echo "No COPILOT_TOKEN set"
fi