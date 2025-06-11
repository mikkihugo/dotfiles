#!/bin/bash
# Reset dotfiles flagfiles for fresh installation

echo "🔄 Resetting dotfiles flags..."

FLAGS=(
    "$HOME/.dotfiles/.system-deps-installed"
    "$HOME/.dotfiles/.last_sync"
    "$HOME/.dotfiles/.remote_hash"
)

for flag in "${FLAGS[@]}"; do
    if [ -f "$flag" ]; then
        echo "🗑️  Removing: $(basename "$flag")"
        rm -f "$flag"
    else
        echo "✅ Already clean: $(basename "$flag")"
    fi
done

echo "✅ All flags reset - next login will run fresh setup!"