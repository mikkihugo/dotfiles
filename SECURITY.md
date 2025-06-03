# 🔐 Security Setup

This repository is **public** and contains NO secrets. All sensitive data is managed separately.

## 📋 Token Management Options

### Option 1: Manual Setup (Simple)
After cloning, manually set your tokens:
```bash
export GITHUB_TOKEN="your_token_here"
echo "export GITHUB_TOKEN='$GITHUB_TOKEN'" >> ~/.bashrc
```

### Option 2: Encrypted Sync (Recommended)
Use the included env-manager for secure token sync:
```bash
# First time setup on primary machine
env-setup    # Creates encrypted .env.gpg
env-backup   # Saves to dotfiles/config/.env.gpg

# On new machines
env-restore  # Restores from dotfiles/config/.env.gpg
```

### Option 3: Private Gist (Alternative)
Store tokens in a private GitHub Gist:
```bash
# Save tokens to private gist
gh gist create --private ~/.env

# On new machine
gh gist view GIST_ID > ~/.env
source ~/.env
```

## 🛡️ Security Notes

- **Never commit tokens** to this public repo
- **Use .env.gpg** for encrypted storage
- **GPG passphrase** protects your secrets
- **Public repo** allows easy cloning without auth

## 🚀 Quick Start Without Tokens

The environment works without tokens:
```bash
git clone https://github.com/USERNAME/dotfiles
cd dotfiles && ./install.sh
# Everything works except GitHub operations
```