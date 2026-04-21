# ADR-002: Use Rust CLI tools over POSIX defaults

**Status:** Accepted  
**Date:** 2026-04-21

## Decision

Replace legacy POSIX tools with Rust equivalents. This applies to all scripts,
shell usage, and AI agent tool calls.

| Legacy | Replacement | Notes |
|--------|-------------|-------|
| `grep` | `rg` (ripgrep) | |
| `ls` | `lsd` | |
| `cat` | `bat` | |
| `sed` | `sd` | |
| `find` | `fd` | |
| `ps` | `procs` | |
| `du` | `dust` | |
| `top` | `bottom` | |
| `diff` | `delta` | via git |

Linting and formatting:

| Task | Tool |
|------|------|
| Nix format | `alejandra` |
| Shell format | `shfmt` |
| Shell lint | `shellcheck` |
| Fast lint | `oxlint` |
| Changelog | `git-cliff` |

## Consequences

- Scripts that shell out to `grep`, `cat`, `sed` etc. must be updated on sight.
- AI agents using Bash tool calls must use the Rust equivalents.
- All tools are available via the Nix flake — no separate install required.
