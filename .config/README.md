# Configuration Files

This directory contains application configuration files that are symlinked to `~/.config/` for consistency across machines.

## 📁 Directory Structure

```
.config/
├── direnv/
│   └── direnv.toml          # Direnv automatic allow whitelist
├── systemd/
│   └── user/
│       ├── nix-gc.service   # Nix garbage collection service
│       └── nix-gc.timer     # Weekly GC schedule (Mondays ~00:48)
├── fish/                    # Fish shell configuration
└── zsh/                     # Zsh shell configuration
```

## 🔄 Setup on New Machine

These files are automatically symlinked by the dotfiles bootstrap script. To manually create symlinks:

```bash
# Direnv configuration
mkdir -p ~/.config/direnv
ln -sf ~/.dotfiles/.config/direnv/direnv.toml ~/.config/direnv/direnv.toml

# Nix garbage collection (systemd user service)
mkdir -p ~/.config/systemd/user
ln -sf ~/.dotfiles/.config/systemd/user/nix-gc.service ~/.config/systemd/user/nix-gc.service
ln -sf ~/.dotfiles/.config/systemd/user/nix-gc.timer ~/.config/systemd/user/nix-gc.timer
systemctl --user daemon-reload
systemctl --user enable --now nix-gc.timer
```

## 🛠️ Configuration Details

### Direnv (`direnv.toml`)
- **Auto-allow**: All `.envrc` files under `/home/mhugo/code` are automatically trusted
- **Warn timeout**: 5 minutes before warning about unallowed files

### Nix Garbage Collection (`nix-gc.service` & `nix-gc.timer`)
- **Schedule**: Weekly on Mondays at ~00:48 (randomized ±1h)
- **Command**: `nix-collect-garbage -d` (deletes old generations and unused packages)
- **Persistent**: Catches up if system was off during scheduled time
- **Logs**: View with `journalctl --user -u nix-gc.service`

## 📊 Monitoring

```bash
# Check when next garbage collection will run
systemctl --user list-timers nix-gc.timer

# View garbage collection logs
journalctl --user -u nix-gc.service

# Manual garbage collection
nix-collect-garbage -d
```
