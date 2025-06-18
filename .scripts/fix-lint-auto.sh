#!/bin/bash
# Auto-fix common lint issues without AI

set -e

if [ $# -eq 0 ]; then
    echo "Usage: $0 <file>"
    exit 1
fi

FILE="$1"

echo "🔧 Auto-fixing lint issues in $FILE..."

# Backup original
cp "$FILE" "${FILE}.bak"

# Fix unused parameters - prefix with underscore
# This sed command looks for function parameters that oxlint complains about
echo "Fixing unused parameters..."
sed -i -E 's/function ([a-zA-Z0-9_]+)\(([^)]*)\)/function \1(\2)/' "$FILE" | \
while IFS= read -r line; do
    if [[ "$line" =~ "Parameter '"([a-zA-Z0-9_]+)"' is declared but never used" ]]; then
        param="${BASH_REMATCH[1]}"
        sed -i "s/\b${param}\b/_${param}/g" "$FILE"
    fi
done

# Alternative approach using a temp file
TMPFILE=$(mktemp)

# Get all unused parameters from oxlint
oxlint "$FILE" 2>&1 | grep "Parameter.*is declared but never used" | \
    sed -E "s/.*Parameter '([^']+)'.*/\1/" > "$TMPFILE" || true

# Prefix each unused parameter with underscore
while IFS= read -r param; do
    if [ -n "$param" ]; then
        echo "  Fixing parameter: $param -> _$param"
        # Only replace in function signatures, not in function body
        sed -i -E "s/(function[^(]*\([^)]*)\b${param}\b/\1_${param}/g" "$FILE"
        sed -i -E "s/([(,]\s*)${param}(\s*[,)])/\1_${param}\2/g" "$FILE"
    fi
done < "$TMPFILE"

# Get unused variables
oxlint "$FILE" 2>&1 | grep "Variable.*is declared but never used" | \
    sed -E "s/.*Variable '([^']+)'.*/\1/" > "$TMPFILE" || true

# Comment out or remove unused variables
while IFS= read -r var; do
    if [ -n "$var" ]; then
        echo "  Removing unused variable: $var"
        # Comment out the line with unused variable
        sed -i "/const ${var} =/s/^/\/\/ /" "$FILE"
        sed -i "/let ${var} =/s/^/\/\/ /" "$FILE"
        sed -i "/var ${var} =/s/^/\/\/ /" "$FILE"
    fi
done < "$TMPFILE"

# Fix empty catch blocks
echo "Fixing empty catch blocks..."
sed -i -E 's/catch\s*\([^)]+\)\s*\{\s*\}/catch { \/* Error ignored *\/ }/' "$FILE"

# Fix catch parameters
oxlint "$FILE" 2>&1 | grep "Catch parameter.*is caught but never used" | \
    sed -E "s/.*Catch parameter '([^']+)'.*/\1/" > "$TMPFILE" || true

while IFS= read -r param; do
    if [ -n "$param" ]; then
        echo "  Fixing catch parameter: $param -> _$param"
        sed -i -E "s/catch\s*\(${param}\)/catch(_${param})/g" "$FILE"
    fi
done < "$TMPFILE"

rm -f "$TMPFILE"

# Show results
echo ""
echo "✅ Auto-fix complete!"
echo ""
echo "Remaining issues:"
oxlint "$FILE" 2>&1 || true

echo ""
echo "Diff:"
diff -u "${FILE}.bak" "$FILE" || true

echo ""
echo "Original backed up to: ${FILE}.bak"