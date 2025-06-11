#!/bin/bash
#
# Test All Available AI Models
# Purpose: Comprehensive testing of all configured models
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo -e "${PURPLE}🧪 Comprehensive AI Model Testing${NC}"
echo "=================================="
echo ""

# Simple test prompt
TEST_PROMPT="Say 'OK' if you can read this"
TIMEOUT=10

# Test function
test_model() {
    local provider=$1
    local model=$2
    local name=$3
    
    echo -n "Testing $name... "
    
    # Try the model with timeout
    if timeout $TIMEOUT bash -c "echo '$TEST_PROMPT' | aichat -m '$model' 2>/dev/null | grep -q 'OK'"; then
        echo -e "${GREEN}✅ Works${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
}

# Test with curl for direct API testing
test_api_directly() {
    local name=$1
    local url=$2
    local auth_header=$3
    local model=$4
    
    echo -n "Testing $name (direct API)... "
    
    local response=$(curl -s -X POST "$url" \
        -H "$auth_header" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$TEST_PROMPT\"}],
            \"max_tokens\": 50
        }" 2>/dev/null)
    
    if echo "$response" | grep -q "OK"; then
        echo -e "${GREEN}✅ Works${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
}

# Check prerequisites
echo -e "${BLUE}Checking Prerequisites${NC}"
echo "----------------------"

# GitHub Token
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo -e "${GREEN}✓ GitHub Token found${NC}"
    GITHUB_AVAILABLE=true
else
    echo -e "${YELLOW}✗ No GitHub Token${NC}"
    GITHUB_AVAILABLE=false
fi

# Google AI
if [ -n "${GOOGLE_AI_STUDIO_KEY:-}${GOOGLE_GENERATIVE_AI_API_KEY:-}${GOOGLE_AI_API_KEY:-}" ]; then
    echo -e "${GREEN}✓ Google AI key found${NC}"
    GOOGLE_AVAILABLE=true
    # Use whichever key is available
    GOOGLE_KEY="${GOOGLE_AI_STUDIO_KEY:-${GOOGLE_GENERATIVE_AI_API_KEY:-${GOOGLE_AI_API_KEY:-}}}"
else
    echo -e "${YELLOW}✗ No Google AI key${NC}"
    GOOGLE_AVAILABLE=false
fi

# OpenRouter
if [ -n "${OPENROUTER_API_KEY:-}" ] && [ "${OPENROUTER_API_KEY}" != "free" ]; then
    echo -e "${GREEN}✓ OpenRouter API key found${NC}"
    OPENROUTER_AVAILABLE=true
else
    echo -e "${YELLOW}✗ No OpenRouter API key (will try free tier)${NC}"
    OPENROUTER_AVAILABLE=true  # Free tier should work
fi

# Cloudflare
if [ -n "${CF_API_TOKEN:-}" ]; then
    echo -e "${GREEN}✓ Cloudflare API token found${NC}"
else
    echo -e "${YELLOW}✗ No Cloudflare API token${NC}"
fi

echo ""

# Test GitHub Models (Azure endpoint)
if [ "$GITHUB_AVAILABLE" = true ]; then
    echo -e "${BLUE}Testing GitHub Models (Azure)${NC}"
    echo "-----------------------------"
    
    # Direct API test
    test_api_directly "GPT-4o-mini" \
        "https://models.inference.ai.azure.com/chat/completions" \
        "Authorization: Bearer $GITHUB_TOKEN" \
        "gpt-4o-mini"
    
    # Test via aichat
    test_model "github" "github:gpt-4o-mini" "GPT-4o-mini (aichat)"
    test_model "github" "github:gpt-4o" "GPT-4o (aichat)"
    test_model "github" "github:llama-3.2-90b" "Llama 3.2 90B"
    test_model "github" "github:mistral-large" "Mistral Large"
    test_model "github" "github:phi-3-medium" "Phi-3 Medium"
    
    echo ""
fi

# Test GitHub Copilot API
if [ "$GITHUB_AVAILABLE" = true ]; then
    echo -e "${BLUE}Testing GitHub Copilot API${NC}"
    echo "-------------------------"
    
    # Note: Copilot API might require additional setup/subscription
    test_api_directly "Copilot GPT-4" \
        "https://api.githubcopilot.com/chat/completions" \
        "Authorization: Bearer $GITHUB_TOKEN" \
        "gpt-4"
    
    test_model "copilot" "copilot:gpt-4" "Copilot GPT-4 (aichat)"
    test_model "copilot" "copilot:gpt-3.5-turbo" "Copilot GPT-3.5"
    
    echo ""
fi

# Test Google AI
if [ "$GOOGLE_AVAILABLE" = true ]; then
    echo -e "${BLUE}Testing Google AI Studio${NC}"
    echo "-----------------------"
    
    # Direct API test for Gemini
    test_api_directly "Gemini Pro" \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$GOOGLE_KEY" \
        "Content-Type: application/json" \
        "gemini-pro"
    
    # Test via aichat
    test_model "google" "google:gemini-pro" "Gemini Pro (aichat)"
    test_model "google" "google:gemini-1.5-flash" "Gemini 1.5 Flash"
    
    echo ""
fi

# Test OpenRouter Free Models
echo -e "${BLUE}Testing OpenRouter Free Models${NC}"
echo "-----------------------------"

# These should work even without API key
test_model "openrouter" "openrouter:llama-3.1-70b" "Llama 3.1 70B (free)"
test_model "openrouter" "openrouter:mythomist" "Mythomist (free)"
test_model "openrouter" "openrouter:qwen-72b" "Qwen 2.5 72B (free)"

echo ""

# Test Local Models (if Ollama is running)
if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
    echo -e "${BLUE}Testing Local Ollama Models${NC}"
    echo "--------------------------"
    
    # List available models
    echo "Available Ollama models:"
    ollama list
    echo ""
    
    # Test if any models are pulled
    if ollama list | grep -q "codellama"; then
        test_model "ollama" "ollama:codellama" "CodeLlama"
    fi
    
    if ollama list | grep -q "deepseek"; then
        test_model "ollama" "ollama:deepseek-coder" "DeepSeek Coder"
    fi
    
    echo ""
fi

# Summary
echo -e "${PURPLE}Test Summary${NC}"
echo "============"
echo ""

# Show which providers are working
echo "Available providers:"
[ "$GITHUB_AVAILABLE" = true ] && echo -e "${GREEN}✓ GitHub Models${NC}"
[ "$GOOGLE_AVAILABLE" = true ] && echo -e "${GREEN}✓ Google AI${NC}"
echo -e "${GREEN}✓ OpenRouter Free Tier${NC}"

echo ""
echo "To use these models:"
echo "  • With aichat: aichat -m provider:model"
echo "  • With aider: aider --model provider/model"
echo "  • List models: list-github-models.sh"
echo ""

# Recommend best free model based on tests
echo -e "${BLUE}Recommended free models:${NC}"
echo "1. github:gpt-4o - Best overall (requires GitHub token)"
echo "2. github:llama-3.2-90b - Best open model (requires GitHub token)"
echo "3. openrouter:llama-3.1-70b - No API key needed"
echo "4. google:gemini-1.5-flash - Fast and capable (requires Google AI key)"