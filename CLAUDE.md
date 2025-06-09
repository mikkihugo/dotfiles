# synthLANG: HOMEDIR_MGMT v1.2

## CRITICAL_OPS:
  dotfiles_repo: ~/.dotfiles → github.com/mikkihugo/dotfiles
  commit_rule: ALL_CHANGES → IMMEDIATE_COMMIT
  commit_cmd: cd ~/.dotfiles && git add -A && git commit -m "$MSG" && git push

## FORBIDDEN_PATTERNS:
  file_suffix: [enhanced, improved, better, v2, new, old]
  examples: [file_enhanced.ts, component_v2.tsx, service_better.ts]
  rule: ALWAYS_EDIT_ORIGINAL && USE_GIT_VERSION_CONTROL

## TEMP_SCRIPTS:
  location: ~/.tmp/  # NOT in home directory
  cleanup: ALWAYS_DELETE_AFTER_USE
  pattern: ~/.tmp/test-*.sh → execute → rm
  example: |
    mkdir -p ~/.tmp
    cat > ~/.tmp/test-gateway.sh << 'EOF'
    #!/bin/bash
    echo "test"
    EOF
    chmod +x ~/.tmp/test-gateway.sh
    ~/.tmp/test-gateway.sh
    rm ~/.tmp/test-gateway.sh

## ENV_SECURITY:
  storage: PRIVATE_GITHUB_GISTS  # NEVER in dotfiles repo
  local_path: ~/.env_tokens
  update_cmd: gh gist edit $GIST_ID ~/.env_tokens
  gist_ids:
    tokens: 51169297e2acfc6da7d22b16d5e5c53b
    gateway_backup: a1549caf1eece0a9896fd4027cd1881e

## TABBY_GATEWAY:
  url: ws://51.38.127.98:9000
  token: STORED_IN_GIST  # See .env_tokens
  backup: mise run gateway-backup
  deploy: mise run gateway-deploy
  schedule: mise run gateway-schedule

## CONFIG_PROTOCOL:
  pre_edit_check: |
    ls -la ~/.bashrc  # symlink_indicator: →
    if !symlinked:
      cp ~/.bashrc ~/.dotfiles/
      ln -sf ~/.dotfiles/.bashrc ~/.bashrc
      cd ~/.dotfiles && git add .bashrc && git commit -m "Add .bashrc"

## ACTIVE_ENV:
  shell: bash + mise + starship
  terminal: tabby (not termius/warp)
  nx_daemon: DISABLED (NX_DAEMON=false)  # prevents_server_kills
  sessions: tmux  # simple_cmds: s/sl/sk/sa/sm/sw/st

## MISE_TASKS:
  gateway-backup: Backup gateway to gist
  gateway-sync: Sync config from gist
  gateway-deploy: Deploy gateway container
  gateway-schedule: Setup daily backups
  sync: Sync dotfiles + tokens + SSH
  setup: Complete environment setup

## QUICK_REF:
  dotfiles_sync: cd ~/.dotfiles && git add -A && git commit -m "$MSG" && git push
  token_update: gh gist edit $GIST_ID ~/.env_tokens
  nx_stop: pnpm nx daemon --stop
  session_mgmt: {s: create/attach, sl: list, sk: kill, sa/sm/sw/st: quick_jumps}