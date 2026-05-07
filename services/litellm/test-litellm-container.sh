#!/bin/bash
# Test LiteLLM container with all providers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🐳 Testing LiteLLM Container Setup"
echo "================================="
echo ""

# Set test environment variables if not already set
export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-test-master-key}"
export DATABASE_URL="${DATABASE_URL:-sqlite:////app/litellm.db}"

# Test the litellm startup script directly
echo "1. Testing litellm-startup.sh script..."
echo "---------------------------------------"

# Create a temporary config directory
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/config"
cp "$SCRIPT_DIR/litellm-startup.sh" "$TEMP_DIR/"

# Create base config
cat > "$TEMP_DIR/config/litellm_config.yaml" << 'EOF'
model_list:
  - model_name: test/base
    litellm_params:
      model: gpt-3.5-turbo
      api_key: test

litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_ttl: 3600
  enable_preview_features: true
EOF

# Run the startup script to generate dynamic config
echo "Generating dynamic config..."
cd "$TEMP_DIR"
LITELLM_CONFIG_DIR="$TEMP_DIR/config" LITELLM_GENERATE_ONLY=1 bash litellm-startup.sh 2>&1 | head -50

echo ""
echo "2. Checking generated config..."
echo "-------------------------------"
if [ -f "$TEMP_DIR/config/dynamic-config.yaml" ]; then
    echo "✅ Dynamic config created"
    echo ""
    echo "Model counts by provider:"
    count_models() {
        local label="$1"
        local pattern="$2"
        local count
        count=$(grep -c "$pattern" "$TEMP_DIR/config/dynamic-config.yaml" || true)
        echo "  $label: $count"
    }
    count_models "Google AI models" "model_name: google/"
    count_models "OpenRouter models" "model_name: openrouter/"
    count_models "GitHub models" "model_name: github/"
    count_models "Copilot models" "model_name: copilot/"
    count_models "Local models" "model_name: local/"
else
    echo "❌ Dynamic config not created"
fi

echo ""
echo "3. Testing Docker build..."
echo "-------------------------"
cd "$SCRIPT_DIR"

# Check if Dockerfile.litellm exists
if [ -f "Dockerfile.litellm" ]; then
    echo "✅ Dockerfile.litellm exists"
    
    # Test build (dry run)
    echo ""
    echo "Dockerfile summary:"
    grep -E "^FROM|^RUN pip|^EXPOSE|^CMD" Dockerfile.litellm | head -10
else
    echo "❌ Dockerfile.litellm not found"
fi

echo ""
echo "4. Environment variables check..."
echo "---------------------------------"
echo "Required variables for full functionality:"
echo ""

check_env() {
    local name="$1"
    if [ -n "${!name:-}" ]; then
        echo "✅ $1 is set"
    else
        echo "❌ $1 is not set"
    fi
}

check_env "OPENROUTER_API_KEY"
check_env "GOOGLE_API_KEY"
check_env "GOOGLE_AI_API_KEY"
check_env "GITHUB_TOKEN"
check_env "COPILOT_TOKEN"
check_env "GROQ_API_KEY"

echo ""
echo "5. Model availability summary..."
echo "--------------------------------"

# OpenRouter free models
if [ -n "$OPENROUTER_API_KEY" ]; then
    echo -n "OpenRouter free models: "
    curl -s https://openrouter.ai/api/v1/models \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" | \
        jq -r '[.data[] | select(.id | contains(":free"))] | length' 2>/dev/null || echo "Failed"
fi

# Google models
if [ -n "$GOOGLE_API_KEY" ] || [ -n "$GOOGLE_AI_API_KEY" ]; then
    GKEY="${GOOGLE_API_KEY:-$GOOGLE_AI_API_KEY}"
    echo -n "Google AI models: "
    curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
        -H "x-goog-api-key: $GKEY" | \
        jq -r '.models | length' 2>/dev/null || echo "Failed"
fi

# GitHub models (no auth needed for listing)
echo -n "GitHub Models: "
curl -s https://models.inference.ai.azure.com/models | \
    jq -r '.data | length' 2>/dev/null || echo "Failed"

echo ""
echo "================================="
echo "Setup recommendations:"
echo ""

# Provide setup guidance
if [ -z "$OPENROUTER_API_KEY" ] && [ -z "$GOOGLE_API_KEY" ] && [ -z "$GROQ_API_KEY" ]; then
    echo "⚠️  No AI provider API keys found!"
    echo "   At minimum, set one of:"
    echo "   - OPENROUTER_API_KEY (for 60+ free models)"
    echo "   - GOOGLE_API_KEY (for Gemini models)"
    echo "   - GROQ_API_KEY (for fast inference)"
fi

echo ""
echo "To run the LiteLLM container:"
echo "  cd /home/mhugo/.dotfiles/services && docker compose up litellm"

# Cleanup
rm -rf "$TEMP_DIR"
