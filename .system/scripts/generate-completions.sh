#!/bin/bash
# Generate shell completions for various tools

COMPLETION_DIR="$HOME/.dotfiles/.scripts/completions"
mkdir -p "$COMPLETION_DIR"

echo "🔧 Generating shell completions..."

# Tools that support completion generation
declare -A TOOLS=(
    ["zellij"]="setup --generate-completion bash"
    ["gh"]="completion -s bash"
    ["mise"]="completion bash"
    ["starship"]="completions bash"
    ["zoxide"]="init bash --cmd cd"
    ["rg"]="--generate=complete-bash"
    ["fd"]="--gen-completions bash"
    ["eza"]="--completions bash"
    ["bat"]="--generate-completion bash"
    ["delta"]="--generate-completion bash"
    ["gitui"]="--completions bash"
    ["lazygit"]="completion bash"
    ["k9s"]="completion bash"
    ["kubectl"]="completion bash"
    ["helm"]="completion bash"
    ["docker"]="completion bash"
)

# Generate completions
for tool in "${!TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✓ Generating completion for $tool..."
        eval "$tool ${TOOLS[$tool]}" > "$COMPLETION_DIR/${tool}.bash" 2>/dev/null || {
            echo "    ⚠️  Failed to generate completion for $tool"
            rm -f "$COMPLETION_DIR/${tool}.bash"
        }
    fi
done

# Create a master completion loader
cat > "$COMPLETION_DIR/load-completions.bash" << 'EOF'
# Load all completions
COMPLETION_DIR="$(dirname "${BASH_SOURCE[0]}")"

# Load individual completion files
for completion in "$COMPLETION_DIR"/*.bash; do
    if [[ -f "$completion" && "$completion" != */load-completions.bash ]]; then
        source "$completion"
    fi
done
EOF

echo "✅ Completions generated in $COMPLETION_DIR"
echo "   Add this to your .bashrc:"
echo "   source $COMPLETION_DIR/load-completions.bash"