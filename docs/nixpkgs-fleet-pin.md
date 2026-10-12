# Fleet nixpkgs pin (dotfiles consumer)

Dotfiles follows the Engine **one knob** for the fleet-canonical nixpkgs revision
used by Rust toolchain packages on devbox hosts (`cargo-subcommand-proxies`).

## Flake input

```nix
engine-nixpkgs-pin.url =
  "git+ssh://git@git.centralcloud.net:2222/singularity/singularity-engine?dir=nix/toolchains/nixpkgs-pin";
```

Home modules receive `engine-nixpkgs-pin` via `extraSpecialArgs` and import
`legacyPackages.<system>.rustPackages_*` from that input—not a separate
`nixpkgs-rust` URL.

## Bump workflow

1. Bump the pin in Engine only: see
   [nix/toolchains/nixpkgs-pin/README.md](https://git.centralcloud.net/singularity/singularity-engine/src/branch/main/nix/toolchains/nixpkgs-pin/README.md)
   (set `flake.nix` + `versions.json` `nixpkgs_rev`, lock the pin flake, then
   lock Engine root).
2. Refresh dotfiles lock:
   `nix flake lock --update-input engine-nixpkgs-pin`
3. Apply on the host:
   `home-manager switch --flake .#cc-se-sto-devbox-01` (or your profile name).
4. Optional fleet health (Engine): `repo prove nixpkgs-pin` / `bash scripts/se_nixpkgs_fleet_health.sh`.

## Lock failure: pin not on Forgejo yet

If `git+ssh://…?dir=nix/toolchains/nixpkgs-pin` cannot lock (directory not on
`main` yet), use a local Engine worktree override for evaluation only:

```bash
nix flake lock \
  --override-input engine-nixpkgs-pin \
  /home/mhugo/code/worktrees/jj/singularity-engine/engine-nixpkgs-lock-20261012/nix/toolchains/nixpkgs-pin
```

Commit the resulting `flake.lock` only after the same pin path exists on Forgejo
so other hosts can lock without overrides.

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
bumps remain an explicit `nix flake lock --update-input engine-nixpkgs-pin` step.
