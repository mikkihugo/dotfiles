# Gist Structure for Team vs Personal

## PROBLEM: 
If team gist contains personal tokens, everyone sees everyone's private keys!

## SOLUTION: 3-Tier Gist System

### 1. TEAM GIST (Public to team)
```yaml
# gist: team-dotfiles-config
content:
  - gateway_url: ws://51.38.127.98:9000
  - gateway_token: BNgh9981doggy!!  # OK - shared resource
  - ssh_hosts: [shared servers]      # OK - team servers
  - NOT: personal_tokens, api_keys
```

### 2. PERSONAL GIST (Private)
```yaml
# gist: personal-tokens-USERNAME
content:
  - GITHUB_TOKEN: gho_xxx           # Personal
  - OPENAI_API_KEY: sk-xxx         # Personal  
  - AWS_ACCESS_KEY: xxx            # Personal
  - TABBY_GIST_ID: xxx             # Link to team gist
```

### 3. DOTFILES REPO (Public)
```yaml
content:
  - configs, scripts, tools
  - NO tokens or secrets
  - References to gist IDs via env
```

## SETUP FLOW:

```bash
# 1. Team member gets team gist ID
TEAM_GIST_ID=xxx  # Shared via secure channel

# 2. Download team config
gh gist view $TEAM_GIST_ID -f team-config.sh > ~/.team-config
source ~/.team-config

# 3. Create personal gist
cat > ~/.env_tokens << EOF
# Personal tokens
export GITHUB_TOKEN="your-personal-token"
export TEAM_GIST_ID="$TEAM_GIST_ID"
EOF

PERSONAL_GIST_ID=$(gh gist create ~/.env_tokens --desc "Personal tokens - $(whoami)")

# 4. Auto-sync both
~/.dotfiles/.scripts/sync-gists.sh
```

## FILE STRUCTURE:

```
~/.env_tokens          # Personal tokens (from personal gist)
~/.team-config         # Team config (from team gist)
~/.dotfiles/           # Public configs (from GitHub)
```

## SECURITY RULES:

1. **NEVER** put personal tokens in team gist
2. **NEVER** put team gist ID in public repo
3. **ALWAYS** use separate gists per user
4. **ALWAYS** source both files in .bashrc:
   ```bash
   [ -f ~/.team-config ] && source ~/.team-config
   [ -f ~/.env_tokens ] && source ~/.env_tokens
   ```