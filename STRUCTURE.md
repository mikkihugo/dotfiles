# Dotfiles Structure (Clean & Organized)

## 📁 All configs in `config/` with symlinks:

```
config/
├── aliases       → ~/.aliases
├── bashrc        → ~/.bashrc  
├── starship.toml → ~/.config/starship.toml
└── tmux.conf     → ~/.tmux.conf

.scripts/
├── tabby-sync.sh         # Tabby ↔ Gist sync
├── tmux-startup.sh       # Login menu
├── tmux-save-restore.sh  # Session management
└── tmux-auto-name.sh     # Auto-naming

.mise.toml                # Tools including jq, yq, gh
```

## ✅ All dependencies via mise:
- `jq` - JSON processing
- `yq` - YAML processing  
- `gh` - GitHub CLI for gist sync

## 🔗 Symlinks verified:
- All configs properly linked from `config/`
- Scripts accessible via PATH
- Fixed broken aliases

## 🎯 Single sync command:
```bash
tabby-sync pull    # Get hosts from gist
tabby-sync push    # Save hosts to gist
```

Clean, organized, and maintainable!