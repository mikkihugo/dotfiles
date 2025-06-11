#!/bin/bash
#
# Nexus AI Stack - Quick Deploy
# Purpose: Build and deploy the AI development environment
# Version: 1.0.0

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Nexus AI Stack Deployment${NC}"
echo ""

# Check prerequisites
check_prereqs() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}❌ Docker not found${NC}"
        exit 1
    fi
    
    # Check GitHub token
    if [ -z "${GITHUB_TOKEN:-}" ]; then
        echo -e "${RED}❌ GITHUB_TOKEN not set${NC}"
        echo "Get a token at: https://github.com/settings/tokens"
        echo "Then: export GITHUB_TOKEN=your_token"
        exit 1
    fi
    
    # Verify token works with GitHub Models
    echo "Testing GitHub token..."
    if curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
        https://models.inference.ai.azure.com/v1/models | grep -q "gpt-4o"; then
        echo -e "${GREEN}✓ GitHub token valid for AI models${NC}"
    else
        echo -e "${YELLOW}⚠ Could not verify GitHub Models access${NC}"
    fi
    
    # Check for optional services
    echo ""
    echo -e "${BLUE}Optional services setup:${NC}"
    
    # Google AI keys - check multiple possible names
    GOOGLE_KEY_FOUND=false
    for key_name in GOOGLE_AI GOOGLE_AI_KEY GOOGLE_API_KEY GOOGLE_AI_STUDIO_KEY GOOGLE_GENERATIVE_AI_API_KEY GEMINI_API_KEY; do
        if [ -n "${!key_name:-}" ]; then
            echo -e "${GREEN}✓ Google AI key found: $key_name${NC}"
            GOOGLE_KEY_FOUND=true
            export GOOGLE_AI_KEY="${!key_name}"
            break
        fi
    done
    
    if [ "$GOOGLE_KEY_FOUND" = false ]; then
        echo -e "${YELLOW}⚠ No Google AI key found${NC}"
        echo "  To enable Google Gemini models, set one of:"
        echo "    export GOOGLE_AI_KEY=your_key"
        echo "    export GOOGLE_AI_STUDIO_KEY=your_key"
        echo "  Get free key at: https://makersuite.google.com/app/apikey"
    fi
    
    # Google login
    if command -v gcloud &>/dev/null && gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        echo -e "${GREEN}✓ Google account authenticated${NC}"
        GOOGLE_ACCOUNT=$(gcloud config get-value account)
        export GOOGLE_ACCOUNT
    else
        echo -e "${YELLOW}⚠ Google account not authenticated${NC}"
        echo "  To enable Google services, run: gcloud auth login"
    fi
    
    # Cloudflare API
    if [ -n "${CF_API_TOKEN:-}" ]; then
        echo -e "${GREEN}✓ Cloudflare API token found${NC}"
    else
        echo -e "${YELLOW}⚠ No Cloudflare API token${NC}"
        echo "  To enable Cloudflare tunnel, set: export CF_API_TOKEN=your_token"
        echo "  Get token at: https://dash.cloudflare.com/profile/api-tokens"
    fi
    
    echo -e "${GREEN}✓ Prerequisites checked${NC}"
}

# Create minimal .env file
create_env() {
    if [ ! -f .env ]; then
        echo -e "${YELLOW}Creating .env file...${NC}"
        cat > .env << EOF
# GitHub token (for AI models and auth)
GITHUB_TOKEN=${GITHUB_TOKEN}

# Optional: OpenRouter for additional free models
OPENROUTER_API_KEY=free

# Optional: Your email for Let's Encrypt
CF_API_EMAIL=mikkihugo@gmail.com

# Admin passwords (change these!)
ADMIN_PASSWORD=nexus123
CODE_SERVER_PASSWORD=nexus123
EOF
        echo -e "${GREEN}✓ .env created${NC}"
    fi
}

# Build the all-in-one container
build_container() {
    echo -e "${YELLOW}Building AI development container...${NC}"
    
    cd ai-dev
    docker build -f Dockerfile.all-in-one -t nexus-ai:latest .
    cd ..
    
    echo -e "${GREEN}✓ Container built${NC}"
}

# Create docker-compose override for quick start
create_quick_compose() {
    cat > docker-compose.quick.yml << 'EOF'
version: '3.8'

services:
  # All-in-one AI Development
  ai:
    image: nexus-ai:latest
    container_name: nexus-ai
    restart: unless-stopped
    ports:
      - "10080:8080"  # VS Code
      - "10888:8888"  # Jupyter
      - "13000:3000"  # AI Chat
    volumes:
      - ~/code:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
      - ~/.ssh:/root/.ssh:ro
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - GITHUB_TOKEN=${GITHUB_TOKEN}
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-free}
      - PASSWORD=${CODE_SERVER_PASSWORD:-nexus123}
      - VAULT_ADDR=http://vault:8200
    command: ["/usr/local/bin/ai", "code"]
    depends_on:
      - vault
    networks:
      - nexus-net

  # Minimal Vault for secrets
  vault:
    image: vault:latest
    container_name: nexus-vault
    restart: unless-stopped
    ports:
      - "10200:8200"
    cap_add:
      - IPC_LOCK
    volumes:
      - vault-data:/vault/file
    environment:
      - VAULT_DEV_ROOT_TOKEN_ID=nexus-root-token
      - VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200
    command: server -dev

