#!/usr/bin/env bash
# Verify the Engine filter keeps this repo's declared inputs and excludes runtime state.
set -euo pipefail
: "${REPOSITORY_OPERATOR_FLAKE_SOURCE_BIN:?set the provisioned absolute Engine helper path}"
case "$REPOSITORY_OPERATOR_FLAKE_SOURCE_BIN" in /*) ;; *) echo 'helper path must be absolute' >&2; exit 1 ;; esac
root=$(cd "$(dirname "$0")/.." && pwd -P)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-source-test.XXXXXX")
mkdir -p "$fixture/.purpose" "$fixture/.nix" "$fixture/.worktrees"
printf '{ outputs = { self }: {}; }\n' > "$fixture/flake.nix"
cp "$root/.purpose/flake-source-policy.v1.json" "$fixture/.purpose/flake-source-policy.v1.json"
for file in .envrc .nix/direnv.sh .secrets.baseline .statix.toml; do printf 'tracked\n' > "$fixture/$file"; done
printf 'runtime\n' > "$fixture/.worktrees/sentinel"
printf 'untracked visible\n' > "$fixture/new-source.nix"
printf 'untracked hidden\n' > "$fixture/.nix/untracked"
git -C "$fixture" init -q
git -C "$fixture" add -f flake.nix .envrc .nix/direnv.sh .secrets.baseline .statix.toml .purpose/flake-source-policy.v1.json .worktrees/sentinel
source_ref=$("$REPOSITORY_OPERATOR_FLAKE_SOURCE_BIN" "$fixture")
case "$source_ref" in path:/nix/store/*) source_dir=${source_ref#path:} ;; *) echo "unexpected source reference: $source_ref" >&2; exit 1 ;; esac
for file in flake.nix new-source.nix .envrc .nix/direnv.sh .secrets.baseline .statix.toml .purpose/flake-source-policy.v1.json; do
  test -f "$source_dir/$file" || { echo "missing expected input: $file" >&2; exit 1; }
done
for file in .worktrees/sentinel .git .nix/untracked; do
  test ! -e "$source_dir/$file" || { echo "unexpected runtime input: $file" >&2; exit 1; }
done
