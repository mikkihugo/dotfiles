#!/bin/bash
# Mise plugin for AI tools - automatically configures AI API keys from vault

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/vault-client/vault-client.sh"

mise_vault_ai_setup() {
    echo "🤖 Loading AI API keys from vault..."
    
    # OpenAI
    local openai_key=$(vault_get "openai_api_key")
    if [ -n "$openai_key" ]; then
        export OPENAI_API_KEY="$openai_key"
        echo "  ✓ OpenAI configured"
    fi
    
    # Anthropic Claude
    local anthropic_key=$(vault_get "anthropic_api_key")
    if [ -n "$anthropic_key" ]; then
        export ANTHROPIC_API_KEY="$anthropic_key"
        export CLAUDE_API_KEY="$anthropic_key"
        echo "  ✓ Anthropic/Claude configured"
    fi
    
    # Google AI
    local google_key=$(vault_get "google_ai_key")
    if [ -n "$google_key" ]; then
        export GOOGLE_AI_KEY="$google_key"
        export GEMINI_API_KEY="$google_key"
        echo "  ✓ Google AI configured"
    fi
    
    # Hugging Face
    local hf_token=$(vault_get "huggingface_token")
    if [ -n "$hf_token" ]; then
        export HUGGINGFACE_TOKEN="$hf_token"
        export HF_TOKEN="$hf_token"
        echo "  ✓ Hugging Face configured"
    fi
    
    # Replicate
    local replicate_key=$(vault_get "replicate_api_key")
    if [ -n "$replicate_key" ]; then
        export REPLICATE_API_TOKEN="$replicate_key"
        echo "  ✓ Replicate configured"
    fi
    
    # Configure AI tool endpoints
    local litellm_url=$(vault_get "litellm_url")
    if [ -n "$litellm_url" ]; then
        export OPENAI_API_BASE="$litellm_url"
        export ANTHROPIC_API_BASE="$litellm_url"
        echo "  ✓ Using LiteLLM proxy at $litellm_url"
    fi
}

# Install AI tools if not present
mise_vault_ai_install() {
    echo "📦 Installing AI tools..."
    
    # aichat
    if ! command -v aichat &> /dev/null; then
        cargo install aichat
    fi
    
    # llm (Simon Willison's tool)
    if ! command -v llm &> /dev/null; then
        pip install llm
    fi
    
    # openai CLI
    if ! command -v openai &> /dev/null; then
        pip install openai
    fi
}

# Configure aichat with vault settings
mise_vault_ai_config() {
    mkdir -p ~/.config/aichat
    cat > ~/.config/aichat/config.yaml << EOF
model: claude-3-opus-20240229
temperature: 0.7
save_session: true

clients:
  - type: openai
    api_key: \${OPENAI_API_KEY}
    
  - type: claude
    api_key: \${ANTHROPIC_API_KEY}
    
  - type: gemini
    api_key: \${GOOGLE_AI_KEY}
EOF
}

case "${1:-setup}" in
    setup)
        mise_vault_ai_setup
        ;;
    install)
        mise_vault_ai_install
        ;;
    config)
        mise_vault_ai_config
        ;;
    all)
        mise_vault_ai_setup
        mise_vault_ai_install
        mise_vault_ai_config
        ;;
    *)
        echo "Usage: $0 {setup|install|config|all}"
        ;;
esac