#!/bin/bash
#
# Copyright 2024 Mikki Hugo. All rights reserved.
# Licensed under the Apache License, Version 2.0
#
# Security script to check for hardcoded secrets before git commits
# Usage: Run before committing to catch potential secret leaks

echo "🔍 Checking for potential hardcoded secrets..."

# Common patterns for API keys and tokens
SECRET_PATTERNS=(
    "AIza[0-9A-Za-z_-]{35}"                    # Google API keys
    "[a-f0-9]{32}"                             # Generic 32-char hex tokens
    "sk-[a-zA-Z0-9]{48}"                       # OpenAI API keys
    "xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+"        # Slack bot tokens
    "ghp_[a-zA-Z0-9]{36}"                      # GitHub personal access tokens
    "gho_[a-zA-Z0-9]{36}"                      # GitHub OAuth tokens
)

# Variable name patterns that should never have hardcoded values
VAR_PATTERNS=(
    "export.*API_KEY.*="
    "export.*TOKEN.*="
    "export.*SECRET.*="
    "export.*PASSWORD.*="
)

FOUND_ISSUES=0

# Check for secret patterns
for pattern in "${SECRET_PATTERNS[@]}"; do
    if git diff --cached | grep -E "$pattern" >/dev/null 2>&1; then
        echo "❌ Potential hardcoded secret found matching pattern: $pattern"
        git diff --cached | grep -E "$pattern" --color=always
        FOUND_ISSUES=1
    fi
done

# Check for environment variable assignments with potential secrets
for pattern in "${VAR_PATTERNS[@]}"; do
    if git diff --cached | grep -E "$pattern" | grep -v "your_.*_here\|example\|template\|placeholder" >/dev/null 2>&1; then
        echo "❌ Potential hardcoded secret in environment variable:"
        git diff --cached | grep -E "$pattern" --color=always
        FOUND_ISSUES=1
    fi
done

if [ $FOUND_ISSUES -eq 1 ]; then
    echo ""
    echo "🚨 Security check failed! Potential secrets detected."
    echo "   Move secrets to ~/.env_tokens (managed via private gist)"
    echo "   Use environment variables instead of hardcoded values"
    exit 1
else
    echo "✅ No hardcoded secrets detected"
fi