volumes:
  vault-data:
EOF
}

# Setup Vault with tokens
setup_vault() {
    echo -e "${YELLOW}Setting up Vault with tokens...${NC}"
    
    # Wait for Vault to be ready
    until curl -s http://localhost:10200/v1/sys/health | grep -q "initialized"; do
        echo "Waiting for Vault..."
        sleep 2
    done
    
    # Enable KV secrets engine
    docker exec nexus-vault vault secrets enable -version=2 -path=secret kv 2>/dev/null || true
    
    # Store tokens from environment
    echo "Storing tokens in Vault..."
    
    # GitHub token
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        docker exec nexus-vault vault kv put secret/tokens \
            github_token="$GITHUB_TOKEN" \
            github_user="${GITHUB_USER:-mikkihugo}"
    fi
    
    # OpenRouter token (if provided)
    if [ -n "${OPENROUTER_API_KEY:-}" ] && [ "$OPENROUTER_API_KEY" != "free" ]; then
        docker exec nexus-vault vault kv put secret/openrouter \
            api_key="$OPENROUTER_API_KEY"
    fi
    
    # OpenAI token (if in environment)
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        docker exec nexus-vault vault kv put secret/openai \
            api_key="$OPENAI_API_KEY"
    fi
    
    # Anthropic token (if in environment)
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        docker exec nexus-vault vault kv put secret/anthropic \
            api_key="$ANTHROPIC_API_KEY"
    fi
    
    # Cloudflare tokens (if in environment)
    if [ -n "${CF_API_TOKEN:-}" ]; then
        docker exec nexus-vault vault kv put secret/cloudflare \
            api_token="$CF_API_TOKEN" \
            api_email="${CF_API_EMAIL:-mikkihugo@gmail.com}"
    fi
    
    # Google AI API key (from gcloud if authenticated)
    if command -v gcloud &>/dev/null && gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        echo "Setting up Google AI credentials..."
        
        # Get access token for AI Platform
        GOOGLE_ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null)
        if [ -n "$GOOGLE_ACCESS_TOKEN" ]; then
            docker exec nexus-vault vault kv put secret/google \
                access_token="$GOOGLE_ACCESS_TOKEN" \
                project_id="$(gcloud config get-value project 2>/dev/null)" \
                account="$(gcloud config get-value account 2>/dev/null)"
        fi
        
        # Check for various Google AI API keys
        if [ -n "${GOOGLE_AI_API_KEY:-}" ]; then
            docker exec nexus-vault vault kv put secret/google/ai \
                api_key="$GOOGLE_AI_API_KEY"
        elif [ -n "${GOOGLE_AI_STUDIO_KEY:-}" ]; then
            docker exec nexus-vault vault kv put secret/google/ai \
                studio_key="$GOOGLE_AI_STUDIO_KEY"
        elif [ -n "${GOOGLE_GENERATIVE_AI_API_KEY:-}" ]; then
            docker exec nexus-vault vault kv put secret/google/ai \
                generative_key="$GOOGLE_GENERATIVE_AI_API_KEY"
        fi
    fi
    
    # Create policy for AI container
    docker exec nexus-vault vault policy write ai-policy - << 'EOF'
path "secret/data/tokens" {
  capabilities = ["read"]
}
path "secret/data/openrouter" {
  capabilities = ["read"]
}
path "secret/data/openai" {
  capabilities = ["read"]
}
path "secret/data/anthropic" {
  capabilities = ["read"]
}
path "secret/data/cloudflare" {
  capabilities = ["read"]
}
path "secret/data/google/ai" {
  capabilities = ["read"]
}
path "secret/data/google/cloud" {
  capabilities = ["read"]
}
EOF
    
    # Create token for AI container
    AI_VAULT_TOKEN=$(docker exec nexus-vault vault token create \
        -policy=ai-policy \
        -ttl=720h \
        -format=json | jq -r '.auth.client_token')
    
    # Update AI container with Vault token
    docker exec nexus-ai bash -c "echo 'export VAULT_TOKEN=$AI_VAULT_TOKEN' >> ~/.bashrc"
    docker exec nexus-ai bash -c "echo 'export VAULT_ADDR=http://nexus-vault:8200' >> ~/.bashrc"
    
    echo -e "${GREEN}✓ Vault configured with tokens${NC}"
}

# Deploy services
deploy() {
    echo -e "${YELLOW}Starting services...${NC}"
    
    docker compose -f docker-compose.quick.yml up -d
    
    # Wait for services
    echo "Waiting for services to start..."
    sleep 10
    
    # Setup Vault
    setup_vault
    
    # Configure AI container to use Vault
    configure_ai_vault
    
    # Show status
    docker compose -f docker-compose.quick.yml ps
    
    echo -e "${GREEN}✅ Deployment complete!${NC}"
}

