# Observations

## 2026-07-30 — Engine fabric shell hook depends on caller working directory

- Observed: `nix develop path:/home/mhugo/code/singularity-engine/fabrics/data --command …` fails from an unrelated working directory with `build-cache: cannot locate Engine cache activator`.
- Consumer impact: wrappers that delegate into the Engine fabric must enter `fabrics/data` before starting its development shell.
- Evidence: the pre-activation cargo-pgrx wrapper probe failed from the dotfiles worktree and passed after adding `cd "$flake_dir"`.
- Follow-up owner: `singularity-engine` build-cache shell-hook maintainers; make repository discovery derive from the flake/source path if callers are intended to invoke the shell externally.
- Scope decision: this change only adapts the dotfiles wrapper; it does not modify the read-only Engine checkout.
