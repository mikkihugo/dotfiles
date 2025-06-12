#!/bin/bash
#
# Start Nexus with all services
# Purpose: Complete deployment with Cloudflare access
# Version: 1.0.0

set -euo pipefail

source ~/.dotfiles/.env_tokens

echo "🚀 Starting Nexus AI Stack"
echo ""

# Start the AI development environment
echo "Starting AI development container..."

# Create the working environment with mise
docker run -d \
    --name nexus-ai-live \
    -v ~/code:/workspace \
    -v ~/.gitconfig:/root/.gitconfig:ro \
    -v ~/.ssh:/root/.ssh:ro \
    -e GITHUB_TOKEN="$(gh auth token)" \
    -e GOOGLE_AI_API_KEY="$GOOGLE_AI_API_KEY" \
    -e OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
    ubuntu:22.04 \
    bash -c "
        # Install mise
        curl https://mise.run | sh
        eval \"\$(~/.local/bin/mise activate bash)\"
        
        # Install tools via mise
        ~/.local/bin/mise use -g python@3.11
        ~/.local/bin/mise use -g node@20
        ~/.local/bin/mise use -g github-cli@latest
        
        # Install AI tools
        pip install aider-chat jupyter openai anthropic
        curl -fsSL https://code-server.dev/install.sh | sh
        
        # Start services
        nohup code-server --bind-addr 0.0.0.0:8080 --auth none /workspace &
        nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root &
        
        echo 'Nexus AI Environment Ready!'
        tail -f /dev/null
    "

echo "AI environment starting..."

# Start Vault
echo "Starting Vault..."
docker run -d \
    --name nexus-vault-live \
    -e VAULT_DEV_ROOT_TOKEN_ID=nexus-root-token \
    -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
    hashicorp/vault:latest server -dev

echo "Vault starting..."

# Wait for services to be ready
echo "Waiting for services..."
sleep 10

# Get container IPs
AI_IP=$(docker inspect nexus-ai-live --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
VAULT_IP=$(docker inspect nexus-vault-live --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')

echo ""
echo "Container IPs:"
echo "AI Environment: $AI_IP:8080 (VS Code), $AI_IP:8888 (Jupyter)"
echo "Vault: $VAULT_IP:8200"
echo ""

# Create cloudflared tunnel config
cat > /tmp/cloudflared-config.yml << EOF
tunnel: nexus-manual
credentials-file: /tmp/credentials.json

ingress:
  - hostname: code.nexus.hugo.dk
    service: http://$AI_IP:8080
  - hostname: jupyter.nexus.hugo.dk
    service: http://$AI_IP:8888
  - hostname: vault.nexus.hugo.dk
    service: http://$VAULT_IP:8200
  - service: http_status:404
EOF

echo "Cloudflared config created at /tmp/cloudflared-config.yml"
echo ""
echo "To create the tunnel manually:"
echo "1. Go to https://dash.cloudflare.com/"
echo "2. Go to Zero Trust > Networks > Tunnels"
echo "3. Create a tunnel named 'nexus-manual'"
echo "4. Copy the credentials JSON to /tmp/credentials.json"
echo "5. Run: ~/.local/bin/cloudflared tunnel --config /tmp/cloudflared-config.yml run nexus-manual"
echo ""
echo "Your services will then be available at:"
echo "• https://code.nexus.hugo.dk"
echo "• https://jupyter.nexus.hugo.dk"
echo "• https://vault.nexus.hugo.dk"