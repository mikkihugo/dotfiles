#!/bin/bash
# 🔐 Setup tokens from private gist

GIST_ID="${GIST_ID:-YOUR_GIST_ID_HERE}"  # Set your gist ID here or pass as env var
TOKEN_FILE="$HOME/.env_tokens"

echo "🔐 Setting up environment tokens..."

# Check if gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo "📝 Please authenticate with GitHub first:"
    gh auth login
fi

# Download tokens from gist
echo "⬇️  Downloading tokens from private gist..."
if gh gist view "$GIST_ID" > "$TOKEN_FILE"; then
    echo "✅ Tokens downloaded successfully"
    
    # Source the tokens
    source "$TOKEN_FILE"
    
    # Add to bashrc if not already there
    if ! grep -q "source ~/.env_tokens" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# Auto-load tokens from private gist" >> ~/.bashrc
        echo '[[ -f ~/.env_tokens ]] && source ~/.env_tokens' >> ~/.bashrc
        echo "✅ Added auto-loading to .bashrc"
    fi
    
    echo ""
    echo "🎉 Tokens configured successfully!"
    echo "   GITHUB_TOKEN: ${GITHUB_TOKEN:0:20}..."
    echo "   GITHUB_REPO: $GITHUB_REPO"
    echo ""
    echo "💡 Restart your shell or run: source ~/.env_tokens"
else
    echo "❌ Failed to download tokens"
    echo "   Make sure you have access to gist: $GIST_ID"
    exit 1
fi