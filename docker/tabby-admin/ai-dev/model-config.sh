#!/bin/bash
#
# AI Model Configuration - Free/Low-Cost Options
# Purpose: Configure Aider and aichat to use free models
# Version: 1.0.0

# Setup aichat config with free models
setup_aichat_free_models() {
    mkdir -p ~/.config/aichat
    
    cat > ~/.config/aichat/config.yaml << 'EOF'
# AIChat configuration - Free models only

# Default to GitHub Models (free with GitHub token)
# This gives you GPT-4o access without needing OpenAI API!
model: github:gpt-4o

# Model configurations
models:
  # GitHub Models (Azure-hosted, free with GitHub token)
  - name: github:gpt-4o
    provider: openai
    base_url: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN
    
  - name: github:gpt-4o-mini
    provider: openai
    base_url: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN
    
  - name: github:llama-3.2-90b
    provider: openai
    base_url: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN
    
  - name: github:mistral-large
    provider: openai
    base_url: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN
    
  - name: github:phi-3-medium
    provider: openai
    base_url: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN

  # GitHub Copilot Chat API (different endpoint, different models)
  - name: copilot:gpt-4
    provider: openai
    base_url: https://api.githubcopilot.com
    api_key_env: GITHUB_TOKEN
    headers:
      X-GitHub-Api-Version: "2022-11-28"
      Accept: "application/vnd.github.copilot-chat+json"
      
  - name: copilot:gpt-3.5-turbo
    provider: openai
    base_url: https://api.githubcopilot.com
    api_key_env: GITHUB_TOKEN
    headers:
      X-GitHub-Api-Version: "2022-11-28"
      Accept: "application/vnd.github.copilot-chat+json"
      
  # OpenRouter free models
  - name: openrouter:mythomist
    provider: openrouter
    model: nousresearch/hermes-3-llama-3.1-405b:free
    api_key_env: OPENROUTER_API_KEY
    
  - name: openrouter:llama-3.1-70b
    provider: openrouter
    model: meta-llama/llama-3.1-70b-instruct:free
    api_key_env: OPENROUTER_API_KEY
    
  - name: openrouter:qwen-72b
    provider: openrouter
    model: qwen/qwen-2.5-72b-instruct:free
    api_key_env: OPENROUTER_API_KEY
    
  # Google AI Studio (free tier - 60 requests/minute)
  - name: google:gemini-pro
    provider: openai
    base_url: https://generativelanguage.googleapis.com/v1beta
    model: gemini-pro
    api_key_env: GOOGLE_AI_STUDIO_KEY
    
  - name: google:gemini-1.5-flash
    provider: openai  
    base_url: https://generativelanguage.googleapis.com/v1beta
    model: gemini-1.5-flash-latest
    api_key_env: GOOGLE_AI_STUDIO_KEY
    
  # Google via OpenRouter (if available)
  - name: openrouter:gemini
    provider: openrouter
    model: google/gemini-pro
    api_key_env: OPENROUTER_API_KEY
    
  # Local models via Ollama
  - name: ollama:deepseek-coder
    provider: ollama
    model: deepseek-coder:33b
    base_url: http://localhost:11434
    
  - name: ollama:codellama
    provider: ollama
    model: codellama:70b
    base_url: http://localhost:11434

# RAG settings optimized for CPU and free tier
rag:
  enabled: true
  # Use tiny embedding model for CPU efficiency
  embedding_model: sentence-transformers/all-MiniLM-L6-v2
  embedding_provider: local  # Uses sentence-transformers locally (CPU)
  # Alternative even smaller model: sentence-transformers/all-MiniLM-L12-v2
  chunk_size: 1000  # Smaller chunks for faster processing
  chunk_overlap: 100
  top_k: 3  # Fewer results for speed and token savings
  
  # Use small local model for RAG reranking (optional)
  rerank_model: ms-marco-MiniLM-L-6-v2
  rerank_enabled: false  # Disable if too slow on CPU

# Clients settings
clients:
  - type: github
    api_base: https://models.inference.ai.azure.com
    api_key_env: GITHUB_TOKEN
    
  - type: openrouter
    api_base: https://openrouter.ai/api/v1
    api_key_env: OPENROUTER_API_KEY
    extra_headers:
      HTTP-Referer: https://github.com/mikkihugo/nexus
      X-Title: "Nexus AI Dev"

# Default system prompt for coding
default_role: coder
roles:
  - name: coder
    model: github:gpt-4o
    temperature: 0.3
    prompt: |
      You are an expert programmer with deep knowledge of the codebase via RAG.
      Be concise and focus on code. Minimize explanations unless asked.
      Always include file paths and line numbers when referencing code.
EOF
}

