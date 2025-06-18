#!/bin/bash
# Find all files that need linting

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Output format (file, json, count)
FORMAT="${1:-file}"

# Temporary file for results
LINT_FILES=$(mktemp /tmp/lint-targets.XXXXXX)
trap "rm -f $LINT_FILES ${LINT_FILES}.filtered" EXIT

echo -e "${YELLOW}🔍 Finding files that need linting...${NC}"

# 1. Find modified files (git)
if [ -d .git ]; then
    echo -e "\n${BLUE}Modified files:${NC}"
    git diff --name-only >> "$LINT_FILES"
    git diff --cached --name-only >> "$LINT_FILES"
    # Untracked files
    git ls-files --others --exclude-standard >> "$LINT_FILES"
fi

# 2. Find source files by extension
echo -e "\n${BLUE}Finding source files...${NC}"

# Define file patterns
declare -A PATTERNS=(
    ["JavaScript"]="-e js -e jsx -e mjs"
    ["TypeScript"]="-e ts -e tsx"
    ["Python"]="-e py -e pyw"
    ["Rust"]="-e rs"
    ["Go"]="-e go"
    ["C/C++"]="-e c -e cpp -e cc -e h -e hpp"
    ["Shell"]="-e sh -e bash -e zsh"
    ["YAML"]="-e yml -e yaml"
    ["JSON"]="-e json"
    ["Markdown"]="-e md -e mdx"
)

# Use fd if available, otherwise find
if command -v fd &>/dev/null; then
    for lang in "${!PATTERNS[@]}"; do
        fd ${PATTERNS[$lang]} -t f >> "$LINT_FILES"
    done
else
    # Fallback to find
    find . -type f \( \
        -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o \
        -name "*.py" -o -name "*.rs" -o -name "*.go" -o \
        -name "*.c" -o -name "*.cpp" -o -name "*.h" -o \
        -name "*.sh" -o -name "*.bash" -o \
        -name "*.yml" -o -name "*.yaml" -o \
        -name "*.json" -o -name "*.md" \
    \) 2>/dev/null >> "$LINT_FILES"
fi

# 3. Remove duplicates and filter
sort -u "$LINT_FILES" | grep -v -E '(node_modules|\.git|dist|build|target|\.cache|vendor)/' > "${LINT_FILES}.filtered"
mv "${LINT_FILES}.filtered" "$LINT_FILES"

# 4. Check which files have lint issues
echo -e "\n${BLUE}Checking for lint issues...${NC}"
PROBLEM_FILES=$(mktemp /tmp/lint-problems.XXXXXX)
trap "rm -f $LINT_FILES ${LINT_FILES}.filtered $PROBLEM_FILES" EXIT

while IFS= read -r file; do
    if [ ! -f "$file" ]; then
        continue
    fi
    
    HAS_ISSUE=false
    
    # Quick checks for common issues
    if rg -q "TODO:|FIXME:|XXX:|HACK:" "$file" 2>/dev/null; then
        HAS_ISSUE=true
    fi
    
    # Check for AI patterns
    if rg -q "enhanced-|improved-|better-|data[0-9]+\s*=|result[0-9]+\s*=" "$file" 2>/dev/null; then
        HAS_ISSUE=true
    fi
    
    # Language-specific checks
    case "$file" in
        *.js|*.jsx|*.ts|*.tsx)
            if command -v oxlint &>/dev/null; then
                if ! oxlint "$file" &>/dev/null; then
                    HAS_ISSUE=true
                fi
            fi
            ;;
        *.py)
            if command -v ruff &>/dev/null; then
                if ! ruff check "$file" &>/dev/null; then
                    HAS_ISSUE=true
                fi
            fi
            ;;
        *.rs)
            if command -v cargo &>/dev/null && [ -f "Cargo.toml" ]; then
                if ! cargo clippy --no-deps -- --forbid warnings &>/dev/null; then
                    HAS_ISSUE=true
                fi
            fi
            ;;
    esac
    
    if [ "$HAS_ISSUE" = true ]; then
        echo "$file" >> "$PROBLEM_FILES"
    fi
done < "$LINT_FILES"

# Output results based on format
case "$FORMAT" in
    json)
        echo "{"
        echo "  \"total_files\": $(wc -l < "$LINT_FILES"),"
        echo "  \"files_with_issues\": $(wc -l < "$PROBLEM_FILES"),"
        echo "  \"files\": ["
        while IFS= read -r file; do
            echo "    \"$file\","
        done < "$PROBLEM_FILES" | sed '$ s/,$//'
        echo "  ]"
        echo "}"
        ;;
    count)
        echo -e "\n${GREEN}Summary:${NC}"
        echo "Total source files: $(wc -l < "$LINT_FILES")"
        echo "Files with issues: $(wc -l < "$PROBLEM_FILES")"
        ;;
    *)
        # Default: output file list
        if [ -s "$PROBLEM_FILES" ]; then
            echo -e "\n${RED}Files needing lint:${NC}"
            cat "$PROBLEM_FILES"
        else
            echo -e "\n${GREEN}✅ No files need linting!${NC}"
        fi
        ;;
esac

# Cleanup
rm -f "$LINT_FILES" "$PROBLEM_FILES"