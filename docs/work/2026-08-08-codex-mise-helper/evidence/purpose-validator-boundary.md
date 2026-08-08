# Purpose validator boundary — 2026-08-08

Both Purpose MCP calls were directed at:

    /home/mhugo/.dotfiles-worktrees/codex-mise-helper-pdd

and returned:

    Target is outside allowed roots: /home/mhugo/.dotfiles-worktrees/codex-mise-helper-pdd

The affected calls were scaffold_work and validate_work with
require_evidence=false. No fallback wrote into the shared ~/.dotfiles checkout.

The packet remains proposed. A workspace-aware Purpose validation route or an
allowlist extension is required before it can become execution-authorized.
