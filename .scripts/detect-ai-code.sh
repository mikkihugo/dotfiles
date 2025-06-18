#!/bin/bash
# Detect AI-generated code patterns and hallucinations

# AI Code Smell Patterns
declare -A AI_PATTERNS=(
    # Package hallucinations
    ["enhanced-"]="Package names with 'enhanced-' prefix"
    ["improved-"]="Package names with 'improved-' prefix"
    ["better-"]="Package names with 'better-' prefix"
    ["advanced-"]="Package names with 'advanced-' prefix"
    ["super-"]="Package names with 'super-' prefix"
    
    # Generic variable names
    ["\\bdata[0-9]*\\s*="]="Generic 'data' variables"
    ["\\bresult[0-9]*\\s*="]="Generic 'result' variables"
    ["\\btemp[0-9]*\\s*="]="Generic 'temp' variables"
    ["\\bthing[0-9]*\\s*="]="Generic 'thing' variables"
    
    # AI comment patterns
    ["# TODO: implement"]="Unimplemented TODO comments"
    ["// TODO: implement"]="Unimplemented TODO comments"
    ["Your code here"]="Placeholder code"
    ["Add your logic here"]="Placeholder code"
    
    # Overly verbose comments
    ["# This function"]="Overly obvious comments"
    ["// This method"]="Overly obvious comments"
    ["# Initialize"]="Overly obvious comments"
    
    # Inconsistent error handling
    ["except:\\s*pass"]="Empty exception handlers"
    ["catch.*{\\s*}"]="Empty catch blocks"
    
    # AI hallucination in docs
    ["@param {[^}]*} undefined"]="Undefined parameters in JSDoc"
    ["@returns {void}.*return"]="Void return with actual return"
)

echo "🔍 Scanning for AI-generated code patterns..."
echo "================================================"

TOTAL_ISSUES=0

for pattern in "${!AI_PATTERNS[@]}"; do
    description="${AI_PATTERNS[$pattern]}"
    
    if command -v rg &>/dev/null; then
        count=$(rg -c "$pattern" . 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo ""
            echo "⚠️  $description:"
            rg -n "$pattern" . --max-count=3 2>/dev/null
            echo "   (Found in $count files)"
            ((TOTAL_ISSUES+=count))
        fi
    fi
done

# Check for hallucinated imports
echo ""
echo "🔍 Checking for potentially hallucinated packages..."
echo "================================================"

# Python
if command -v python3 &>/dev/null; then
    rg "^(?:from|import)\s+(\S+)" -o -r '$1' . 2>/dev/null | \
    sort -u | \
    while read -r module; do
        if [[ "$module" =~ (enhanced|improved|better|advanced|super|ultra) ]]; then
            echo "⚠️  Suspicious Python import: $module"
            ((TOTAL_ISSUES++))
        fi
    done
fi

# JavaScript/TypeScript
if [ -f "package.json" ]; then
    rg "(?:import|require).*['\"]([^'\"]+)['\"]" -o -r '$1' . 2>/dev/null | \
    grep -E "(enhanced|improved|better|advanced|super|ultra)" | \
    sort -u | \
    while read -r module; do
        echo "⚠️  Suspicious JS/TS import: $module"
        ((TOTAL_ISSUES++))
    done
fi

# Mixed style detection
echo ""
echo "🔍 Checking for mixed coding styles..."
echo "================================================"

# Count different naming styles
camel_count=$(rg "[a-z][A-Z]" . 2>/dev/null | wc -l)
snake_count=$(rg "[a-z]_[a-z]" . 2>/dev/null | wc -l)
pascal_count=$(rg "^[A-Z][a-zA-Z]*\\s*=" . 2>/dev/null | wc -l)

if [ "$camel_count" -gt 10 ] && [ "$snake_count" -gt 10 ]; then
    echo "⚠️  Mixed naming conventions detected:"
    echo "   camelCase: $camel_count occurrences"
    echo "   snake_case: $snake_count occurrences"
    ((TOTAL_ISSUES++))
fi

# Summary
echo ""
echo "================================================"
if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo "✅ No obvious AI-generated code issues found!"
else
    echo "❌ Found $TOTAL_ISSUES potential AI-generated code issues"
    echo ""
    echo "Recommendations:"
    echo "1. Review and rename generic variables"
    echo "2. Verify all imported packages exist"
    echo "3. Remove placeholder comments and code"
    echo "4. Ensure consistent naming conventions"
    echo "5. Add proper error handling"
fi