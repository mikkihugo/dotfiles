#!/bin/bash
# Test Google AI models specifically

echo "🔍 Testing Google AI Models"
echo "=========================="
echo ""

GKEY="${GOOGLE_API_KEY:-$GOOGLE_AI_API_KEY}"

if [ -z "$GKEY" ]; then
    echo "❌ No GOOGLE_API_KEY or GOOGLE_AI_API_KEY set"
    exit 1
fi

echo "1. Listing available models:"
echo "----------------------------"
response=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
    -H "x-goog-api-key: $GKEY")

echo "$response" | jq -r '.models[] | "\(.name) - \(.displayName)"' 2>/dev/null || echo "$response"

echo ""
echo "2. Testing different Gemini models:"
echo "-----------------------------------"

# Test different model endpoints
models=("gemini-pro" "gemini-1.5-flash" "gemini-1.5-pro" "gemini-pro-vision")

for model in "${models[@]}"; do
    echo -n "Testing $model... "
    
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" \
        -H "x-goog-api-key: $GKEY" \
        -H "Content-Type: application/json" \
        -d '{
            "contents": [{
                "parts": [{"text": "Say hi"}]
            }],
            "generationConfig": {
                "maxOutputTokens": 10
            }
        }' 2>/dev/null)
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        echo "✅ SUCCESS"
        # Extract the response text
        text=$(echo "$body" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null)
        echo "   Response: $text"
    else
        echo "❌ FAILED (HTTP $http_code)"
        # Show error message if available
        error=$(echo "$body" | jq -r '.error.message' 2>/dev/null)
        if [ "$error" != "null" ] && [ -n "$error" ]; then
            echo "   Error: $error"
        fi
    fi
done

echo ""
echo "3. Raw model list response:"
echo "---------------------------"
curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
    -H "x-goog-api-key: $GKEY" | jq '.'