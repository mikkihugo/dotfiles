# dotfiles

Nix-powered dotfiles for `mhugo` with SOPS-encrypted secrets. A single `flake.nix` pins every language runtime and CLI, while profile manifests describe how the repo links into `$HOME`.

## New Machine Setup (One Command)

```bash
curl -sSL https://raw.githubusercontent.com/mikkihugo/dotfiles/main/bootstrap-remote.sh | bash
```

Just paste your SSH key when prompted. The script will:
- ✅ Install Nix package manager
- ✅ Set up SSH keys (main + additional keys/config)
- ✅ Clone your private dotfiles repo
- ✅ Set up SOPS decryption (from your SSH key)
- ✅ Install all configurations and tools
- ✅ Load all your encrypted secrets immediately

**That's it! Your new machine has your complete environment in 2 minutes.**

## Manual Setup (if needed)

```bash
# 1. Install Nix (multi-user)
curl -L https://nixos.org/nix/install | sh

# 2. Clone the dotfiles
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 3. Enter the dev shell
nix develop        # or: direnv allow (see below)

# 4. Apply the default profile (symlinks + backups)
./install.sh

# 5. (Optional) Make the nix dev shell your login environment
./setup-login-shell.sh
```

After step 5, new terminals automatically drop into zsh running inside the flake-managed environment.

Choose a different profile on the fly:

```bash
DOTFILES_PROFILE=services ./install.sh
```

The `.envrc` file enables automatic activation via [direnv](https://direnv.net/). Run `direnv allow` once per machine if you prefer transparent entry into `nix develop` whenever you `cd` into the repo.

## Layout

```
flake.nix                # Declarative toolchain definition
.envrc                   # direnv hook (use flake)
bootstrap/
  steps/                 # Ordered setup tasks (check nix, link configs, post actions)
config/                  # Files mirroring final destinations under $HOME
profiles/                # Host/role manifests (links.json)
shell/                   # Shared shell logic + per-shell entrypoints
services/                # Optional infra bits (Cloudflare, litellm, vault, etc.)
tasks/                   # Lint/doctor helpers invoked inside the dev shell
install.sh               # Delegates to bootstrap/bootstrap.sh
```

All interactive shells (`bash`, `zsh`, optional `nushell`) source the same shared environment:

- `shell/shared/env.sh` exports `DOTFILES_ROOT`, loads `~/.env_*` overlays, and appends user-local bin paths.
- `shell/shared/aliases.sh` wires modern CLI aliases (`rg`, `fd`, `eza`, …) with graceful fallbacks.
- `shell/shared/tooling.sh` initialises `zoxide`, `starship`, and `direnv` when available.

## Tooling via Nix

`flake.nix` provisions:
- Runtimes: Node.js 20, pnpm 9, Python 3.12, Go 1.22, Rust (rustup), GCC
- Developer tooling: git (+LFS + gitui), zsh, nushell, zoxide, direnv + nix-direnv, starship, ripgrep, fd, fzf, bat, eza, delta, tmate, Eternal Terminal, tmux, htop, jq, yq, cloudflared, tailscale, shellcheck, shfmt, curl, wget, unzip

`nix develop` (or `direnv allow`) places all of these on `PATH`; Moonrepo, VS Code, and other tooling just see a preconfigured environment with no manual installs.

## Bootstrap Flow

`install.sh` delegates to `bootstrap/bootstrap.sh`, which:

1. Verifies Nix is available (`bootstrap/steps/00-check-nix.sh`).
2. Reads the active profile manifest and symlinks files into `$HOME`, backing up any collisions in `~/.dotfiles-backup-YYYYMMDD-HHMMSS` (`bootstrap/steps/10-symlinks.sh`).
3. Runs the `tasks/run doctor` helper for a quick sanity check (`bootstrap/steps/20-post.sh`).

Re-run `./install.sh` whenever you pull an update or switch profiles—it’s idempotent.

## Tasks

Inside the dev shell:

```
./tasks/run lint    # shellcheck + shfmt
./tasks/run doctor  # print versions of major toolchains
```

Extend `tasks/scripts/` and update `tasks/run` to expose additional helpers.

## Profiles

`profiles/default/links.json` connects the core shell config:

- `shell/bash/bashrc` → `~/.bashrc`
- `shell/zsh/zshrc` → `~/.zshrc`
- `config/starship.toml` → `~/.config/starship.toml`
- `config/zellij/*` → `~/.config/zellij/`
- `config/git/config` → `~/.config/git/config`
- `config/ripgreprc` → `~/.ripgreprc`

`profiles/services/links.json` adds Cloudflare/LiteLLM manifests under `~/.config/services/` so ops machines can opt in without cluttering personal laptops.

## Connectivity Toolkit

The dev shell ships with several always-ready remote tools:

- **tmate** for instant shared terminals (use the public relay or self-host `tmate-ssh-server`).
- **Eternal Terminal (et)** for resilient SSH sessions; pair with Cloudflare Tunnel or Tailscale to avoid inbound firewall rules.
- **cloudflared** to publish SSH/web endpoints through Cloudflare Access without opening ports.
- **tailscale** for mesh VPN and SSH certificates—run `sudo tailscale up` on hosts that join your tailnet.

Nushell (`nushell`) is available for structured pipelines, while Bash remains the fallback system shell for scripts.

## Next Steps

- Review `shell/shared/aliases.sh` and prune/extend as needed.
- Inspect `services/` before launching anything—populate `.env` files with real secrets outside git.
- Consider adding per-host manifests (`profiles/<name>/links.json`) for CI, servers, or experimental setups.

Happy hacking! ✨
