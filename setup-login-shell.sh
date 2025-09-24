#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZPROFILE="$HOME/.zprofile"
BLOCK_START="# >>> dotfiles nix shell >>>"
BLOCK_END="# <<< dotfiles nix shell <<<"

if ! command -v nix >/dev/null 2>&1; then
  echo "❌ Nix is not installed. Install it from https://nixos.org/download.html (multi-user recommended) and re-run." >&2
  exit 1
fi

ZSH_PATH="$(command -v zsh || true)"
if [ -z "$ZSH_PATH" ]; then
  echo "❌ zsh not found on PATH. Enter 'nix develop' (or install zsh) and run again." >&2
  exit 1
fi

if ! grep -Fxq "$ZSH_PATH" /etc/shells; then
  echo "➕ Adding $ZSH_PATH to /etc/shells"
  echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
  echo "⚙️  Setting login shell to $ZSH_PATH"
  chsh -s "$ZSH_PATH"
fi

if [ -f "$ZPROFILE" ] && grep -Fq "$BLOCK_START" "$ZPROFILE"; then
  echo "ℹ️  Updating existing nix shell block in $ZPROFILE"
  tmp_file="$(mktemp)"
  awk -v start="$BLOCK_START" -v end="$BLOCK_END" 'BEGIN{skip=0} {
    if ($0 == start) { skip=1 }
    if (!skip) { print }
    if ($0 == end) { skip=0 }
  }' "$ZPROFILE" > "$tmp_file"
  mv "$tmp_file" "$ZPROFILE"
fi

touch "$ZPROFILE"
cat <<EOF >> "$ZPROFILE"

$BLOCK_START
if [ -z "\${DOTFILES_NIX_AUTOSTART-}" ] \
   && [ -t 0 ] && [ -t 1 ] \
   && [ -f "$ROOT_DIR/flake.nix" ]; then
  export DOTFILES_NIX_AUTOSTART=1
  exec nix develop "$ROOT_DIR"#default --command "$ZSH_PATH" -l
fi
$BLOCK_END
EOF

if command -v direnv >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && direnv allow .) || true
fi

echo "🎉 Login shell set to zsh with automatic entry into the dotfiles Nix dev shell."
