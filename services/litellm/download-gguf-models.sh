#!/bin/bash
# Download GGUF models for llama.cpp

MODELS_DIR="./models"
mkdir -p "$MODELS_DIR"

echo "🚀 Downloading optimized models for llama.cpp..."

# CodeLlama 7B - Best for code generation (2.7GB)
if [ ! -f "$MODELS_DIR/codellama-7b-instruct.Q4_K_M.gguf" ]; then
    echo "📥 Downloading CodeLlama 7B..."
    wget -O "$MODELS_DIR/codellama-7b-instruct.Q4_K_M.gguf" \
        "https://huggingface.co/TheBloke/CodeLlama-7B-Instruct-GGUF/resolve/main/codellama-7b-instruct.Q4_K_M.gguf"
fi

# Phi-3 Mini (1.4GB) - Fast, efficient
if [ ! -f "$MODELS_DIR/phi-3-mini.Q4_K_M.gguf" ]; then
    echo "📥 Downloading Phi-3 Mini..."
    wget -O "$MODELS_DIR/phi-3-mini.Q4_K_M.gguf" \
        "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf"
fi

# DeepSeek Coder 1.3B (764MB) - Tiny but capable
if [ ! -f "$MODELS_DIR/deepseek-coder-1.3b.Q4_K_M.gguf" ]; then
    echo "📥 Downloading DeepSeek Coder 1.3B..."
    wget -O "$MODELS_DIR/deepseek-coder-1.3b.Q4_K_M.gguf" \
        "https://huggingface.co/TheBloke/deepseek-coder-1.3b-instruct-GGUF/resolve/main/deepseek-coder-1.3b-instruct.Q4_K_M.gguf"
fi

# Embedding model options (choose one)
EMBED_MODEL="${EMBED_MODEL:-minilm}"  # Options: nomic, minilm, gte, bge

case "$EMBED_MODEL" in
  "nomic")
    # Nomic Embed Text v1.5 (274MB) - Highest quality
    if [ ! -f "$MODELS_DIR/nomic-embed-text-v1.5.Q4_K_M.gguf" ]; then
        echo "📥 Downloading Nomic Embed Text v1.5..."
        wget -O "$MODELS_DIR/nomic-embed-text-v1.5.Q4_K_M.gguf" \
            "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.Q4_K_M.gguf"
    fi
    ;;
  "minilm")
    # all-MiniLM-L6-v2 (90MB) - Tiny but effective!
    if [ ! -f "$MODELS_DIR/all-MiniLM-L6-v2.Q4_K_M.gguf" ]; then
        echo "📥 Downloading all-MiniLM-L6-v2 (tiny 90MB)..."
        wget -O "$MODELS_DIR/all-MiniLM-L6-v2.Q4_K_M.gguf" \
            "https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.Q4_K_M.gguf"
    fi
    ;;
  "gte")
    # GTE-Small (130MB) - Good balance
    if [ ! -f "$MODELS_DIR/gte-small.Q4_K_M.gguf" ]; then
        echo "📥 Downloading GTE-Small..."
        wget -O "$MODELS_DIR/gte-small.Q4_K_M.gguf" \
            "https://huggingface.co/thenlper/gte-small-GGUF/resolve/main/gte-small.Q4_K_M.gguf"
    fi
    ;;
  "bge")
    # BGE-Small (130MB) - Great for code
    if [ ! -f "$MODELS_DIR/bge-small-en-v1.5.Q4_K_M.gguf" ]; then
        echo "📥 Downloading BGE-Small..."
        wget -O "$MODELS_DIR/bge-small-en-v1.5.Q4_K_M.gguf" \
            "https://huggingface.co/BAAI/bge-small-en-v1.5-GGUF/resolve/main/bge-small-en-v1.5.Q4_K_M.gguf"
    fi
    ;;
esac

echo "✅ Models ready in $MODELS_DIR"
ls -lh "$MODELS_DIR"