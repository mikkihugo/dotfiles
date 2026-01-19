# SOPS Secrets Management

This dotfiles repo uses [SOPS](https://github.com/getsops/sops) to encrypt sensitive data with age encryption.

## Setup Complete ✅

- Age key: `~/.config/sops/age/keys.txt`
- SOPS config: `~/.dotfiles/.sops.yaml`
- Encrypted secrets: `~/.dotfiles/secrets/api-keys.yaml`

## Quick Reference

### Managing API Keys

```bash
# Edit encrypted API keys
sops ~/.dotfiles/secrets/api-keys.yaml

# View decrypted content
sops --decrypt ~/.dotfiles/secrets/api-keys.yaml
```

### Managing .env Files

```bash
# Encrypt a .env file
sops-env encrypt .env                # Creates .env.enc

# Edit encrypted .env.enc
sops-env edit .env.enc              # Opens in $EDITOR

# Decrypt and view
sops-env decrypt .env.enc           # Prints to stdout

# Create new encrypted env file
sops-env create project.env.enc     # Creates and opens for editing
```

### Auto-Loading in Projects

The bashrc automatically loads `.env.enc` files when you cd into a directory:

```bash
cd ~/my-project
# If .env.enc exists, it's automatically decrypted and sourced
```

Or use with direnv:

```bash
# In your project's .envrc:
sops_source_env .env.enc
```

## File Patterns

SOPS will automatically encrypt these files:

- `secrets/**/*.yaml`
- `secrets/**/*.json`  
- `**/.env.enc`
- `**/.envrc.enc`

## Current Encrypted Secrets

### `~/.dotfiles/secrets/api-keys.yaml`

Contains:
- LLM-MUX API key and base URL
- Loaded automatically in bashrc
- Exports: `$OPENAI_API_KEY`, `$ANTHROPIC_API_KEY`, etc.

## Adding New Secrets

1. Edit the encrypted file:
   ```bash
   sops ~/.dotfiles/secrets/api-keys.yaml
   ```

2. Add your secrets in YAML format:
   ```yaml
   github:
     token: "ghp_..."
   
   aws:
     access_key: "AKIA..."
     secret_key: "..."
   ```

3. Save and close - it's automatically encrypted

4. Update bashrc to export the new variables if needed

## Best Practices

- ✅ **Always** encrypt API keys, tokens, passwords
- ✅ **Never** commit unencrypted secrets to git
- ✅ Use `.env.enc` for project-specific secrets
- ✅ Use `~/.dotfiles/secrets/` for global secrets
- ❌ **Don't** put secrets in plain `.env` files
- ❌ **Don't** commit your age private key

## Backup Your Age Key

**IMPORTANT**: Backup `~/.config/sops/age/keys.txt` securely!

Without this key, you **cannot** decrypt your secrets.

```bash
# Backup to a secure location (NOT in git!)
cp ~/.config/sops/age/keys.txt ~/backup/age-key-backup.txt
```

## Troubleshooting

### "failed to get the data key"

- Check age key exists: `ls ~/.config/sops/age/keys.txt`
- Verify SOPS_AGE_KEY_FILE is set: `echo $SOPS_AGE_KEY_FILE`

### Secrets not loading

```bash
# Test manual decryption
sops --decrypt ~/.dotfiles/secrets/api-keys.yaml

# Reload bashrc
source ~/.dotfiles/shell/bash/bashrc
```

### Edit fails

Make sure `$EDITOR` is set:
```bash
export EDITOR=nano  # or vim, code, etc.
```

## Age Key Backup Location

Your age key is backed up in a **private GitHub gist**:

- Gist ID: `bc16d0e5315aa78394a4fe7468a79f4e`
- Created: 2026-01-07
- URL: https://gist.github.com/bc16d0e5315aa78394a4fe7468a79f4e

### Restore from Backup

If you need to restore your age key on a new machine:

```bash
# Create directory
mkdir -p ~/.config/sops/age

# Download from gist
gh gist view bc16d0e5315aa78394a4fe7468a79f4e --raw > ~/.config/sops/age/keys.txt

# Set correct permissions
chmod 600 ~/.config/sops/age/keys.txt

# Verify
sops --decrypt ~/.dotfiles/secrets/api-keys.yaml
```

### Keep Gist Updated

If you regenerate your age key:

```bash
# Update the gist
gh gist edit bc16d0e5315aa78394a4fe7468a79f4e ~/.config/sops/age/keys.txt
```

## Claude Code OAuth Token

Your Claude Code OAuth token is now encrypted and auto-loaded!

### Current Setup

The token is stored in:
- **Encrypted**: `~/.dotfiles/secrets/api-keys.yaml` (encrypted with SOPS)
- **Fallback**: `~/.claude-max/oauth.json` (unencrypted - can be deleted)

### Environment Variable

On shell startup, `$CLAUDE_CODE_OAUTH_TOKEN` is automatically exported:

```bash
echo $CLAUDE_CODE_OAUTH_TOKEN
# sk-ant-oat01-...
```

### Updating the Token

If you need to update your Claude Code OAuth token:

```bash
# Method 1: Edit encrypted secrets directly
sops ~/.dotfiles/secrets/api-keys.yaml
# Edit the claude_code.oauth_token field

# Method 2: Extract from ~/.claude-max/oauth.json and update
NEW_TOKEN=$(jq -r '.access_token' ~/.claude-max/oauth.json)
# Then manually edit with sops as above
```

### Security Note

Once encrypted in SOPS, you can safely delete the unencrypted version:

```bash
# Optional: Remove unencrypted OAuth token
rm ~/.claude-max/oauth.json

# The encrypted version in SOPS will continue to work
```
