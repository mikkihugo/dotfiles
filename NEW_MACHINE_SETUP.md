# New Machine Setup with SOPS-Integrated Dotfiles

## Prerequisites
- SSH key copied to new machine (same key you use everywhere: `~/.ssh/id_ed25519`)
- Git configured with your credentials

## Installation Process

### 1. Install Nix (if not already installed)
```bash
curl -L https://nixos.org/nix/install | sh -s -- --daemon
# Source nix or restart shell
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 2. Clone Your Dotfiles
```bash
git clone git@github.com:mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### 3. Enter Nix Development Environment
```bash
# This automatically installs all tools including SOPS, age, etc.
nix develop
```

### 4. Set Up SOPS Decryption Key
```bash
# Generate your private age key from SSH key
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Verify you can decrypt secrets
sops -d secrets/shared.yaml
```

### 5. Install Dotfiles
```bash
# This runs your existing bootstrap process
./install.sh

# Optional: Set up login shell integration
./setup-login-shell.sh
```

### 6. Verify Installation
```bash
# Start new shell - should have all environment variables
bash -l

# Check that secrets are loaded
echo $GITHUB_TOKEN
echo $OPENAI_API_KEY

# Test tools work
gh auth status
```

## What Happens Automatically

✅ **Nix provides all tools**: SOPS, age, development tools, etc.
✅ **SOPS decrypts secrets**: Environment variables available immediately
✅ **Dotfiles symlinked**: All config files in proper locations
✅ **Same environment everywhere**: Identical setup across all machines

## Differences from Current Setup

**Before (Gist-based):**
- Clone dotfiles → Run install → Wait for gist sync timer → Manual token fixes

**After (SOPS-based):**
- Clone dotfiles → Run install → **Everything works immediately**

## Troubleshooting

**Secrets not loading?**
```bash
# Check SOPS key exists
ls -la ~/.config/sops/age/keys.txt

# Test decryption
sops -d secrets/shared.yaml

# Check env.sh is sourcing SOPS
grep -A 5 "SOPS-managed" ~/.dotfiles/shell/shared/env.sh
```

**Missing tools?**
```bash
# Make sure you're in nix develop shell
nix develop
which sops age ssh-to-age
```

## Security Notes

- ✅ **Private key stays local**: `~/.config/sops/age/keys.txt` never gets committed
- ✅ **Secrets encrypted in git**: Safe to push/pull anywhere
- ✅ **Same SSH key everywhere**: Reuse your existing key for SOPS

The beauty: **Your existing installation process (`./install.sh`) works unchanged** - SOPS integration is seamless!