# Home Directory Management Rules

## CRITICAL: Always use dotfiles repo
- **Repo**: `~/dotfiles` → `github.com/mikkihugo/dotfiles`
- **Rule**: Commit ALL home config changes immediately
- **Command**: `cd ~/dotfiles && git add -A && git commit -m "message" && git push`

## FORBIDDEN: File naming
- **NEVER use**: `enhanced`, `improved`, `better`, `v2`, `new`, `old`
- **NEVER create**: `file_enhanced.ts`, `component_v2.tsx`, `service_better.ts`
- **ALWAYS**: Edit the original file directly
- **ALWAYS**: Use git for version control, not filename suffixes

## Sensitive Data (.env files)
- **Storage**: Private GitHub Gists (NOT in dotfiles repo)
- **Local**: `~/.env_tokens` (downloaded from gist)
- **Update gist**: `gh gist edit $GIST_ID ~/.env_tokens`

## Before editing ANY home config file:
```bash
# Check if it's already managed
ls -la ~/.bashrc  # Look for symlink arrow →

# If not symlinked, add to dotfiles:
cp ~/.bashrc ~/dotfiles/
ln -sf ~/dotfiles/.bashrc ~/.bashrc
cd ~/dotfiles && git add .bashrc && git commit -m "Add .bashrc"
```

## Active configurations:
- **Shell**: bash with mise + starship
- **NX**: Daemon disabled (NX_DAEMON=false) to prevent server kills

## Quick reference:
- Commit dotfiles: `cd ~/dotfiles && git add -A && git commit -m "msg" && git push`
- Update tokens: `gh gist edit $GIST_ID ~/.env_tokens`
- Stop NX: `pnpm nx daemon --stop`