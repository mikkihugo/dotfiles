# Key Management Options for Development

## Current Setup
- **dotenv v1.1.0** installed globally at `/usr/local/bin/dotenv`
- Keys stored in `~/.env_tokens` (backed up to private GitHub Gist)
- Keys loaded in shell via `source ~/.env_tokens`

## Better Key Management Options

### 1. **GitHub Secrets + gh CLI** (Recommended for repos)
```bash
# Set secret for a repository
gh secret set OPENAI_API_KEY --repo mikkihugo/myproject

# List secrets
gh secret list --repo mikkihugo/myproject

# Use in GitHub Actions
# Automatically available as ${{ secrets.OPENAI_API_KEY }}

# For local development, use gh CLI to fetch
gh api repos/mikkihugo/myproject/actions/secrets
```

**Pros:** Integrated with GitHub, works with Actions, encrypted
**Cons:** Only for specific repos, not global

### 2. **1Password CLI** (Best for teams/personal)
```bash
# Install
mise install 1password-cli

# Store secret
op item create --category=apikey --title="OpenAI API" \
  --vault="Development" apikey="sk-..."

# Retrieve in scripts
export OPENAI_API_KEY=$(op read "op://Development/OpenAI API/apikey")

# Use with dotenv
op inject -i .env.template -o .env
```

**Pros:** Professional secret management, team sharing, audit logs
**Cons:** Requires 1Password subscription

### 3. **Doppler** (Modern secret management)
```bash
# Install
curl -Ls https://cli.doppler.com/install.sh | sh

# Setup project
doppler setup

# Set secrets
doppler secrets set OPENAI_API_KEY="sk-..."

# Run commands with secrets
doppler run -- npm start

# Export to .env
doppler secrets download --no-file --format env > .env
```

**Pros:** Free tier, version control for secrets, environments
**Cons:** Another service to manage

### 4. **HashiCorp Vault** (Self-hosted option)
```bash
# Run Vault locally
docker run -d --name vault -p 8200:8200 vault

# Store secret
vault kv put secret/api-keys openai="sk-..."

# Retrieve
vault kv get -field=openai secret/api-keys
```

**Pros:** Self-hosted, enterprise-grade, fine-grained access control
**Cons:** Complex setup, overkill for personal use

### 5. **SOPS (Mozilla)** (Encrypt files in repo)
```bash
# Install
mise install sops

# Encrypt .env file
sops -e -i .env

# Decrypt for use
sops -d .env > .env.decrypted
source .env.decrypted
rm .env.decrypted

# Works with multiple providers (age, GPG, AWS KMS, etc.)
```

**Pros:** Encrypted secrets in git, simple, supports teams
**Cons:** Need to manage encryption keys

### 6. **direnv with encrypted files**
```bash
# Install direnv (already in your mise tools)
# Create .envrc
cat > .envrc << 'EOF'
# Decrypt and load secrets
if [ -f .env.gpg ]; then
  gpg -d .env.gpg 2>/dev/null | dotenv
fi
EOF

# Encrypt your .env
gpg -c .env -o .env.gpg
```

**Pros:** Automatic per-directory env loading, secure
**Cons:** Need to manage GPG keys

### 7. **Keychain/Keyring Integration**
```bash
# Use system keychain (macOS/Linux)
# Python keyring
pip install keyring

# Store
python -c "import keyring; keyring.set_password('myapp', 'openai', 'sk-...')"

# Retrieve in shell
export OPENAI_API_KEY=$(python -c "import keyring; print(keyring.get_password('myapp', 'openai'))")
```

**Pros:** OS-level security, no files to manage
**Cons:** Platform-specific, requires Python

## Recommended Setup for You

Given your setup, I recommend a hybrid approach:

### For Global Keys (like API tokens):
1. **Keep using GitHub Gist** for backup (current approach)
2. **Add SOPS** for local encryption:
   ```bash
   # Encrypt your .env_tokens
   sops -e ~/.env_tokens > ~/.env_tokens.enc
   
   # Decrypt when needed
   sops -d ~/.env_tokens.enc > ~/.env_tokens
   ```

### For Project-Specific Keys:
1. **Use GitHub Secrets** for CI/CD
2. **Use direnv + SOPS** for local development:
   ```bash
   # In project directory
   echo "dotenv .env.local" > .envrc
   sops -e .env.local  # Creates .env.local.enc
   ```

### Quick Implementation Script:
```bash
#!/bin/bash
# setup-secure-env.sh

# Install required tools
mise install sops direnv

# Create age key for SOPS (simpler than GPG)
age-keygen -o ~/.config/sops/age/keys.txt

# Create SOPS config
cat > ~/.sops.yaml << EOF
creation_rules:
  - path_regex: \.env.*\.enc$
    age: $(grep "public key:" ~/.config/sops/age/keys.txt | cut -d' ' -f4)
EOF

# Encrypt existing tokens
sops -e ~/.env_tokens > ~/.env_tokens.enc

# Create shell function for easy access
cat >> ~/.bashrc << 'EOF'
# Secure environment loading
load-secrets() {
  if [ -f ~/.env_tokens.enc ]; then
    export $(sops -d ~/.env_tokens.enc | xargs)
  fi
}
EOF
```

This gives you encryption at rest while keeping your current workflow!