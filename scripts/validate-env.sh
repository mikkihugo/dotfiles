#\!/bin/bash
echo "🔍 Environment Validation"
echo "========================"
echo ""

# Check if tokens are loaded
echo "1️⃣ Token Check:"
[ -n "$GITHUB_TOKEN" ] && echo "✅ GITHUB_TOKEN: ${GITHUB_TOKEN:0:20}..." || echo "❌ GITHUB_TOKEN not set"
[ -n "$OPENROUTER_API_KEY" ] && echo "✅ OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:0:20}..." || echo "❌ OPENROUTER_API_KEY not set"
[ -n "$GOOGLE_AI_API_KEY" ] && echo "✅ GOOGLE_AI_API_KEY: ${GOOGLE_AI_API_KEY:0:20}..." || echo "❌ GOOGLE_AI_API_KEY not set"
[ -n "$OPENAI_API_KEY" ] && echo "✅ OPENAI_API_KEY: ${OPENAI_API_KEY:0:20}..." || echo "❌ OPENAI_API_KEY not set"
[ -n "$TAVILY_API_KEY" ] && echo "✅ TAVILY_API_KEY: ${TAVILY_API_KEY:0:20}..." || echo "❌ TAVILY_API_KEY not set"

echo ""
echo "2️⃣ Mise Check:"
which mise >/dev/null && echo "✅ mise is available" || echo "❌ mise not found"

echo ""
echo "3️⃣ Starship Check:"
which starship >/dev/null && echo "✅ starship is available" || echo "❌ starship not found"

echo ""
echo "4️⃣ Test aichat models:"
aichat --list-models 2>&1  < /dev/null |  head -5

echo ""
echo "5️⃣ Test GitHub CLI:"
gh auth status 2>&1 | head -2

echo ""
echo "💡 To reload: source ~/.bashrc"
echo "💡 To test aichat: mise run aichat -m github:phi-3.5-mini-instruct \"Hello\""

