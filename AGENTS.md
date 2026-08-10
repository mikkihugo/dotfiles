# .dotfiles — Agent Guide

NixOS/home-manager config for mikki-laptop and mikki-bunker. Read this
before making non-trivial changes.

## Applying changes

- Bare `home-manager switch` recurses — always use the flake target:
  `home-manager switch --flake .#mikki-laptop` (or `.#mikki-bunker` on the
  bunker host). This is a known footgun, not a style preference.
- Enter the managed toolchain first: `nix develop` (or `direnv allow`).
- Bump tool versions by editing `flake.nix` and committing the updated
  `flake.lock` (`nix flake update`).

## Structure

- `config/` mirrors `$HOME` destinations, linked via `profiles/<name>/links.json`.
- `bootstrap/` is the install entrypoint (`install.sh` forwards to it).
- `tasks/run` dispatches maintenance helpers under `tasks/scripts/`.
- New files go under `config/` and get linked through a profile manifest —
  don't hand-symlink into `$HOME`.

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
