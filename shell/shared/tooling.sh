#!/bin/bash
# Shared interactive tooling hooks

DOTFILES_SHELL=${DOTFILES_SHELL:-bash}

if command -v zoxide >/dev/null 2>&1; then
  case "$DOTFILES_SHELL" in
    bash|zsh|fish)
      eval "$(zoxide init "$DOTFILES_SHELL")"
      ;;
  esac
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init "$DOTFILES_SHELL")"
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook "$DOTFILES_SHELL")"
fi
