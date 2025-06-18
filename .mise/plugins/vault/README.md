# Hugo Vault Mise Plugins

Custom mise plugins that integrate with PostgreSQL vault for secure credential management.

## 🚀 Quick Start

```bash
# Run the master setup
./setup-all.sh

# Or setup individual plugins
./mise-vault-ai.sh setup      # AI tools (OpenAI, Anthropic, etc)
./mise-vault-cloud.sh setup   # Cloud providers (AWS, GCP, Azure)
./mise-vault-git.sh setup     # Git/GitHub/GitLab
./mise-vault-dev.sh setup     # Development tools
./mise-vault-monitoring.sh setup  # Monitoring & alerts
```

## 🔐 5 Custom Mise Plugins

### 1. **mise-vault-ai** - AI & LLM Integration
- Configures API keys for OpenAI, Anthropic, Google AI, Hugging Face
- Sets up aichat, llm CLI, and other AI tools
- Points to LiteLLM proxy if configured
- Auto-configures model endpoints

### 2. **mise-vault-cloud** - Cloud Provider Access
- AWS credentials and CLI configuration
- Google Cloud service accounts
- Azure service principals
- Cloudflare API tokens
- DigitalOcean access tokens
- Includes terraform and kubectl setup

### 3. **mise-vault-git** - Version Control Integration
- GitHub personal access tokens
- GitLab and Gitea tokens
- SSH key management
- GPG signing configuration
- Git user setup
- Installs gh, glab, tea, lazygit

### 4. **mise-vault-dev** - Development Environment
- Docker Hub credentials
- NPM/Cargo/PyPI tokens
- Database connection strings
- Redis URLs
- GitHub Copilot setup
- Editor configurations
- Project templates

### 5. **mise-vault-monitoring** - Observability Stack
- Datadog API keys
- Sentry DSN configuration
- PagerDuty integration
- Prometheus/Grafana setup
- Slack/Discord webhooks
- Twilio SMS alerts
- Health check scripts

## 📋 Features

Each plugin provides:
- **setup** - Load credentials from vault to environment
- **install** - Install related tools and CLIs
- **config** - Configure tools with best practices
- **all** - Run all of the above

## 🔧 Usage in Projects

Add to your project's `.mise.toml`:

```toml
[hooks]
enter = """
source ~/.dotfiles/tools/vault-client/mise-vault-plugin.sh setup
source ~/.dotfiles/.mise/plugins/vault/mise-vault-dev.sh setup
"""

[env]
# Project-specific vault overrides
VAULT_HOST = "your-vault-host"
```

## 🌐 Environment Variables

All plugins respect these vault connection variables:
- `VAULT_HOST` - PostgreSQL host (default: db)
- `VAULT_USER` - PostgreSQL user (default: hugo)
- `VAULT_PASSWORD` - PostgreSQL password (default: hugo)
- `VAULT_DB` - PostgreSQL database (default: hugo)

## 🔑 Required Vault Keys

### AI Plugin
- `openai_api_key`
- `anthropic_api_key`
- `google_ai_key`
- `huggingface_token`
- `replicate_api_key`
- `litellm_url` (optional)

### Cloud Plugin
- `aws_access_key_id`, `aws_secret_access_key`
- `google_application_credentials`
- `azure_client_id`, `azure_client_secret`
- `cloudflare_api_token`

### Git Plugin
- `github_token`
- `gitlab_token`
- `git_user_name`, `git_user_email`
- `ssh_private_key`
- `gpg_private_key` (optional)

### Dev Plugin
- `docker_username`, `docker_password`
- `npm_token`
- `cargo_token`
- `postgres_host`, `postgres_user`, `postgres_password`

### Monitoring Plugin
- `datadog_api_key`
- `sentry_dsn`
- `slack_webhook_url`
- `twilio_account_sid`, `twilio_auth_token`

## 🛡️ Security

- Credentials are stored encrypted in PostgreSQL
- No secrets in environment files or git
- Vault access requires authentication
- Supports role-based access control
- Audit logging available

## 🔄 Integration with mise

The plugins enhance mise's capabilities:
- Auto-load credentials on directory enter
- Project-specific secret management
- Tool version + credential management
- Shell hook integration
- Cross-platform support

## 📦 Minimal Dependencies

- PostgreSQL client (5MB)
- Basic shell (bash)
- Python with psycopg2 (optional)
- No heavy frameworks required

## 🎯 Example Workflow

```bash
# Store your API keys in vault
vault-client set openai_api_key sk-...
vault-client set github_token ghp_...

# Enter a project directory with .mise.toml
cd my-project
# Credentials are automatically loaded!

# Use tools with automatic auth
gh repo create
aichat "Help me with this code"
terraform apply

# Everything just works! 🎉
```