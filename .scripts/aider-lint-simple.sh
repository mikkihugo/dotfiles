#!/bin/bash
# Simple aider lint command that works

# Find files and run aider on them
if [ $# -eq 0 ]; then
    echo "Usage: $0 <pattern>"
    echo "Example: $0 '*.js'"
    exit 1
fi

PATTERN="$1"

# Find files with issues
echo "Finding files with pattern: $PATTERN"
files=$(find . -name "$PATTERN" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | head -10)

if [ -z "$files" ]; then
    echo "No files found matching $PATTERN"
    exit 0
fi

echo "Found files:"
echo "$files"
echo ""

# Run aider with minimal config
for file in $files; do
    echo "Processing: $file"
    aider --no-config \
          --model openrouter/mistralai/mistral-7b-instruct:free \
          --openai-api-base https://openrouter.ai/api/v1 \
          --no-auto-commits \
          --message "Review this file for lint issues and fix them" \
          --yes-always \
          "$file"
done