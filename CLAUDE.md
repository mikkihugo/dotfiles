# synthLANG: HOMEDIR_MGMT v1.0

## CRITICAL_OPS:
  dotfiles_repo: ~/.dotfiles → github.com/mikkihugo/dotfiles
  commit_rule: ALL_CHANGES → IMMEDIATE_COMMIT
  commit_cmd: cd ~/.dotfiles && git add -A && git commit -m "$MSG" && git push

## FORBIDDEN_PATTERNS:
  file_suffix: [enhanced, improved, better, v2, new, old]
  examples: [file_enhanced.ts, component_v2.tsx, service_better.ts]
  rule: ALWAYS_EDIT_ORIGINAL && USE_GIT_VERSION_CONTROL

## ENV_SECURITY:
  storage: PRIVATE_GITHUB_GISTS  # NEVER in dotfiles repo
  local_path: ~/.env_tokens
  update_cmd: gh gist edit $GIST_ID ~/.env_tokens

## CONFIG_PROTOCOL:
  pre_edit_check: |
    ls -la ~/.bashrc  # symlink_indicator: →
    if !symlinked:
      cp ~/.bashrc ~/.dotfiles/
      ln -sf ~/.dotfiles/.bashrc ~/.bashrc
      cd ~/.dotfiles && git add .bashrc && git commit -m "Add .bashrc"

## ACTIVE_ENV:
  shell: bash + mise + starship
  nx_daemon: DISABLED (NX_DAEMON=false)  # prevents_server_kills
  sessions: tmux  # simple_cmds: s/sl/sk/sa/sm/sw/st

## QUICK_REF:
  dotfiles_sync: cd ~/.dotfiles && git add -A && git commit -m "$MSG" && git push
  token_update: gh gist edit $GIST_ID ~/.env_tokens
  nx_stop: pnpm nx daemon --stop
  session_mgmt: {s: create/attach, sl: list, sk: kill, sa/sm/sw/st: quick_jumps}