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

## Completed live proof

- The direct underlying Home Manager binary activated the exact worktree flake
  as generation 309. The prior generation 308 remains evidence only of the
  rejected, primary-checkout activation path.
- The mutable root config now has `model = "gpt-5.6-sol"` and
  `model_provider = "openai"`; its unrelated preference fields remain present.
- The resident directory now contains only `default`, `taxonomy-worker`,
  `taxonomy-validator`, and `singularity-engine-harvester`, all OpenAI-backed.
  Every retired gateway symlink is absent.
- All five `external-*.config.toml` profiles are Home Manager symlinks outside
  the resident directory. Each has `model_provider = "llm-gateway"` and
  `web_search = "disabled"`; only the catalog-supported DeepSeek profile pins
  `model_reasoning_effort = "high"`.
- The resulting managed wrapper was executed with a harmless fake underlying
  binary. It forwarded `--flake VALUE`, `--flake=VALUE`, `-f VALUE`, and
  `-fVALUE` unchanged, including following options, and injected no primary
  checkout flake in any explicit-flake case.
