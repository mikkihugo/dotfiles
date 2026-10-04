# Dotfiles review fixes

Status: implemented
Owner: codex
Last verified: 2026-10-04
Source: operator request and read-only review findings
Canonical issue/ADR/spec: docs/work/2026-10-04-dotfiles-review-fixes/

Purpose: restore the dotfiles review contract without disturbing unrelated user edits.
Consumer: dotfiles operators, Home Manager activation, OpenCode, Codex, and repository gates.

Tasks:

1. Move Exa authentication into SOPS and inject it only through the OpenCode wrapper.
2. Align Luna model declarations and contract tests with `gpt-6.1-luna`.
3. Make the Nix build gate dirty-tree aware and harden rollout/search cleanup inputs.
4. Expand shell lint coverage and raise Starship's command timeout.
5. Run focused tests, the full repository gate, and inspect the final diff.

Non-goals: rotating the exposed Exa credential, changing unrelated existing worktree edits, or publishing/landing the branch.

Status: implemented
