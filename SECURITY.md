# 🔐 Security Setup

This repository is **public** and contains NO secrets. All sensitive data is managed separately.

## 📋 Token Management via Private Gist (Recommended)

### Quick Setup for New Machines
```bash
# 1. Install dotfiles
git clone https://github.com/mikkihugo/dotfiles ~/.dotfiles
cd ~/.dotfiles && ./install.sh

# 2. Login to GitHub CLI (one-time)
gh auth login

# 3. Retrieve tokens from private gist
gh gist view YOUR_GIST_ID > ~/.env_tokens
source ~/.env_tokens

# 4. Auto-load on shell start (optional)
echo '[[ -f ~/.env_tokens ]] && source ~/.env_tokens' >> ~/.bashrc
```

### Managing Your Tokens

**View current tokens:**
```bash
gh gist view YOUR_GIST_ID
```

**Update tokens:**
```bash
# Edit locally then update
vim ~/.env_tokens
gh gist edit YOUR_GIST_ID ~/.env_tokens

# Or edit directly in browser
gh gist edit YOUR_GIST_ID --web
```

## 🛡️ Security Notes

- **Private gist** - Only accessible with your GitHub account
- **No passwords** - Uses GitHub authentication
- **Version controlled** - Gist tracks all changes
- **Cross-machine sync** - Same tokens everywhere

## 🚀 Quick Start Without Tokens

The environment works without tokens:
```bash
git clone https://github.com/mikkihugo/dotfiles
cd dotfiles && ./install.sh
# Everything works except GitHub operations
```