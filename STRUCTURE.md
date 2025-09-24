# Repository Structure

```
.
├── flake.nix                # Nix dev shell with all runtimes/tooling
├── .envrc                   # direnv hook (use flake)
├── bootstrap/
│   ├── bootstrap.sh         # entrypoint called by install.sh
│   └── steps/               # ordered scripts (00-, 10-, 20-...)
├── config/                  # mirrors $HOME destinations (starship, zellij, git, ...)
├── profiles/
│   ├── default/links.json   # standard workstation links
│   └── services/links.json  # optional ops stack links
├── services/                # docker/cloudflare/litellm/vault manifests
├── shell/
│   ├── shared/              # env + aliases shared across shells
│   ├── bash/                # bash-specific entrypoints
│   └── zsh/                 # zsh-specific entrypoints
├── tasks/
│   ├── run                  # thin task dispatcher
│   └── scripts/             # lint + doctor helpers
├── install.sh               # forwards to bootstrap/bootstrap.sh
└── setup-login-shell.sh     # make the nix dev shell your login environment
```

- Run `nix develop` (or `direnv allow`) to enter the managed toolchain before invoking scripts.
- Apply a profile with `./install.sh` (use `DOTFILES_PROFILE=<name>` to switch).
- New files go under `config/` and are linked through a profile manifest.
- Add maintenance helpers under `tasks/scripts/` and expose them via `tasks/run`.
- Bump tool versions by editing `flake.nix` and committing the updated lock file (`nix flake update`).
