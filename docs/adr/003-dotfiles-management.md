# ADR-003: All home config changes go through the dotfiles repo

**Status:** Accepted  
**Date:** 2026-04-21

## Decision

The dotfiles repo at `~/.dotfiles` (`github.com/mikkihugo/dotfiles`) is the
single source of truth for all user-space configuration.

**Rules:**

1. Every change to a home config file is committed immediately — no local-only
   edits that drift from the repo.
2. Before editing any file under `$HOME`, check whether it is already managed:
   ```bash
   ls -la ~/.bashrc   # symlink arrow → means managed
   ```
   If not managed, move it into dotfiles and symlink it first.
3. Commit command: `git -C ~/.dotfiles add <file> && git commit && git push`
4. Home Manager (`hms`) is the activation mechanism — it applies the full
   generation atomically. Never manually edit files that `hms` owns.

**Forbidden file naming** (use git history, not filename suffixes):

- `_enhanced`, `_improved`, `_better`, `_v2`, `_new`, `_old`
- Examples of forbidden names: `config_v2.nix`, `shell_new.nix`, `packages_better.nix`

## Consequences

- Dirty working tree in `~/.dotfiles` is always a signal that something needs
  to be committed or reverted — never left as "work in progress".
- AI agents must commit changes to dotfiles files before reporting the task done.
