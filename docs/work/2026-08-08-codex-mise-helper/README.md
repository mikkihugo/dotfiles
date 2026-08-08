# Work: 2026-08-08-codex-mise-helper

Status: planned. The JSON contract and work spec are authoritative. Admission
remains proposed; this planning lane must not activate Home Manager or modify
the live mise installation.

## Observed baseline

- config/mise/config.toml selects aqua:openai/codex at latest.
- The observed Aqua Codex 0.147.0 install does not include
  codex-code-mode-host; the npm package layout does.
- The just recipe, maintenance script, and systemd service install and upgrade
  mise tools but do not reshim.
- The systemd service PATH does not include the declared Nix Node runtime.
- scripts/test-nix-tooling.mjs currently proves only install and upgrade for
  the updater; it does not prove provider choice, Node availability, or reshim.

## Implementation plan

1. Add the focused static assertions in scripts/test-nix-tooling.mjs first and
   capture their expected failure against this baseline.
2. Replace only the Codex registry key in config/mise/config.toml with
   npm:@openai/codex at latest.
3. Amend justfile, scripts/repo-maintenance.sh, and
   home/modules/mise-auto-update.nix so each path runs install, upgrade, then
   reshim. Add the Nix Node bin path to the service process PATH.
4. Run the focused test and the declared repository check. Build the Home
   Manager activation package before an authorized switch.
5. After the authorized switch, run mise install and mise reshim, then prove
   the managed Codex wrapper version and the executable code-mode helper in the
   active npm install. Preserve this output as runtime evidence.
6. Run review and publish through the dotfiles repo facade only after the work
   packet validates with completion evidence.

## Scope

The implementation is limited to the five source/test files listed in
work.spec.json and this packet. It does not alter config/codex, the Codex
wrapper, flake.nix, other mise tools, or live host state during planning.

This repository has docs/work packets but no docs/plans directory convention,
so this README is the executable implementation plan.

## Planning validation

The Purpose MCP scaffold_work and validate_work calls were attempted against
this isolated worktree and both returned:

    Target is outside allowed roots: /home/mhugo/.dotfiles-worktrees/codex-mise-helper-pdd

The packet is therefore intentionally still proposed and not execution
authorized. Local structural validation did pass: all three JSON files parse,
the snapshot raw-byte digest is bound in work.spec.json, the contract and work
IDs link, and the four requirements and five planned implementation files are
present. An implementation owner must either make the Purpose server admit this
dotfiles worktree root or validate the same packet through an approved
workspace-aware path before changing configuration.
