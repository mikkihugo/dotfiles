# CLAUDE.md - Claude-specific configuration

## RUST TOOLS ENFORCEMENT
**ALWAYS use these commands instead of traditional Unix tools:**
- **NEVER use `find`** → Always use `fd`
- **NEVER use `grep`** → Always use `rg` (ripgrep)
- **NEVER use `ls`** → Always use `eza`
- **NEVER use `cat`** → Always use `bat`
- **NEVER use `sed`** → Always use `sd` when available
- **NEVER use `ps`** → Always use `procs` when available
- **NEVER use `du`** → Always use `dust` when available
- **NEVER use `top/htop`** → Always use `btop` when available

## TOOL PATHS (if commands fail)
- ripgrep: `/home/mhugo/.local/share/mise/installs/ripgrep/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl/rg`
- fd: `fd` (mise-managed)
- eza: `eza` (mise-managed)
- bat: `bat` (mise-managed)

## COMMON PATTERNS
```bash
# Search for files
fd "pattern"                    # NOT: find . -name "*pattern*"
fd -e js -e ts                  # NOT: find . -name "*.js" -o -name "*.ts"
fd -t f -x echo {}              # NOT: find . -type f -exec echo {} \;

# Search in files  
rg "pattern"                    # NOT: grep -r "pattern" .
rg -t js "function"             # NOT: grep --include="*.js" -r "function" .
rg -l "pattern"                 # NOT: grep -l "pattern" *

# List files
eza -la                         # NOT: ls -la
eza --tree --level=2            # NOT: tree -L 2
```

## HOME DIRECTORY MANAGEMENT

### CRITICAL: Always use dotfiles repo
- **Repo**: `~/.dotfiles` → `github.com/mikkihugo/dotfiles`
- **Rule**: Commit ALL home config changes immediately
- **Command**: `cd ~/.dotfiles && git add -A && git commit -m "message" && git push`

### FORBIDDEN: File naming
- **NEVER use**: `enhanced`, `improved`, `better`, `v2`, `new`, `old`
- **NEVER create**: `file_enhanced.ts`, `component_v2.tsx`, `service_better.ts`
- **ALWAYS**: Edit the original file directly
- **ALWAYS**: Use git for version control, not filename suffixes

### Shell Aliases to Avoid
- **find**: Aliased to `fd` - causes command failures
- **grep**: Aliased to `rg` - use `rg` directly instead
- **Use instead**: `fd` for finding files, `rg` for searching content

### Fixed Issues
- **alias: --: not found**: Fixed problematic `alias -- '-=cd -'` in .aliases file
- **Line 153 error**: Appears in current session but fixed for new terminals

### Sensitive Data (.env files)
- **Storage**: Private GitHub Gists (NOT in dotfiles repo)
- **Local**: `~/.env_tokens` (downloaded from gist)
- **Update gist**: `gh gist edit $GIST_ID ~/.env_tokens`

### Before editing ANY home config file:
```bash
# Check if it's already managed
ls -la ~/.bashrc  # Look for symlink arrow →

# If not symlinked, add to dotfiles:
cp ~/.bashrc ~/.dotfiles/
ln -sf ~/.dotfiles/.bashrc ~/.bashrc
cd ~/.dotfiles && git add .bashrc && git commit -m "Add .bashrc"
```

### Active configurations:
- **Shell**: bash with mise + starship
- **Terminal**: tabby
- **NX**: Daemon disabled (NX_DAEMON=false) to prevent server kills

### Quick reference:
- Commit dotfiles: `cd ~/.dotfiles && git add -A && git commit -m "msg" && git push`
- Update tokens: `gh gist edit $GIST_ID ~/.env_tokens`
- Stop NX: `pnpm nx daemon --stop`