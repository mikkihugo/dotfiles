# 🔐 Token Setup Instructions

Since this is a **public repository**, tokens must be set up separately on each machine.

## Option 1: Quick Manual Setup
```bash
# After running install.sh, add your tokens:
export GITHUB_TOKEN="your_github_token_here"
export GITHUB_REPO="your_repo_here"
echo "export GITHUB_TOKEN='$GITHUB_TOKEN'" >> ~/.bashrc_local
echo "source ~/.bashrc_local" >> ~/.bashrc
```

## Option 2: Private Gist Method
```bash
# On your main machine:
cat > ~/.env << EOF
GITHUB_TOKEN=your_token_here
GITHUB_REPO=your_repo_here
EOF

# Save to private gist
gh gist create --private ~/.env -d "My environment variables"
# Note the gist ID

# On new machine:
gh auth login  # One-time auth
gh gist view GIST_ID > ~/.env
source ~/.env
```

## Option 3: Secure Sync (Advanced)
Use encrypted file sync service (Keybase, 1Password CLI, etc.)

## Security Notes
- Never commit tokens to public repos
- Use different tokens per machine if needed
- Rotate tokens regularly
- Set token expiration dates