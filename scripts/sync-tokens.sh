#\!/bin/bash
# Download latest .env_tokens from gist
echo "📥 Downloading .env_tokens from GitHub gist..."
gh gist view 61a7776d4d278cc1ef57549a7d0f61f8 -r > ~/.env_tokens.tmp
if [ $? -eq 0 ]; then
    mv ~/.env_tokens.tmp ~/.env_tokens
    echo "✅ Updated ~/.env_tokens from gist"
else
    rm -f ~/.env_tokens.tmp
    echo "❌ Failed to download from gist"
fi

