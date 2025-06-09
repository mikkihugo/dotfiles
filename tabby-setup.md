# Tabby Terminal Setup (2025)

## Installation
1. Download from https://tabby.sh
2. Available for: Windows, Mac, Linux, Android (Alpha)

## Free Cloud Sync Options:

### Option 1: GitHub Gist Sync (Recommended)
1. Install plugin: `Cloud Sync Settings`
2. Settings → Plugins → Search "sync"
3. Configure with GitHub token
4. Your SSH connections sync via Gist!

### Option 2: Tabby Web (Self-hosted)
```bash
# Run your own sync server
docker run -d -p 9876:80 ghcr.io/eugeny/tabby-web
```

### Option 3: File Sync
- Store config in: `~/.dotfiles/tabby/`
- Sync with Git, Syncthing, or Dropbox

## Migration from Termius:

```bash
# Export Termius hosts
termius export --output termius.json

# Convert to Tabby format
~/.dotfiles/.scripts/termius-to-tabby.sh
```

## Features:
- ✅ Free & Open Source
- ✅ Multi-platform (inc. Android alpha)
- ✅ Cloud sync via plugins
- ✅ Split panes, tabs
- ✅ SSH, serial, telnet
- ✅ Highly customizable
- ✅ No account required

## Config Location:
- Windows: `%APPDATA%\tabby\`
- Mac: `~/Library/Application Support/tabby/`
- Linux: `~/.config/tabby/`