# Configure AI container to fetch tokens from Vault
configure_ai_vault() {
    echo -e "${YELLOW}Configuring AI container to use Vault...${NC}"
    
    # Create script to fetch tokens from Vault
    docker exec nexus-ai bash -c 'cat > /usr/local/bin/vault-tokens << "EOF"
#!/bin/bash
# Fetch tokens from Vault and export them

if [ -z "$VAULT_TOKEN" ] || [ -z "$VAULT_ADDR" ]; then
    echo "Vault not configured"
    return 1
fi

# Fetch GitHub token
GITHUB_TOKEN=$(vault kv get -field=github_token secret/tokens 2>/dev/null)
if [ -n "$GITHUB_TOKEN" ]; then
    export GITHUB_TOKEN
    echo "✓ GitHub token loaded from Vault"
fi

# Fetch other tokens if they exist
OPENROUTER_API_KEY=$(vault kv get -field=api_key secret/openrouter 2>/dev/null || echo "free")
export OPENROUTER_API_KEY

OPENAI_API_KEY=$(vault kv get -field=api_key secret/openai 2>/dev/null)
[ -n "$OPENAI_API_KEY" ] && export OPENAI_API_KEY

ANTHROPIC_API_KEY=$(vault kv get -field=api_key secret/anthropic 2>/dev/null)
[ -n "$ANTHROPIC_API_KEY" ] && export ANTHROPIC_API_KEY

# Google AI keys
GOOGLE_AI_STUDIO_KEY=$(vault kv get -field=studio_key secret/google/ai 2>/dev/null)
[ -n "$GOOGLE_AI_STUDIO_KEY" ] && export GOOGLE_AI_STUDIO_KEY

GOOGLE_GENERATIVE_AI_API_KEY=$(vault kv get -field=generative_key secret/google/ai 2>/dev/null)
[ -n "$GOOGLE_GENERATIVE_AI_API_KEY" ] && export GOOGLE_GENERATIVE_AI_API_KEY

echo "✓ Tokens loaded from Vault"
EOF'
    
    docker exec nexus-ai chmod +x /usr/local/bin/vault-tokens
    
    # Add to bashrc
    docker exec nexus-ai bash -c 'echo "source /usr/local/bin/vault-tokens" >> ~/.bashrc'
    
    # Install vault CLI in AI container
    docker exec nexus-ai bash -c 'curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add - && \
        apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main" && \
        apt-get update && apt-get install -y vault'
    
    echo -e "${GREEN}✓ AI container configured for Vault${NC}"
}

# Show access info
show_info() {
    echo ""
    echo -e "${BLUE}🎉 Nexus AI Stack is running!${NC}"
    echo ""
    echo "Access your services:"
    echo "  • VS Code:  http://localhost:10080"
    echo "    Password: ${CODE_SERVER_PASSWORD:-nexus123}"
    echo ""
    echo "  • Jupyter:  http://localhost:10888"
    echo "    Token: Check logs with: docker logs nexus-ai"
    echo ""
    echo "  • Vault:    http://localhost:10200"
    echo "    Token: nexus-root-token"
    echo ""
    echo "Available AI tools:"
    echo "  • aider-free - Aider with GitHub Models"
    echo "  • aider-rag  - Aider with RAG support"
    echo "  • aichat     - Direct AI chat with RAG"
    echo "  • test-models - Test available models"
    echo ""
    echo "To enter the AI environment:"
    echo "  docker exec -it nexus-ai bash"
    echo ""
    echo "To use Aider with your code:"
    echo "  docker exec -it nexus-ai aider-free /workspace/your-project"
}

# Main execution
main() {
    case "${1:-deploy}" in
        deploy)
            check_prereqs
            create_env
            build_container
            create_quick_compose
            deploy
            show_info
            ;;
            
        build)
            check_prereqs
            build_container
            ;;
            
        start)
            docker compose -f docker-compose.quick.yml up -d
            show_info
            ;;
            
        stop)
            docker compose -f docker-compose.quick.yml down
            ;;
            
        logs)
            docker compose -f docker-compose.quick.yml logs -f
            ;;
            
        shell)
            docker exec -it nexus-ai bash
            ;;
            
        clean)
            docker compose -f docker-compose.quick.yml down -v
            docker rmi nexus-ai:latest || true
            ;;
            
        *)
            echo "Usage: $0 {deploy|build|start|stop|logs|shell|clean}"
            echo ""
            echo "  deploy - Build and start everything"
            echo "  build  - Just build the container"
            echo "  start  - Start services"
            echo "  stop   - Stop services"
            echo "  logs   - Show logs"
            echo "  shell  - Enter AI container"
            echo "  clean  - Remove everything"
            ;;
    esac
}

main "$@"