# Termius Automation & Sync Setup

## 1. Termius CLI (termius-cli)
Install the official CLI for automation:
```bash
pip install termius
termius login
```

## 2. Export/Import Hosts Automatically
```bash
# Export all hosts to JSON
termius export --output ~/termius-hosts.json

# Import hosts from JSON
termius import --input ~/termius-hosts.json
```

## 3. Sync with Private Gist
Create a sync script:
```bash
#!/bin/bash
# ~/.dotfiles/.scripts/termius-sync.sh

GIST_ID="${TERMIUS_GIST_ID}"  # Set in ~/.env_tokens

# Export from Termius
termius export --output /tmp/termius-export.json

# Encrypt before uploading (optional)
# openssl enc -aes-256-cbc -salt -in /tmp/termius-export.json -out /tmp/termius-export.enc -k "$TERMIUS_ENCRYPT_KEY"

# Upload to gist
gh gist edit "$GIST_ID" /tmp/termius-export.json

# Cleanup
rm -f /tmp/termius-export.json
```

## 4. Auto-Apply Settings via API
Termius Pro API allows programmatic access:
```bash
# Set default settings for all hosts
curl -X PATCH https://api.termius.com/api/v4/hosts/ \
  -H "Authorization: Bearer $TERMIUS_API_KEY" \
  -d '{
    "startup_script": "tmux attach || tmux new -s main",
    "terminal_settings": {
      "mouse_reporting": "off",
      "copy_on_select": false,
      "paste_on_right_click": false,
      "scrollback_lines": 10000
    }
  }'
```

## 5. Termius Config Templates
Create host templates in `~/.dotfiles/termius-templates.json`:
```json
{
  "templates": {
    "default": {
      "terminal_type": "xterm-256color",
      "startup_script": "source ~/.bashrc && tmux attach || tmux new",
      "environment": {
        "TERM": "xterm-256color",
        "TMUX_STARTUP_ENABLED": "false"
      },
      "terminal_settings": {
        "font_size": 14,
        "cursor_blink": false,
        "mouse_reporting": "off"
      }
    },
    "production": {
      "inherit": "default",
      "startup_script": "tmux new-session -s prod-$(hostname)",
      "terminal_settings": {
        "background_color": "#2a0000"
      }
    }
  }
}
```

## 6. Bulk Update Script
Apply settings to multiple hosts:
```bash
#!/bin/bash
# Apply template to hosts matching pattern

TEMPLATE="default"
PATTERN="$1"

termius hosts list | grep "$PATTERN" | while read -r host_id host_name; do
  echo "Updating $host_name..."
  termius host update "$host_id" \
    --startup-script "tmux attach || tmux new -s main" \
    --terminal-type "xterm-256color"
done
```

## 7. Sync Snippets
Export/import snippets:
```bash
# Export snippets
termius snippet export > ~/.dotfiles/termius-snippets.json

# Import snippets  
termius snippet import < ~/.dotfiles/termius-snippets.json
```

## 8. Auto-sync on Login
Add to ~/.bashrc:
```bash
# Auto-sync Termius settings on login
if command -v termius &>/dev/null && [ -f "$HOME/.termius-last-sync" ]; then
  LAST_SYNC=$(stat -c %Y "$HOME/.termius-last-sync" 2>/dev/null || echo 0)
  NOW=$(date +%s)
  DIFF=$((NOW - LAST_SYNC))
  
  # Sync every 24 hours
  if [ $DIFF -gt 86400 ]; then
    echo "Syncing Termius settings..."
    ~/.dotfiles/.scripts/termius-sync.sh
    touch "$HOME/.termius-last-sync"
  fi
fi
```