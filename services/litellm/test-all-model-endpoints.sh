#!/bin/bash
# Test all model endpoints to verify they load correctly

echo "🔍 Testing All Model Endpoints"
echo "=============================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
PASS=0
FAIL=0
SKIP=0

# Test function
test_endpoint() {
    local name=$1
    local url=$2
    local headers=$3
    local expected=$4
    
    echo -n "Testing $name... "
    
    if [[ "$headers" == "none" ]]; then
        response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null)
    else
        response=$(curl -s -w "\n%{http_code}" -H "$headers" "$url" 2>/dev/null)
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" ]]; then
        # Check if response contains expected content
        if echo "$body" | grep -q "$expected" 2>/dev/null; then
            echo -e "${GREEN}✓ PASS${NC} (HTTP $http_code)"
            ((PASS++))
            return 0
        else
            echo -e "${YELLOW}⚠ PARTIAL${NC} (HTTP $http_code but unexpected response)"
            ((FAIL++))
            return 1
        fi
    elif [[ "$http_code" == "401" ]] || [[ "$http_code" == "403" ]]; then
        echo -e "${YELLOW}⚠ AUTH REQUIRED${NC} (HTTP $http_code)"
        ((SKIP++))
        return 2
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
        return 1
    fi
}

echo "1. GitHub Models (Azure Endpoint)"
echo "---------------------------------"
test_endpoint "Model List (No Auth)" \
    "https://models.inference.ai.azure.com/models" \
    "none" \
    "gpt-4"

if [ -n "$GITHUB_TOKEN" ]; then
    test_endpoint "Model List (With Token)" \
        "https://models.inference.ai.azure.com/models" \
        "Authorization: Bearer $GITHUB_TOKEN" \
        "gpt-4"
    
    # Test actual model call
    echo -n "Testing GPT-4o Mini inference... "
    inference_response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://models.inference.ai.azure.com/chat/completions" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "Say hello"}],
            "max_tokens": 10
        }' 2>/dev/null)
    
    http_code=$(echo "$inference_response" | tail -n1)
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC} - No GITHUB_TOKEN set"
    ((SKIP++))
fi

echo ""
echo "2. GitHub Copilot"
echo "-----------------"
if [ -n "$COPILOT_TOKEN" ]; then
    test_endpoint "Model List" \
        "https://api.githubcopilot.com/v1/models" \
        "Authorization: Bearer $COPILOT_TOKEN" \
        "model"
    
    # Test actual model call
    echo -n "Testing Copilot inference... "
    copilot_response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://api.githubcopilot.com/v1/chat/completions" \
        -H "Authorization: Bearer $COPILOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "gpt-4",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 10
        }' 2>/dev/null)
    
    http_code=$(echo "$copilot_response" | tail -n1)
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC} - No COPILOT_TOKEN set"
    ((SKIP++))
fi

echo ""
echo "3. OpenRouter"
echo "-------------"
if [ -n "$OPENROUTER_API_KEY" ]; then
    test_endpoint "Model List" \
        "https://openrouter.ai/api/v1/models" \
        "Authorization: Bearer $OPENROUTER_API_KEY" \
        ":free"
    
    # Count free models
    echo -n "Counting free models... "
    free_count=$(curl -s "https://openrouter.ai/api/v1/models" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" | \
        jq -r '.data[] | select(.id | contains(":free")) | .id' | wc -l)
    echo -e "${GREEN}Found $free_count free models${NC}"
    
    # Test a free model
    echo -n "Testing free model inference... "
    or_response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "mistralai/mistral-7b-instruct:free",
            "messages": [{"role": "user", "content": "Hi"}],
            "max_tokens": 10
        }' 2>/dev/null)
    
    http_code=$(echo "$or_response" | tail -n1)
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC} - No OPENROUTER_API_KEY set"
    ((SKIP++))
fi

echo ""
echo "4. Google AI"
echo "------------"
if [ -n "$GOOGLE_API_KEY" ] || [ -n "$GOOGLE_AI_API_KEY" ]; then
    GKEY="${GOOGLE_API_KEY:-$GOOGLE_AI_API_KEY}"
    
    test_endpoint "Model List" \
        "https://generativelanguage.googleapis.com/v1beta/models" \
        "x-goog-api-key: $GKEY" \
        "gemini"
    
    # Test Gemini inference
    echo -n "Testing Gemini inference... "
    gemini_response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent" \
        -H "x-goog-api-key: $GKEY" \
        -H "Content-Type: application/json" \
        -d '{
            "contents": [{
                "parts": [{"text": "Hello"}]
            }]
        }' 2>/dev/null)
    
    http_code=$(echo "$gemini_response" | tail -n1)
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC} - No GOOGLE_API_KEY set"
    ((SKIP++))
fi

echo ""
echo "5. Groq"
echo "-------"
if [ -n "$GROQ_API_KEY" ]; then
    test_endpoint "Model List" \
        "https://api.groq.com/openai/v1/models" \
        "Authorization: Bearer $GROQ_API_KEY" \
        "model"
    
    # Test Groq inference
    echo -n "Testing Mixtral inference... "
    groq_response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "mixtral-8x7b-32768",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 10
        }' 2>/dev/null)
    
    http_code=$(echo "$groq_response" | tail -n1)
    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (HTTP $http_code)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ SKIPPED${NC} - No GROQ_API_KEY set"
    ((SKIP++))
fi

echo ""
echo "6. Local llama.cpp"
echo "------------------"
# Check if llama-server is running
echo -n "Checking llama.cpp server... "
llama_response=$(curl -s -w "\n%{http_code}" "http://localhost:8081/health" 2>/dev/null)
http_code=$(echo "$llama_response" | tail -n1)

if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}✓ Running${NC}"
    ((PASS++))
    
    # Test model list
    echo -n "Testing model list... "
    models_response=$(curl -s "http://localhost:8081/v1/models" 2>/dev/null)
    if echo "$models_response" | grep -q "model"; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⚠ NOT RUNNING${NC}"
    ((SKIP++))
fi

echo ""
echo "=============================="
echo "Test Summary"
echo "=============================="
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${RED}Failed:${NC} $FAIL"
echo -e "${YELLOW}Skipped:${NC} $SKIP"
echo ""

# Overall result
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ All configured endpoints are working!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some endpoints failed. Check configuration.${NC}"
    exit 1
fi