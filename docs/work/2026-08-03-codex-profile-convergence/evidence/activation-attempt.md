# Activation falsifier and fix

The first attempt used the managed `home-manager switch --flake .#cc-se-sto-devbox-01`
wrapper and created Home Manager generation 308, but its live Codex files stayed
on the old primary-checkout configuration. This falsified the assumption that
the wrapper honored the supplied flake.

Cause: `home/modules/shell.nix` unconditionally prepended its own primary
`$HOME/.dotfiles#<profile>` flake before the caller arguments. Home Manager used
that first flake and ignored the intended worktree source.

Fix: retain the primary flake as the no-argument default only. When the caller
passes `--flake VALUE`, `--flake=VALUE`, `-f VALUE`, or `-fVALUE`, forward every
argument unchanged to the underlying Home Manager binary.

The regression starts red in `scripts/test-nix-tooling.mjs`, then checks the
guard, all accepted spellings, default injection, and untouched forwarded
arguments. A direct underlying-binary activation and a real-wrapper readback
are required before publication.
