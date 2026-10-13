# Devbox cache layout

The devbox now exports the same logical package-cache variables as the runner,
but keeps them user-scoped. Cargo remains at `~/.cargo` so `~/.cargo/bin` and
rustup-compatible tools do not move. Mix, Hex, and npm caches are normalized
under `~/.cache`; activation migrates a legacy directory once and leaves a
compatibility symlink.

RED proof: `scripts/test-language-cache-layout.sh` failed before the variables
and activation migration existed. GREEN proof:

```sh
bash scripts/test-language-cache-layout.sh
repo check nix
```
