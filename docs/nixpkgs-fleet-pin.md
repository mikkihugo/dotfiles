# Fleet nixpkgs pin (dotfiles consumer)

Dotfiles follows the Engine **one knob** for the fleet-canonical nixpkgs revision
used by Rust toolchain packages on devbox hosts (`cargo-subcommand-proxies`).

## Flake input

The rev is pinned directly in this repo's own flake input:

```nix
nixpkgs.url = "github:NixOS/nixpkgs/6fcc160353f63555b560f25588925133c8f61f2a";
```

That rev is the one Engine publishes: it lives in Engine's `flake.nix` nixpkgs
input and in Engine's `nix/toolchains/versions.json` (`nixpkgs_rev`). Dotfiles
pins it by value instead of consuming a cross-repo flake, because Engine's
separate pin flake (`nix/toolchains/nixpkgs-pin`) was removed on 2026-11-11.
A cross-repo input meant another repo's release cycle decided when this repo
could build — and, once that flake's lock entry had been written from a local
worktree override, the lock pointed at a deleted path and every dotfiles
activation build failed.

Home modules use the dotfiles' own `pkgs` (no separate `nixpkgs-rust` URL):
`cargo-subcommand-proxies` reads `pkgs.rustPackages_1_98`.

## Bump workflow

1. Bump the rev in Engine only: see
   [nix/toolchains/versions.json](https://git.centralcloud.net/singularity/singularity-engine/src/branch/main/nix/toolchains/versions.json)
   (`nixpkgs_rev`, plus Engine's own `flake.nix` nixpkgs input and lock).
2. Refresh dotfiles lock:
   `nix flake lock --update-input nixpkgs`
3. Apply on the host:
   `home-manager switch --flake .#cc-se-sto-devbox-01` (or your profile name).
4. Optional fleet health (Engine): `repo prove nixpkgs-pin` / `bash scripts/se_nixpkgs_fleet_health.sh`.

Keep the dotfiles `flake.nix` rev and Engine's `nixpkgs_rev` in step; they are
the same revision by contract.

## Locking from a working copy

The lock must be written from the working copy, not from a bare `.` reference:

```bash
nix flake lock "path:$HOME/.dotfiles" --update-input nixpkgs
```

A bare `.` resolves through the git fetcher, which only sees tracked files and
fails while a new file (such as the vendored direnv guard) is still untracked.
`path:` covers the whole tree.

## Scheduled apply (optional)

For devbox hosts that should pick up dotfiles commits on a timer without
rewriting the lock on every run:

```nix
# home.nix (example — not enabled by default)
services.home-manager.autoUpgrade = {
  enable = true;
  flake = "path:${config.home.homeDirectory}/.dotfiles";
  flags = [ "--no-update-lock-file" ];
};
```

Use `--no-update-lock-file` so auto-upgrade applies the **committed** pin; pin
bumps remain an explicit `nix flake lock --update-input nixpkgs` step.
