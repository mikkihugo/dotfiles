#!/bin/bash
#
# Quick Start Nexus AI Stack
# Purpose: Fast deployment with existing tokens
# Version: 1.0.0

set -euo pipefail

# Load tokens
source ~/.dotfiles/.env_tokens

echo "🚀 Quick Starting Nexus AI Stack"
echo ""

# Create simple docker-compose for immediate use
cat > docker-compose.simple.yml << 'EOF'
version: '3.8'

services:
  # Simple AI environment with pre-built images
  ai:
    image: python:3.11-slim
    container_name: nexus-ai-simple
    restart: unless-stopped
    ports:
      - "10080:8080"  # Code server
      - "10888:8888"  # Jupyter
    volumes:
      - ~/code:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
      - ~/.ssh:/root/.ssh:ro
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - GOOGLE_AI_API_KEY=${GOOGLE_AI_API_KEY}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
      - CF_API_TOKEN=${CF_API_TOKEN}
    working_dir: /workspace
    command: >
      bash -c "
        apt-get update && apt-get install -y curl git nodejs npm &&
        curl https://mise.run | sh &&
        ~/.local/bin/mise use -g python@3.11 &&
        ~/.local/bin/mise use -g node@20 &&
        pip install aider-chat jupyter openai anthropic &&
        npm install -g @githubnext/github-copilot-cli &&
        curl -fsSL https://code-server.dev/install.sh | sh &&
        nohup code-server --bind-addr 0.0.0.0:8080 --auth none /workspace &
        nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root &
        echo 'AI tools ready!' &&
        echo 'VS Code: http://localhost:10080' &&
        echo 'Jupyter: http://localhost:10888' &&
        tail -f /dev/null
      "

  # Dev Vault  
  vault:
    image: hashicorp/vault:latest
    container_name: nexus-vault-simple
    restart: unless-stopped
    ports:
      - "10200:8200"
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=nexus-dev-token
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    command: server -dev

volumes:
  code-workspace:
EOF

echo "Starting services..."
docker compose -f docker-compose.simple.yml up -d

echo ""
echo "✅ Quick start complete!"
echo ""
echo "Services:"
echo "  • VS Code:  http://localhost:10080"
echo "  • Jupyter:  http://localhost:10888" 
echo "  • Vault:    http://localhost:10200"
echo ""
echo "To use AI tools, connect to the container:"
echo "  docker exec -it nexus-ai-simple bash"
echo ""
echo "Available FREE AI models:"
echo "  • GitHub Models (best): aider --model gpt-4o"
echo "  • Google Gemini: aider --model gemini-pro"
echo "  • OpenRouter free: aider --model openrouter/meta-llama/llama-3.1-70b-instruct:free"
echo "  • OpenRouter free: aider --model openrouter/qwen/qwen-2.5-72b-instruct:free"
echo ""
echo "Set up aichat config for free models:"
echo "  docker exec -it nexus-ai-simple bash"
echo "  aichat --list-models  # See all available models"