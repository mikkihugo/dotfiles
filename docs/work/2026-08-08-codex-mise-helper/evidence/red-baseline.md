# RED baseline — 2026-08-08

Observed from the isolated worktree before any implementation changes:

    config/mise/config.toml:2:"aqua:openai/codex" = "latest"
    RED baseline: no declared mise reshim path
    RED baseline: mise-auto-update PATH omits Nix Node

The checks were read-only:

    rg -n '^"aqua:openai/codex" = "latest"$' config/mise/config.toml
    rg -q 'mise reshim' justfile scripts/repo-maintenance.sh home/modules/mise-auto-update.nix
    rg -q '\$\{pkgs\.nodejs\}/bin' home/modules/mise-auto-update.nix

This is stale-proof evidence only. The implementation must add the named
contract-test assertions before changing the production configuration.
