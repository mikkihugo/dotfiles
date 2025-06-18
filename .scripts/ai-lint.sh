#!/bin/bash
# AI Code Review Script - Detect AI patterns, hallucinations, and issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Usage
if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory|file> [--fix]"
    echo "  --fix    Attempt to fix issues automatically"
    exit 1
fi

TARGET="$1"
FIX_MODE="${2:-}"

echo -e "${YELLOW}🔍 AI Code Review Starting...${NC}"

# 1. Check for package hallucinations
echo -e "\n${YELLOW}1. Checking for hallucinated packages...${NC}"
if command -v rg &>/dev/null; then
    # Common hallucination patterns
    rg -i "import.*(?:enhanced|improved|better|advanced|super|ultra|pro|plus|extended|optimized)[-_]" "$TARGET" || true
    rg -i "require\(['\"].*(?:enhanced|improved|better|advanced).*['\"]" "$TARGET" || true
    
    # Check for non-existent npm packages
    if [ -f "package.json" ]; then
        echo "Verifying npm dependencies..."
        npx npm-check-updates --errorLevel 2 || true
    fi
    
    # Check Python imports
    rg "^(?:from|import)\s+\S+" "$TARGET" -o | sort -u > /tmp/ai-imports.txt || true
    if [ -s /tmp/ai-imports.txt ]; then
        echo "Found imports to verify..."
    fi
fi

# 2. Check for AI code patterns
echo -e "\n${YELLOW}2. Detecting AI-generated patterns...${NC}"
# Look for overly generic variable names
rg -i "\b(data|result|item|obj|val|temp|tmp|thing|stuff)\d*\s*=" "$TARGET" || true

# Look for inconsistent naming
echo "Checking naming consistency..."
rg "(?:camelCase|snake_case|PascalCase)" "$TARGET" -o | sort | uniq -c | sort -rn | head -10 || true

# 3. Security checks
echo -e "\n${YELLOW}3. Security analysis...${NC}"
if command -v semgrep &>/dev/null; then
    semgrep --config=auto "$TARGET" 2>/dev/null || true
else
    # Fallback patterns
    rg -i "(?:api[_-]?key|password|secret|token)\s*=\s*['\"]" "$TARGET" || true
    rg "eval\(|exec\(|system\(" "$TARGET" || true
fi

# 4. Complexity analysis
echo -e "\n${YELLOW}4. Complexity check...${NC}"
if command -v tokei &>/dev/null; then
    tokei "$TARGET" --sort lines
fi

# 5. Use aider for AI review
if command -v aider &>/dev/null; then
    echo -e "\n${YELLOW}5. Running AI-assisted review...${NC}"
    
    # Create review prompt
    cat > /tmp/ai-review-prompt.txt << 'EOF'
Review this code for:
1. AI-generated patterns (generic names, inconsistent style)
2. Package hallucinations (non-existent dependencies)
3. Security vulnerabilities
4. Overly complex or convoluted logic
5. Missing error handling
6. Architectural issues

List issues found with severity (HIGH/MEDIUM/LOW).
Be concise. Focus on real problems, not style preferences.
EOF

    if [ "$FIX_MODE" = "--fix" ]; then
        echo "Running aider in fix mode..."
        aider --lint --yes --model openrouter/mistralai/mistral-7b-instruct:free \
            --message "$(cat /tmp/ai-review-prompt.txt)" "$TARGET"
    else
        echo "Running aider in review mode..."
        aider --lint --no-git --model openrouter/mistralai/mistral-7b-instruct:free \
            --message "$(cat /tmp/ai-review-prompt.txt)" "$TARGET"
    fi
fi

# 6. Traditional linters
echo -e "\n${YELLOW}6. Running traditional linters...${NC}"
if [ -f "package.json" ] && command -v oxlint &>/dev/null; then
    oxlint "$TARGET" || true
elif [ -f "Cargo.toml" ] && command -v cargo &>/dev/null; then
    cargo clippy -- -W clippy::all || true
elif command -v ruff &>/dev/null && [[ "$TARGET" == *.py ]]; then
    ruff check "$TARGET" || true
fi

# 7. Dependency audit
echo -e "\n${YELLOW}7. Dependency audit...${NC}"
if [ -f "package-lock.json" ]; then
    npm audit || true
elif [ -f "Cargo.lock" ]; then
    cargo audit || true
elif [ -f "requirements.txt" ]; then
    pip-audit || true
fi

echo -e "\n${GREEN}✅ AI Code Review Complete${NC}"