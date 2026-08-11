# .dotfiles — Agent Guide

NixOS/home-manager config for mikki-laptop and mikki-bunker. Read this
before making non-trivial changes.

## Applying changes

- Bare `home-manager switch` recurses — always use the flake target:
  `home-manager switch --flake .#<host>`. This is a known footgun, not a style
  preference. Targets are `mikki-laptop` (aarch64 laptop), `mikki-bunker`
  (x86_64 WSL2 GPU host), `cc-se-sto-devbox-01` (x86_64 fleet devbox), and
  `mhugo` (generic x86_64 fallback) — see `homeConfigurations` in `flake.nix`,
  which is authoritative if this list drifts.
- Enter the managed toolchain first: `nix develop` (or `direnv allow`).
- Bump tool versions by editing `flake.nix` and committing the updated
  `flake.lock` (`nix flake update`).

## Structure

- `config/` mirrors `$HOME` destinations, linked via `profiles/<name>/links.json`.
- `bootstrap/` is the install entrypoint (`install.sh` forwards to it).
- `tasks/run` dispatches maintenance helpers under `tasks/scripts/`.
- New files go under `config/` and get linked through a profile manifest —
  don't hand-symlink into `$HOME`.

## Agent memory

Coding clients do not keep their own memory. Durable agent memory lives in the
`repo_memory` bank reached through the CentralCloud MCP gateway, because a
per-client store is invisible to every other client: a fact learned in Codex is
re-learned or contradicted in Claude Code, Cursor, or Qoder, and nothing
supersedes, retains, or purges across them.

Enforced here:

- **Codex** — `[features] memories = false` plus `[memories] use_memories` /
  `generate_memories = false`. These live in `config/codex/shared-preferences.toml`
  (re-applied to the mutable `~/.codex/config.toml` on every activation) as well
  as `config/codex/config.toml` (seeded once). Both are needed: Codex rewrites
  its own config, so a seed-only setting does not survive.
- **Qoder** — `autoMemoryEnabled: false`, written by the MCP merge block in
  `home/modules/activation.nix`.

Not enforced here, and why:

- **Claude Code** has no per-feature auto-memory switch. `--bare` would disable
  it but also disables hooks, which is how the swarm bus is wired — so it is the
  wrong instrument. Doctrine (retain to `repo_memory`, not
  `~/.claude/projects/*/memory/`) is the control.
- **Factory** has no auto-memory store; `cli-hints.json` is UI throttle state.
- **Cursor** and **Antigravity** knobs are unverified — do not claim they are
  disabled. Cursor's `ai-tracking` DB is attribution telemetry and Antigravity's
  `brain/<uuid>` is per-conversation scratch (1:1 with `conversations/<uuid>`),
  so neither is cross-session memory in the first place.

Never classify `rules/`, `skills/`, `prompts/`, `AGENTS.md`, or `CLAUDE.md` as
memory — including `~/.codex/memories/skills/`, which is the authored
instruction plane despite its path. Disabling memory never means deleting them.

## Secrets

- Encrypted with SOPS + age. Key at `~/.config/sops/age/keys.txt`, config
  at `.sops.yaml`, secrets at `secrets/api-keys.yaml`.
- Edit via `sops secrets/api-keys.yaml` (opens decrypted in `$EDITOR`, re-encrypts
  on save). Never hand-edit or commit decrypted secret content.
- `.env` files use the `sops-env` wrapper (`encrypt`/`edit` subcommands),
  not raw `sops`.

## LLM fabric

Embedding-worker / inference-fabric workloads belong on mikki-bunker
(GPU) only — mikki-laptop is aarch64 with no GPU. Don't propose running
them there.
