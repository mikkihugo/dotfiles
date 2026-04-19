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

### 3. Set Up SOPS Decryption Key
```bash
# Generate your private age key from SSH key
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Verify you can decrypt secrets
sops -d secrets/api-keys.yaml
```

### 4. Authorize the Machine Key
```bash
# Get the public recipient for this machine
ssh-to-age -i ~/.ssh/id_ed25519.pub

# Add that recipient to ~/.dotfiles/.sops.yaml on an authorized machine,
# then re-encrypt the secrets and pull the updated repo here.
```

### 5. Install Dotfiles
```bash
# Runs bootstrap: sudoers NOPASSWD setup, SOPS preflight, home-manager,
# tailscale install + headscale join, openclaw, etc.
#
# Will prompt for sudo password ONCE (during 02-sudoers.sh) — after that
# every later step + every future `hms` runs unprompted.
./install.sh

# Optional: Set up login shell integration
./setup-login-shell.sh
```

### 6. (Windows host only) Install Tailscale on the Windows side too
```powershell
# In PowerShell on the Windows host (not in WSL)
winget install -e --id tailscale.tailscale
tailscale up --login-server=https://vpn.hugo.dk
# UAC prompts on first elevation; paste the authkey from
#   sops -d secrets/api-keys.yaml | grep authkey
# to skip the browser auth flow.
```
Without this step, your Windows browser can't reach `vault.hugo.dk` and
other tailnet-only services — WSL has its own tailnet identity, but
Windows traffic is separate.

### 7. Verify Installation
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
✅ **SOPS decrypts secrets**: once this machine's recipient is authorized
✅ **Dotfiles symlinked**: All config files in proper locations
✅ **Same environment everywhere**: Identical setup across all machines

## Differences from Current Setup

**Before (Gist-based):**
- Clone dotfiles → Run install → Wait for gist sync timer → Manual token fixes

**After (SOPS-based):**
- Clone dotfiles → authorize machine recipient → run install → secrets work immediately

## Troubleshooting

**Secrets not loading?**
```bash
# Check SOPS key exists
ls -la ~/.config/sops/age/keys.txt

# Test decryption
sops -d secrets/api-keys.yaml

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

The key detail: `./install.sh` now bootstraps the local age key before Home Manager,
but a brand-new machine still needs its public recipient added to `.sops.yaml`
before repo secrets can decrypt successfully.
