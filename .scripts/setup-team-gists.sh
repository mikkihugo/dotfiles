#!/bin/bash

# Setup Team Gists - Proper separation of team vs personal configs

set -e

echo "🔐 Setting up team/personal gist separation..."

# Check if team gist ID provided
if [ -z "$1" ]; then
    echo "Usage: $0 <TEAM_GIST_ID>"
    echo ""
    echo "This script separates team configs from personal tokens"
    echo "Ask your team lead for the TEAM_GIST_ID"
    exit 1
fi

TEAM_GIST_ID="$1"
PERSONAL_TOKENS_FILE="$HOME/.env_tokens"
TEAM_CONFIG_FILE="$HOME/.team-config"

# 1. Download team config
echo "📥 Downloading team config..."
gh gist view "$TEAM_GIST_ID" -f team-config.sh > "$TEAM_CONFIG_FILE.tmp" 2>/dev/null || {
    echo "❌ Failed to download team gist. Check the ID: $TEAM_GIST_ID"
    exit 1
}

# Verify it's actually team config (not someone's personal tokens)
if grep -q "GITHUB_TOKEN\|OPENAI_API_KEY\|AWS_ACCESS_KEY" "$TEAM_CONFIG_FILE.tmp"; then
    echo "⚠️  WARNING: Team gist contains personal tokens!"
    echo "This is a security risk. Please fix the team gist."
    rm "$TEAM_CONFIG_FILE.tmp"
    exit 1
fi

mv "$TEAM_CONFIG_FILE.tmp" "$TEAM_CONFIG_FILE"
echo "✅ Team config downloaded"

# 2. Extract gateway info from team config
source "$TEAM_CONFIG_FILE"
echo "🌐 Gateway URL: ${TABBY_GATEWAY_URL:-Not set}"

# 3. Create/update personal tokens file
if [ ! -f "$PERSONAL_TOKENS_FILE" ]; then
    echo "📝 Creating personal tokens file..."
    cat > "$PERSONAL_TOKENS_FILE" << EOF
# Personal tokens - DO NOT SHARE
# This file should be in YOUR personal gist only

# Link to team config
export TEAM_GIST_ID="$TEAM_GIST_ID"

# Your personal tokens (add as needed)
export GITHUB_TOKEN=""
export OPENAI_API_KEY=""
export ANTHROPIC_API_KEY=""

# Add other personal tokens below
EOF
    echo "✅ Created template at $PERSONAL_TOKENS_FILE"
    echo "⚠️  Add your personal tokens to this file"
else
    # Just update team gist ID
    if ! grep -q "TEAM_GIST_ID" "$PERSONAL_TOKENS_FILE"; then
        echo "" >> "$PERSONAL_TOKENS_FILE"
        echo "# Link to team config" >> "$PERSONAL_TOKENS_FILE"
        echo "export TEAM_GIST_ID=\"$TEAM_GIST_ID\"" >> "$PERSONAL_TOKENS_FILE"
    fi
fi

# 4. Create/update personal gist
echo ""
echo "🔒 Personal gist setup:"
if [ -n "$PERSONAL_GIST_ID" ]; then
    echo "Updating existing personal gist..."
    gh gist edit "$PERSONAL_GIST_ID" "$PERSONAL_TOKENS_FILE"
else
    echo "Creating new personal gist..."
    PERSONAL_GIST_ID=$(gh gist create "$PERSONAL_TOKENS_FILE" --desc "Personal tokens - $(whoami)@$(hostname)" | grep -oE '[a-f0-9]{32}')
    echo "export PERSONAL_GIST_ID=\"$PERSONAL_GIST_ID\"" >> "$PERSONAL_TOKENS_FILE"
    echo "✅ Created personal gist: $PERSONAL_GIST_ID"
fi

# 5. Update .bashrc to source both files
if ! grep -q "team-config" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Team and personal configs" >> ~/.bashrc
    echo '[ -f ~/.team-config ] && source ~/.team-config' >> ~/.bashrc
    echo '[ -f ~/.env_tokens ] && source ~/.env_tokens' >> ~/.bashrc
fi

# 6. Create sync script
cat > ~/.dotfiles/.scripts/sync-team-personal.sh << 'EOF'
#!/bin/bash
# Sync both team and personal configs

echo "🔄 Syncing configs..."

# Sync team config
if [ -n "$TEAM_GIST_ID" ]; then
    echo "📥 Updating team config..."
    gh gist view "$TEAM_GIST_ID" -f team-config.sh > ~/.team-config
fi

# Sync personal tokens
if [ -n "$PERSONAL_GIST_ID" ]; then
    echo "📥 Updating personal tokens..."
    gh gist view "$PERSONAL_GIST_ID" -f .env_tokens > ~/.env_tokens
fi

echo "✅ Sync complete"
EOF
chmod +x ~/.dotfiles/.scripts/sync-team-personal.sh

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Summary:"
echo "  Team config: ~/.team-config (from gist: $TEAM_GIST_ID)"
echo "  Personal tokens: ~/.env_tokens (your private gist)"
echo ""
echo "🔐 Security reminders:"
echo "  - NEVER put personal tokens in team gist"
echo "  - NEVER share your personal gist ID"
echo "  - Keep ~/.env_tokens in .gitignore"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.env_tokens and add your personal tokens"
echo "  2. Run: source ~/.team-config && source ~/.env_tokens"