# Setup Aider to use GitHub Models
setup_aider_free() {
    # Create aider config directory
    mkdir -p ~/.aider
    
    # Create model definitions file
    cat > ~/.aider/model-metadata.json << 'EOF'
{
  "models": {
    "github/gpt-4o": {
      "max_tokens": 128000,
      "max_output_tokens": 16384,
      "edit_format": "diff",
      "editor_model": "github/gpt-4o-mini",
      "api_base": "https://models.inference.ai.azure.com/v1"
    },
    "github/gpt-4o-mini": {
      "max_tokens": 128000,
      "max_output_tokens": 16384,
      "edit_format": "diff",
      "api_base": "https://models.inference.ai.azure.com/v1"
    },
    "github/llama-3.2-90b": {
      "max_tokens": 128000,
      "max_output_tokens": 4096,
      "edit_format": "diff",
      "api_base": "https://models.inference.ai.azure.com/v1"
    },
    "openrouter/llama-3.1-70b:free": {
      "max_tokens": 128000,
      "max_output_tokens": 4096,
      "edit_format": "whole",
      "api_base": "https://openrouter.ai/api/v1"
    },
    "openrouter/qwen-72b:free": {
      "max_tokens": 32768,
      "max_output_tokens": 4096,
      "edit_format": "whole",
      "api_base": "https://openrouter.ai/api/v1"
    }
  }
}
EOF

    # Create wrapper for aider with free models
    cat > /usr/local/bin/aider-free << 'EOF'
#!/bin/bash
#
# Aider with free models
#

# Default to GitHub Models
MODEL="${AIDER_MODEL:-github/gpt-4o}"
EDITOR_MODEL="${AIDER_EDITOR_MODEL:-github/gpt-4o-mini}"

# Set API keys based on model
case "$MODEL" in
    github/*)
        export OPENAI_API_KEY="${GITHUB_TOKEN}"
        export OPENAI_API_BASE="https://models.inference.ai.azure.com/v1"
        ;;
    openrouter/*)
        export OPENAI_API_KEY="${OPENROUTER_API_KEY:-free}"
        export OPENAI_API_BASE="https://openrouter.ai/api/v1"
        MODEL="${MODEL#openrouter/}"
        ;;
    ollama/*)
        export OPENAI_API_KEY="ollama"
        export OPENAI_API_BASE="http://localhost:11434/v1"
        MODEL="${MODEL#ollama/}"
        ;;
esac

echo "🚀 Starting Aider with free models"
echo "Main model: $MODEL"
echo "Editor model: $EDITOR_MODEL"
echo ""

# Check for GitHub token
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "⚠️  No GITHUB_TOKEN found. GitHub Models won't work."
    echo "Get a token at: https://github.com/settings/tokens"
    echo ""
fi

# Launch aider
exec aider \
    --model "$MODEL" \
    --editor-model "$EDITOR_MODEL" \
    --architect \
    --cache-prompts \
    --no-auto-commits \
    "$@"
EOF
    chmod +x /usr/local/bin/aider-free
}

# Create model testing script
create_model_tester() {
    cat > /usr/local/bin/test-models << 'EOF'
#!/bin/bash
#
# Test available free models
#

echo "🧪 Testing Free AI Models"
echo ""

# Test GitHub Models (Azure endpoint)
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "Testing GitHub Models (Azure)..."
    echo "Hello, respond with 'OK'" | aichat -m github:gpt-4o-mini && echo "✅ GitHub GPT-4o-mini works"
    echo "Hello, respond with 'OK'" | aichat -m github:llama-3.2-90b && echo "✅ GitHub Llama 3.2 works"
    
    echo ""
    echo "Testing GitHub Copilot Chat API..."
    echo "Hello, respond with 'OK'" | aichat -m copilot:gpt-4 && echo "✅ Copilot GPT-4 works"
else
    echo "❌ No GITHUB_TOKEN - skipping GitHub Models"
fi

# Test OpenRouter free models
echo ""
echo "Testing OpenRouter free models..."
echo "Hello, respond with 'OK'" | aichat -m openrouter:llama-3.1-70b && echo "✅ OpenRouter Llama 3.1 works"
echo "Hello, respond with 'OK'" | aichat -m openrouter:mythomist && echo "✅ OpenRouter Mythomist works"

# Test local Ollama if available
if command -v ollama &>/dev/null; then
    echo ""
    echo "Testing Ollama models..."
    ollama list
fi

echo ""
echo "✨ Model testing complete!"
EOF
    chmod +x /usr/local/bin/test-models
}

# Setup environment variables
setup_env() {
    cat >> ~/.bashrc << 'EOF'

# AI Model Configuration
export GITHUB_MODELS_ENDPOINT="https://models.inference.ai.azure.com"
export OPENROUTER_REFERRER="https://github.com/mikkihugo/nexus"

# Aider defaults
export AIDER_MODEL="github/gpt-4o"
export AIDER_EDITOR_MODEL="github/gpt-4o-mini"
export AIDER_CACHE_PROMPTS="true"
export AIDER_AUTO_COMMITS="false"

# Function to switch models
ai-model() {
    case "$1" in
        github)
            export AIDER_MODEL="github/gpt-4o"
            echo "Switched to GitHub GPT-4o"
            ;;
        llama)
            export AIDER_MODEL="github/llama-3.2-90b"
            echo "Switched to GitHub Llama 3.2"
            ;;
        free)
            export AIDER_MODEL="openrouter/llama-3.1-70b:free"
            echo "Switched to OpenRouter Llama 3.1 (free)"
            ;;
        local)
            export AIDER_MODEL="ollama/deepseek-coder:33b"
            echo "Switched to local Ollama"
            ;;
        *)
            echo "Usage: ai-model {github|llama|free|local}"
            echo "Current: $AIDER_MODEL"
            ;;
    esac
}
EOF
}

# Main setup
main() {
    echo "🎯 Setting up free AI models..."
    
    setup_aichat_free_models
    setup_aider_free
    create_model_tester
    setup_env
    
    echo "✅ Free model setup complete!"
    echo ""
    echo "Available commands:"
    echo "  aider-free    - Aider with free models"
    echo "  aider-rag     - Aider with RAG support"
    echo "  test-models   - Test available models"
    echo "  ai-model      - Switch between models"
    echo ""
    echo "Models available:"
    echo "  • GitHub: gpt-4o, gpt-4o-mini, llama-3.2-90b"
    echo "  • OpenRouter: llama-3.1-70b:free, qwen-72b:free"
    echo "  • Local: ollama models"
}

main "$@"