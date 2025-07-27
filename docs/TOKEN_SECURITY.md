# API Token Security Guidelines

## ⚠️ IMPORTANT: Never commit API tokens to git

This repository has security measures in place to prevent accidental commits of sensitive data like API keys and tokens.

## 🔒 Secure Token Management

### Where to store API tokens:
- **✅ Recommended**: `~/.env_tokens` (private GitHub gist, gitignored)
- **✅ Alternative**: Environment variables set in your shell
- **❌ NEVER**: Hardcoded in any file committed to git

### Environment Variables Used:
- `GOOGLE_AI_API_KEY` - Google AI/Gemini API key
- `CF_API_TOKEN` - Cloudflare API token
- `GITHUB_TOKEN` - GitHub personal access token

### Setup Instructions:

1. **Create ~/.env_tokens file:**
   ```bash
   # Store in private gist for backup/sync
   gh gist create --secret ~/.env_tokens
   ```

2. **Add your tokens:**
   ```bash
   # Example ~/.env_tokens content:
   export GOOGLE_AI_API_KEY="your_actual_key_here"
   export CF_API_TOKEN="your_actual_token_here"
   export GITHUB_TOKEN="your_github_token_here"
   ```

3. **The tokens are automatically loaded in your shell via .bashrc**

## 🛡️ Security Features

- **Pre-commit hook**: Automatically scans for potential secrets before commits
- **Security scanner**: `.scripts/check-secrets.sh` detects common token patterns
- **Gitignore**: Sensitive files are excluded from git tracking
- **Example templates**: `.env.example` shows the format without real values

## 🚨 If you accidentally commit a secret:

1. **Rotate the token immediately** (generate a new one)
2. **Remove from git history** (if recently committed)
3. **Update your ~/.env_tokens** with the new token

## 📋 Token Rotation Checklist

When you rotate API tokens:
- [ ] Generate new token from provider
- [ ] Update `~/.env_tokens` with new value
- [ ] Test that services still work
- [ ] Revoke old token from provider
- [ ] Update any backup gists with new values

## 🔍 Manual Security Check

Run the security scanner manually:
```bash
.scripts/check-secrets.sh
```