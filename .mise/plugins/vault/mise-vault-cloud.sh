#!/bin/bash
# Mise plugin for cloud providers - AWS, GCP, Azure, Cloudflare from vault

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../tools/vault-client/vault-client.sh"

mise_vault_cloud_setup() {
    echo "☁️  Loading cloud credentials from vault..."
    
    # AWS
    local aws_key=$(vault_get "aws_access_key_id")
    local aws_secret=$(vault_get "aws_secret_access_key")
    local aws_region=$(vault_get "aws_default_region")
    if [ -n "$aws_key" ] && [ -n "$aws_secret" ]; then
        export AWS_ACCESS_KEY_ID="$aws_key"
        export AWS_SECRET_ACCESS_KEY="$aws_secret"
        export AWS_DEFAULT_REGION="${aws_region:-us-east-1}"
        echo "  ✓ AWS configured"
    fi
    
    # Google Cloud
    local gcp_creds=$(vault_get "google_application_credentials")
    local gcp_project=$(vault_get "google_cloud_project")
    if [ -n "$gcp_creds" ]; then
        echo "$gcp_creds" > ~/.gcp-credentials.json
        export GOOGLE_APPLICATION_CREDENTIALS=~/.gcp-credentials.json
        export GOOGLE_CLOUD_PROJECT="$gcp_project"
        export GCP_PROJECT="$gcp_project"
        echo "  ✓ Google Cloud configured"
    fi
    
    # Azure
    local azure_client=$(vault_get "azure_client_id")
    local azure_secret=$(vault_get "azure_client_secret")
    local azure_tenant=$(vault_get "azure_tenant_id")
    local azure_sub=$(vault_get "azure_subscription_id")
    if [ -n "$azure_client" ] && [ -n "$azure_secret" ]; then
        export AZURE_CLIENT_ID="$azure_client"
        export AZURE_CLIENT_SECRET="$azure_secret"
        export AZURE_TENANT_ID="$azure_tenant"
        export AZURE_SUBSCRIPTION_ID="$azure_sub"
        echo "  ✓ Azure configured"
    fi
    
    # Cloudflare
    local cf_token=$(vault_get "cloudflare_api_token")
    local cf_email=$(vault_get "cloudflare_email")
    local cf_zone=$(vault_get "cloudflare_zone_id")
    if [ -n "$cf_token" ]; then
        export CLOUDFLARE_API_TOKEN="$cf_token"
        export CF_API_TOKEN="$cf_token"
        export CF_API_EMAIL="$cf_email"
        export CF_ZONE_ID="$cf_zone"
        echo "  ✓ Cloudflare configured"
    fi
    
    # DigitalOcean
    local do_token=$(vault_get "digitalocean_token")
    if [ -n "$do_token" ]; then
        export DIGITALOCEAN_ACCESS_TOKEN="$do_token"
        export DO_AUTH_TOKEN="$do_token"
        echo "  ✓ DigitalOcean configured"
    fi
}

# Install cloud CLIs
mise_vault_cloud_install() {
    echo "📦 Installing cloud tools..."
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf awscliv2.zip aws/
    fi
    
    # Google Cloud SDK
    if ! command -v gcloud &> /dev/null; then
        echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
        curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
        sudo apt-get update && sudo apt-get install google-cloud-sdk
    fi
    
    # Azure CLI
    if ! command -v az &> /dev/null; then
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    fi
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        mise use -g terraform@latest
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        mise use -g kubectl@latest
    fi
}

# Configure cloud profiles
mise_vault_cloud_config() {
    # AWS config
    mkdir -p ~/.aws
    cat > ~/.aws/config << EOF
[default]
region = ${AWS_DEFAULT_REGION:-us-east-1}
output = json
EOF
    
    # Cloudflare config
    mkdir -p ~/.cloudflare
    cat > ~/.cloudflare/config.yaml << EOF
api_token: ${CF_API_TOKEN}
email: ${CF_API_EMAIL}
EOF
}

case "${1:-setup}" in
    setup)
        mise_vault_cloud_setup
        ;;
    install)
        mise_vault_cloud_install
        ;;
    config)
        mise_vault_cloud_config
        ;;
    all)
        mise_vault_cloud_setup
        mise_vault_cloud_install
        mise_vault_cloud_config
        ;;
    *)
        echo "Usage: $0 {setup|install|config|all}"
        ;;
esac