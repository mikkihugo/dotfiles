# Central Secret Management Solutions with Web UI

## Best Options for Central Management with Web Interface

### 1. **Doppler** (Recommended - Best Balance)
```bash
# Quick setup
curl -Ls https://cli.doppler.com/install.sh | sh
doppler login
doppler setup

# Create project
doppler projects create my-app

# Manage environments
doppler environments create production
doppler environments create staging
doppler environments create development

# Set secrets via CLI or Web UI
doppler secrets set OPENAI_API_KEY --project my-app --config dev

# Use in any environment
doppler run -- npm start
```

**Web Features:**
- 🌐 https://dashboard.doppler.com
- Environment management (dev/staging/prod)
- Secret versioning and rollback
- Access logs and audit trail
- Team management
- Branching for secrets
- **Free tier:** 5 users, unlimited secrets

### 2. **Infisical** (Open Source Alternative)
```bash
# Self-hosted or cloud
docker run -d \
  -p 8080:8080 \
  -e ENCRYPTION_KEY=$(openssl rand -hex 32) \
  -e JWT_SECRET=$(openssl rand -hex 32) \
  infisical/infisical

# Or use their cloud: https://infisical.com

# CLI installation
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
sudo apt-get install infisical

# Usage
infisical init
infisical secrets set OPENAI_API_KEY="sk-..."
infisical run -- npm start
```

**Web Features:**
- Beautiful modern UI
- Environment management
- Secret versioning
- Point-in-time recovery
- Webhooks and integrations
- **Free tier:** 5 team members

### 3. **HashiCorp Vault with UI** (Enterprise-grade)
```bash
# Run with UI enabled
docker run -d \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' \
  -e 'VAULT_UI=true' \
  vault

# Access UI at http://localhost:8200/ui
# Token: myroot

# Or use HCP Vault (managed cloud version)
# https://cloud.hashicorp.com/products/vault
```

**Web Features:**
- Full-featured UI at :8200/ui
- Policy management
- Dynamic secrets
- Encryption as a service
- **HCP Free tier:** 25 secrets

### 4. **AWS Secrets Manager** (If using AWS)
```bash
# Store secret
aws secretsmanager create-secret \
  --name prod/myapp/api-keys \
  --secret-string '{"openai":"sk-...","github":"ghp-..."}'

# Retrieve
aws secretsmanager get-secret-value \
  --secret-id prod/myapp/api-keys

# Use with .env files
aws secretsmanager get-secret-value \
  --secret-id prod/myapp/api-keys \
  --query SecretString \
  --output text | jq -r 'to_entries[] | "\(.key)=\(.value)"' > .env
```

**Web Features:**
- AWS Console UI
- Automatic rotation
- Cross-region replication
- IAM integration
- **Cost:** $0.40/secret/month

### 5. **Railway** (Developer-friendly)
```bash
# Install Railway CLI
npm install -g @railway/cli

# Login and link project
railway login
railway link

# Set variables
railway variables set OPENAI_API_KEY="sk-..."

# Run with variables
railway run npm start
```

**Web Features:**
- https://railway.app
- Beautiful UI
- Per-environment secrets
- Deploy from GitHub
- Team collaboration
- **Free tier:** $5 credit/month

### 6. **Vercel Environment Variables** (If using Vercel)
```bash
# Install Vercel CLI
npm i -g vercel

# Set secrets
vercel env add OPENAI_API_KEY production
vercel env add OPENAI_API_KEY preview
vercel env add OPENAI_API_KEY development

# Pull to .env.local
vercel env pull
```

**Web Features:**
- Vercel Dashboard
- Per-environment secrets
- Encrypted at rest
- Integrated with deployments
- **Free tier:** Hobby plan included

## Quick Comparison for Your Use Case

| Service | Setup Time | Free Tier | Web UI Quality | Multi-Env | Multi-Repo |
|---------|------------|-----------|----------------|-----------|------------|
| **Doppler** | 5 min | ✅ Generous | ⭐⭐⭐⭐⭐ | ✅ | ✅ |
| **Infisical** | 10 min | ✅ Good | ⭐⭐⭐⭐⭐ | ✅ | ✅ |
| **Railway** | 5 min | ✅ Limited | ⭐⭐⭐⭐ | ✅ | ✅ |
| **Vault** | 30 min | ✅ Limited | ⭐⭐⭐ | ✅ | ✅ |
| **AWS** | 15 min | ❌ Paid | ⭐⭐⭐ | ✅ | ✅ |

## Recommended: Doppler Quick Start

```bash
# 1. Install
curl -Ls https://cli.doppler.com/install.sh | sh

# 2. Login (opens browser)
doppler login

# 3. Create workspace structure
doppler projects create personal-dev
doppler projects create architecturemcp
doppler projects create singularity-engine

# 4. Import existing tokens
doppler secrets upload --project personal-dev < ~/.env_tokens

# 5. Create shell integration
cat >> ~/.bashrc << 'EOF'
# Doppler integration
alias secrets="doppler run --"
alias secrets-sync="doppler secrets download --no-file --format env > ~/.env_tokens"

# Auto-load Doppler in project directories
if [ -f ".doppler.yaml" ]; then
  export $(doppler secrets download --no-file --format env | xargs)
fi
EOF

# 6. In any project
cd ~/code/architecturemcp
doppler setup  # Interactive setup
doppler run -- npm start  # Auto-loads all secrets
```

**Doppler Web Dashboard Features:**
- 🔍 Search across all secrets
- 📁 Organize by projects and environments
- 👥 Team access control
- 📝 Change history and rollback
- 🔔 Webhooks for changes
- 🔗 Integrations (GitHub, Vercel, AWS, etc.)
- 📊 Access logs and audit trail

Would you like me to help you set up Doppler or another solution?