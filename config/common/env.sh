# shellcheck shell=sh
# Common environment variables for all shells
# This file should use POSIX-compatible syntax

# Editor
export EDITOR="hx"
export VISUAL="$EDITOR"

# Pager
export PAGER="bat"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# History
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILESIZE=20000

# Mise/ASDF compatibility
export MISE_SHELL="$SHELL"
export MISE_EXPERIMENTAL=1
# python3 is nixpkgs (Home Manager + flake), not mise. Do not export an
# ecosystem-python flag — that made tools prefer the broken mise interpreter.

# Rust
export CARGO_HOME="$HOME/.cargo"
export RUSTUP_HOME="$HOME/.rustup"

# Go
export GOPATH="$HOME/go"

# FZF
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# Bat theme
export BAT_THEME="OneHalfDark"

# Limit fd threads to prevent runaway processes
export FD_THREADS=4

# GPG
# shellcheck disable=SC2155,SC2046
export GPG_TTY=$(tty)

# XDG Base Directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Add common paths
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.dotfiles/.scripts:$PATH"
export PATH="$CARGO_HOME/bin:$PATH"
export PATH="$GOPATH/bin:$PATH"
