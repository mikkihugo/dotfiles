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

---

## GSD Keys Pattern — process-scoped secrets via wrapper

As of 2026-04-15 the `sf-run` coding agent (formerly `gsd`) has its API keys stored under a
top-level **`gsd:`** section in `secrets/api-keys.yaml`, **separate from** the
top-level sections loaded by `load-ai-keys`. The distinction matters:

| Section | Loaded by | Visible where |
|---|---|---|
| `llm_gateway:`, `kimi:`, `openrouter:`, etc. | `load-ai-keys` bashrc alias | Exported into the interactive shell when you run `load-ai-keys` — every child process inherits them |
| **`gsd:`** | `~/bin/sf-run` wrapper only | Exported into the `sf-run` process env only — nothing else on the system sees them |

The wrapper at `~/bin/sf-run` runs at launch:

```bash
while IFS='=' read -r k v; do
  [ -n "$k" ] && export "$k=$v"
done < <(
  sops --config ~/.dotfiles/.sops.yaml -d ~/.dotfiles/secrets/api-keys.yaml 2>/dev/null \
    | yq -r '.gsd // {} | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null
)
exec ~/.bun/bin/sf-run "$@"
```

Effect: `sf-run` and its children see the keys, the login shell does not. The
keys in the `gsd:` section are **completely separate** from the keys in other
top-level sections — you can (and do) have different OpenRouter, Kimi, and
OLLAMA keys in each because `gsd:` is sf-run-scoped.

### Current `gsd:` section contents

Flat `KEY: VALUE` map. As of 2026-04-15:

```yaml
gsd:
    XIAOMI_TOKEN_PLAN_AMS_API_KEY: ...  # custom provider in models.json
    MINIMAX_API_KEY: ...
    OLLAMA_API_KEY: ...                  # NB: pi calls the provider "ollama-cloud" but expects OLLAMA_API_KEY
    OPENCODE_API_KEY: ...                # NB: provider is "opencode-go", env var is OPENCODE_API_KEY (no _GO_)
    MISTRAL_API_KEY: ...
    TAVILY_API_KEY: ...                  # consumed by gsd's search-the-web tool
    GEMINI_API_KEY: ...                  # used by provider "google"
    ZAI_API_KEY: ...
    KIMI_API_KEY: ...                    # NB: provider is "kimi-coding", env var is KIMI_API_KEY (no _CODE_)
    OPENROUTER_API_KEY: ...              # free-only child key (limit=0), provisioned via openrouter-management
```

**Important**: the env var names are NOT derived from the provider id. Pi's
`packages/pi-ai/src/env-api-keys.ts` has a hardcoded map. When adding a new key,
look up the exact name there — for example:

- provider `kimi-coding` → env var `KIMI_API_KEY` (NOT `KIMI_CODE_API_KEY`)
- provider `opencode-go` → env var `OPENCODE_API_KEY` (NOT `OPENCODE_GO_API_KEY`)
- provider `google` → env var `GEMINI_API_KEY`
- provider `ollama-cloud` → env var `OLLAMA_API_KEY`

Custom providers defined in `models.json` that are NOT in pi's map can use
any `UPPER_SNAKE_NAME` — just reference the same name in both sops and the
`models.json` `apiKey` field.

### Adding or rotating a gsd key — interactive (the easy one)

```bash
sops --config ~/.dotfiles/.sops.yaml ~/.dotfiles/secrets/api-keys.yaml
```

Find the `gsd:` block near the bottom, add or update an entry, save, sops
re-encrypts. **The `--config` flag is mandatory** — sops walks up from the
CWD (not the file path) looking for `.sops.yaml`, so running sops from `~` or
`/tmp/` without `--config` will fail silently with `config file not found, or
has no creation rules`. Learned that one the hard way.

Restart `sf-run` (exit TUI and relaunch) — the wrapper re-decrypts at each launch,
so no cache invalidation needed.

### Adding or rotating a gsd key — non-interactive (for scripted migrations)

Used by Claude Code sessions doing batch migrations. Decrypt → edit plaintext
in-place via text or python → re-encrypt → atomic mv:

```bash
set -u
SOPS_CONF=~/.dotfiles/.sops.yaml
TARGET=~/.dotfiles/secrets/api-keys.yaml
TMP=~/.dotfiles/secrets/api-keys.plain.yaml
NEW=~/.dotfiles/secrets/api-keys.yaml.new
trap '[ -f "$TMP" ] && { shred -u "$TMP" 2>/dev/null || rm -f "$TMP"; }; [ -f "$NEW" ] && rm -f "$NEW"' EXIT

sops --config "$SOPS_CONF" -d "$TARGET" > "$TMP" || exit 1
chmod 600 "$TMP"

# edit $TMP here (python / sed / whatever — avoid yaml.dump round-trips
# if you care about preserving comments and formatting)

if sops --config "$SOPS_CONF" -e "$TMP" > "$NEW"; then
  [ -s "$NEW" ] && grep -q '"sops":\|^sops:' "$NEW" && mv "$NEW" "$TARGET"
fi
# $TMP shredded by trap
```

The `-s "$NEW" && grep -q sops` sanity check catches a failure mode where
`sops -e` silently 0-bytes the output file on config errors. Without it, the
`mv` would wipe the encrypted original with an empty file.

### DO NOT run `/gsd keys add <provider>` inside gsd

Pi's built-in `/gsd keys add` command writes the key plaintext to
`~/.gsd/agent/auth.json` AND exports it to `process.env` for the current
session. If you run it, you undo the point of the wrapper — plaintext key ends
up on disk and survives across sessions. Same goes for `/gsd keys rotate`.

**Always rotate via the sops file**, not gsd's built-in key commands.

### OpenRouter-management section (provisioning keys)

Separate top-level section `openrouter-management:` holds the OpenRouter
provisioning key. Used by scripts that call `POST /api/v1/keys` to create
scoped child keys — never by inference flows. The `gsd:` section's
`OPENROUTER_API_KEY` is one such child key, provisioned with `limit: 0` so it
can only call `:free` models and cannot accrue paid spend.

To create another scoped child key:

```bash
KEY=$(sops --config ~/.dotfiles/.sops.yaml -d ~/.dotfiles/secrets/api-keys.yaml \
  | yq -r '.["openrouter-management"].api_key')
curl -sS -X POST https://openrouter.ai/api/v1/keys \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"your-scope","limit":0}'
unset KEY
# Response includes {"key":"sk-or-v1-..."} — copy into the appropriate sops
# section, never leave it in shell history or a tmp file
```

`limit: 0` means the child key is blocked from accruing any paid spend on
OpenRouter — but `:free`-suffixed models still work because they cost $0.

### Related

- `~/bin/gsd` — the wrapper that injects the `gsd:` section into the gsd process
- `~/.gsd/agent/models.json` — gsd's chat provider definitions, with `apiKey`
  fields referencing the env var names the wrapper exports
- `~/.gsd/agent/auth.json` — gsd's tool/OAuth credential store; holds the
  `search_provider` preference and `openai-codex` OAuth stub only, no plaintext
  api_keys as of the 2026-04-15 migration
