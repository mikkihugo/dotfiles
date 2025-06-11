#!/bin/bash
# Test gum compatibility in current environment

echo "🔍 Gum Environment Test"
echo "======================="

echo "1. TTY Status:"
if tty >/dev/null 2>&1; then
    echo "   ✅ Real TTY: $(tty)"
else
    echo "   ❌ Not a TTY (this is the problem!)"
fi

echo ""
echo "2. Terminal Info:"
echo "   TERM: $TERM"
echo "   SSH_CLIENT: ${SSH_CLIENT:-'not set'}"
echo "   SSH_TTY: ${SSH_TTY:-'not set'}"

echo ""
echo "3. File Descriptors:"
[ -t 0 ] && echo "   ✅ stdin is a TTY" || echo "   ❌ stdin is not a TTY"
[ -t 1 ] && echo "   ✅ stdout is a TTY" || echo "   ❌ stdout is not a TTY"
[ -t 2 ] && echo "   ✅ stderr is a TTY" || echo "   ❌ stderr is not a TTY"

echo ""
echo "4. Device Access:"
[ -c /dev/tty ] && echo "   ✅ /dev/tty exists" || echo "   ❌ /dev/tty missing"
if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    echo "   ✅ /dev/tty is readable/writable"
else
    echo "   ❌ /dev/tty permission issue"
fi

echo ""
echo "5. Gum Test:"
if command -v gum >/dev/null 2>&1; then
    echo "   ✅ Gum is installed"
    echo "   Testing simple choose..."
    if echo "test" | timeout 2 gum choose "option1" "option2" >/dev/null 2>&1; then
        echo "   ✅ Gum works!"
    else
        echo "   ❌ Gum fails (expected in non-TTY environments)"
    fi
else
    echo "   ❌ Gum not found"
fi

echo ""
echo "💡 Recommendation:"
if tty >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
    echo "   Use gum - full TTY support detected"
else
    echo "   Use fallback menu - no real TTY available"
    echo "   This is normal in: Claude Code, CI/CD, Docker, etc."
fi