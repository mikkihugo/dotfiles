#!/bin/bash
#
# Aider + RAG Setup
# Purpose: Configure Aider with proper RAG support for large codebases
# Version: 1.0.0

set -euo pipefail

# Setup aichat configuration for Aider
setup_aichat_config() {
    mkdir -p ~/.config/aichat
    
    cat > ~/.config/aichat/config.yaml << 'EOF'
# AIChat configuration for use with Aider

# Model settings
model: claude-3-opus
temperature: 0.7

# RAG settings
rag:
  enabled: true
  embedding_model: text-embedding-3-small
  chunk_size: 2000
  chunk_overlap: 200
  top_k: 10
  
  # Vector store
  vector_store:
    type: chroma
    persist_directory: .aichat/vectors
    
  # File patterns to index
  include_patterns:
    - "**/*.py"
    - "**/*.js"
    - "**/*.ts"
    - "**/*.jsx"
    - "**/*.tsx"
    - "**/*.go"
    - "**/*.rs"
    - "**/*.java"
    - "**/*.cpp"
    - "**/*.c"
    - "**/*.h"
    - "**/*.md"
    - "**/*.yml"
    - "**/*.yaml"
    - "**/*.json"
    - "**/Dockerfile"
    
  exclude_patterns:
    - "**/node_modules/**"
    - "**/.git/**"
    - "**/dist/**"
    - "**/build/**"
    - "**/__pycache__/**"
    - "**/*.min.js"
    - "**/vendor/**"

# Roles
roles:
  - name: coder
    description: "Expert programmer with deep codebase knowledge via RAG"
    prompt: |
      You are an expert programmer with access to the entire codebase through RAG.
      Use the indexed code knowledge to provide accurate, context-aware assistance.
      Always reference specific files and line numbers when discussing code.
      Consider the project structure and dependencies in your responses.

  - name: architect  
    description: "System architect with holistic codebase understanding"
    prompt: |
      You are a system architect with comprehensive knowledge of the codebase via RAG.
      Focus on design patterns, architecture decisions, and system-wide implications.
      Use the indexed knowledge to understand relationships between components.
      Suggest improvements that align with the existing architecture.
EOF
}

# Create Aider wrapper that uses aichat
create_aider_wrapper() {
    cat > /usr/local/bin/aider-rag << 'EOF'
#!/bin/bash
#
# Aider with RAG support via aichat
#

WORKSPACE="${AIDER_WORKSPACE:-/workspace}"
RAG_INDEX="$WORKSPACE/.aichat/vectors"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if we need to index the codebase
if [ ! -d "$RAG_INDEX" ] || [ -n "${FORCE_REINDEX:-}" ]; then
    echo -e "${YELLOW}Indexing codebase for RAG...${NC}"
    
    # Count files to index
    file_count=$(find "$WORKSPACE" \
        -type f \
        \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" \
           -o -name "*.rs" -o -name "*.java" -o -name "*.cpp" -o -name "*.c" \
           -o -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        -not -path "*/dist/*" \
        -not -path "*/build/*" \
        2>/dev/null | wc -l)
    
    echo "Found $file_count files to index..."
    
    # Run indexing
    cd "$WORKSPACE"
    aichat --role coder --rag-index . --rag-chunk-size 2000 --rag-chunk-overlap 200
    
    echo -e "${GREEN}✓ Indexing complete!${NC}"
fi

# Setup environment for aichat integration
export AICHAT_ENABLE_RAG=true
export AICHAT_RAG_VECTOR_STORE="$RAG_INDEX"
export AICHAT_ROLE="coder"

# Create a custom editor command that queries RAG
cat > /tmp/aider-rag-query << 'SCRIPT'
#!/bin/bash
# Query RAG before making edits
query="$1"
context=$(aichat --role coder --rag-query "$query" 2>/dev/null | head -20)
echo "# RAG Context for: $query"
echo "$context"
echo "---"
SCRIPT
chmod +x /tmp/aider-rag-query

# Start aider with enhanced context
echo -e "${BLUE}Starting Aider with RAG support...${NC}"
echo -e "${YELLOW}Tips:${NC}"
echo "  • Use /add to add files based on RAG search"
echo "  • Use /ask to query the codebase"
echo "  • RAG index at: $RAG_INDEX"
echo ""

# Launch aider with architect mode and custom settings
exec aider \
    --architect \
    --model claude-3-opus-20240229 \
    --edit-format diff \
    --auto-commits false \
    --dirty-commits false \
    --pretty true \
    --stream true \
    --map-tokens 2048 \
    --cache-prompts \
    --env-file <(cat <<ENV
AIDER_QUERY_CMD=/tmp/aider-rag-query
AIDER_CONTEXT_WINDOW=200000
AIDER_HISTORY_WINDOW=20
ENV
) "$@"
EOF
    
    chmod +x /usr/local/bin/aider-rag
}

# Create indexing script
create_indexing_script() {
    cat > /usr/local/bin/index-codebase << 'EOF'
#!/bin/bash
#
# Index codebase for RAG
#

echo "🔍 Codebase Indexing Tool"
echo ""

case "${1:-index}" in
    index)
        echo "Indexing current directory..."
        aichat --role coder --rag-index . \
            --rag-chunk-size "${CHUNK_SIZE:-2000}" \
            --rag-chunk-overlap "${CHUNK_OVERLAP:-200}"
        echo "✓ Indexing complete"
        ;;
        
    search)
        shift
        echo "Searching for: $*"
        aichat --role coder --rag-query "$*"
        ;;
        
    stats)
        if [ -d ".aichat/vectors" ]; then
            echo "Index statistics:"
            du -sh .aichat/vectors
            find .aichat/vectors -type f | wc -l | xargs echo "Vector files:"
        else
            echo "No index found. Run 'index-codebase index' first."
        fi
        ;;
        
    clean)
        echo "Removing index..."
        rm -rf .aichat/vectors
        echo "✓ Index removed"
        ;;
        
    *)
        echo "Usage: index-codebase {index|search|stats|clean}"
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/index-codebase
}

# Setup function for Docker container
setup_in_container() {
    echo "🚀 Setting up Aider + RAG in container..."
    
    # Install dependencies
    pip install --no-cache-dir \
        aider-chat \
        chromadb \
        sentence-transformers \
        tiktoken
    
    # Setup configurations
    setup_aichat_config
    create_aider_wrapper
    create_indexing_script
    
    echo "✅ Setup complete!"
    echo ""
    echo "Usage:"
    echo "  aider-rag     - Start Aider with RAG support"
    echo "  index-codebase - Manage codebase indexing"
    echo "  aichat        - Direct RAG queries"
}

# Main execution
main() {
    case "${1:-setup}" in
        setup)
            setup_in_container
            ;;
        config)
            setup_aichat_config
            ;;
        wrapper)
            create_aider_wrapper
            ;;
        *)
            echo "Usage: $0 {setup|config|wrapper}"
            ;;
    esac
}

main "$@"