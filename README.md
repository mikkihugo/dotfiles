# dotfiles

Declarative user environment for `mhugo`. A single Nix flake pins every
package and tool version; home-manager applies the configuration to `$HOME`.
Secrets are SOPS-encrypted with an age key derived from the SSH ed25519 key —
no separate password, no plaintext credentials in the repo.

## How it works

```
flake.nix           ← nixpkgs + home-manager + sops-nix pins
home/home.nix       ← everything installed and configured in $HOME
secrets/            ← SOPS-encrypted YAML (age backend, .sops.yaml rules)
config/             ← static config files linked into $HOME by home-manager
shell/bash/bashrc   ← on-demand LLM key loader (sourced by HM initExtra)
tools/secret-tui-rust/ ← terminal UI for browsing SOPS secrets
```

`home-manager switch` is the only command needed after any change. It:
1. Builds the Nix derivation (packages, symlinks, shell init)
2. Links config files from `config/` into `~/.config/`
3. Writes generated shell init blocks into `~/.bashrc` / `~/.zshrc`

## New machine setup

```bash
# 1. Install Nix (multi-user, flakes enabled)
curl -L https://nixos.org/nix/install | sh -s -- --daemon
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf

# 2. Clone
git clone git@github.com:mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 3. Add this machine's age key (derived from SSH key — no extra key needed)
mkdir -p ~/.config/sops/age
ssh-to-age -i ~/.ssh/id_ed25519.pub >> ~/.dotfiles/secrets/.sops-machine-keys.txt
# Then add that pubkey to .sops.yaml and re-encrypt secrets (see Secrets below)

# 4. Apply
home-manager switch --flake .#mhugo --impure \
  --extra-experimental-features "nix-command flakes"
```

After step 4, open a new terminal — you're in the managed environment.

## Day-to-day

| Task | Command |
|------|---------|
| Apply config changes | `hms` (alias for home-manager switch) |
| Promote committed ACE worker source into dotfiles | `promote-ace-coder` |
| Load LLM API keys | `load-ai-keys` |
| Browse / edit secrets | `secrets` (opens secret-tui) |
| Enter dotfiles maintenance shell | `nix develop ~/.dotfiles` |

### ACE worker update flow

The local GPU worker services are built from the pinned `ace-coder` flake input,
not from the live dirty checkout in `~/code/ace-coder`.

Use this workflow:

```bash
# 1. Finish and commit the worker-related ACE change in ~/code/ace-coder

# 2. Promote that committed ACE revision into dotfiles
promote-ace-coder

# 3. Apply the dotfiles generation
hms
```

This keeps Home Manager activations reproducible and lets Nix reuse cached
worker builds instead of treating every local ACE edit as a new source hash.

## Repo layout

```
flake.nix                    Entry point — nixpkgs/HM/sops-nix pins
home/
  home.nix                   Declarative user config (packages, shell, git, tools)
config/
  starship.toml              Prompt theme (managed by programs.starship)
  zellij/                    Terminal multiplexer config
  direnv/direnv.toml         Direnv settings (strict mode, warn timeout)
  git/                       Git config fragments (linked by programs.git)
secrets/
  api-keys.yaml              SOPS-encrypted LLM gateway + Claude OAuth token
  .sops.yaml                 Encryption rules (which keys can decrypt which files)
shell/
  bash/bashrc                On-demand load-ai-keys function (sourced by HM)
tools/
  secret-tui-rust/           Ratatui TUI: browse/reveal/edit SOPS secrets
.sops.yaml                   Age key recipients for secret re-encryption
lefthook.yml                 Git hooks: alejandra, statix, shellcheck, shfmt,
                             typos, detect-secrets on pre-commit
```

## Secrets

Secrets live in `secrets/api-keys.yaml`, encrypted with [SOPS](https://github.com/getsops/sops)
using [age](https://github.com/FiloSottile/age) keys derived from SSH ed25519 keys.
No GPG, no separate key files — the SSH key you already have is the decryption key.

### View / edit

```bash
# Browse interactively (reveal, copy, edit)
secrets

# Or directly via sops
sops -d secrets/api-keys.yaml          # decrypt to stdout
sops secrets/api-keys.yaml             # open in $EDITOR (re-encrypts on save)

# In-place value update (never redirect stdout — use sops set)
sops set secrets/api-keys.yaml '["llm_mux"]["api_key"]' '"new-value"'
```

### Adding a new machine

```bash
# 1. Get the age pubkey for the new machine's SSH key
ssh-to-age -i ~/.ssh/id_ed25519.pub

# 2. Add it to .sops.yaml under keys:
#    - age: age1...newkey...

# 3. Re-encrypt all secrets with the new recipient
cd ~/.dotfiles
nix develop  # enters maintenance shell with sops available
sops updatekeys secrets/api-keys.yaml

# 4. Commit .sops.yaml + the re-encrypted secrets/api-keys.yaml
```

### Secret structure (api-keys.yaml)

```yaml
llm_mux:
    api_key: <gateway key>     # single key for all LLM providers
    base_url: <gateway URL>    # routes OpenAI / Anthropic / Google calls
claude_code:
    oauth_token: <token>       # Claude Code OAuth (bypasses ANTHROPIC_API_KEY)
```

`load-ai-keys` decrypts this file and exports the values as the environment
variables each SDK expects (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.).

## What home.nix configures

All user-space config is in `home/home.nix`. It is the single source of truth —
editing a dotfile directly will be overwritten on the next `hms`.

| Section | Purpose |
|---------|---------|
| `home.packages` | CLI tools installed into the user profile |
| `programs.bash` / `programs.zsh` | Shell init (exports DOTFILES_ROOT, sources bashrc) |
| `programs.git` | Git identity, delta pager, aliases |
| `programs.jujutsu` | jj identity and UI settings |
| `programs.direnv` | Auto-load nix shells on `cd` (nix-direnv caches evaluations) |
| `programs.starship` | Cross-shell prompt, config from `config/starship.toml` |
| `programs.zoxide` | Smarter `cd` with frecency scoring |
| `programs.gh` | GitHub CLI settings |

## Code quality (pre-commit hooks)

lefthook runs on every commit:

| Hook | What it checks |
|------|---------------|
| `alejandra` | Nix formatting |
| `statix` | Nix anti-patterns |
| `shellcheck` | Shell script correctness |
| `shfmt` | Shell script formatting |
| `typos` | Spell checking |
| `detect-secrets` | Credential leak prevention |

Run manually: `lefthook run pre-commit`
