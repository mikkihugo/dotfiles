# 🚀 Ultimate Modern Development Environment

Enterprise-grade dotfiles with GitOps automation, smart sync, Tabby gateway, and comprehensive tooling.

> 📝 **Claude Code Instructions**: See CLAUDE.md in synthLANG format  
> 🔐 **Security Note**: Tokens and sensitive configs stored in private gists

## ✨ Key Features

### 🤖 Automated Sync System
- **Smart detection** - Lightning-fast GitHub API checks on login
- **Auto-sync** - Background updates when changes detected
- **Cross-server sync** - All machines stay updated automatically
- **Gist integration** - Secure token & SSH host management

### 🎨 Session & Gateway Management
- **Simple commands** - `s/sl/sk` for tmux session management
- **Tabby gateway** - Multi-user SSH gateway at ws://51.38.127.98:9000
- **SSH integration** - Tabby-sync for unified host management
- **Automated backups** - Daily gateway backups to GitHub gists

### 📦 Backup & Restore
- **Complete state** - Tmux sessions, shell history, SSH configs
- **Smart compression** - Automated backup rotation
- **Instant restore** - One-click environment recreation
- **Directory memory** - Zoxide integration for smart navigation

### 🛠️ Development Powerhouse
- **40+ Git aliases** - `gs`, `gp`, `glog`, `cleanup`, `pushit`
- **Modern CLI tools** - bat, eza, fd, fzf, ripgrep, zoxide
- **Version management** - Mise for Python, Node, Go, Rust
- **Enhanced tmux** - Plugins, session persistence, global hotkeys

## 🚀 Quick Start

### One-Line Install
```bash
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./install.sh
```

### Enable Auto-Sync
```bash
cd ~/.dotfiles && ./.scripts/setup-cron.sh
```

## 🎯 What You Get

### Session Management
```bash
s [name]         # Create/attach tmux session
sl               # List sessions
sk [name]        # Kill session
sa/sm/sw/st      # Quick jumps (agent/mcp/work/temp)
```

### Tabby Gateway
```bash
mise run gateway-deploy    # Deploy gateway container
mise run gateway-backup    # Backup to GitHub gist
mise run gateway-sync      # Sync config from gist
mise run gateway-schedule  # Setup daily backups
```

### Productivity Aliases
```bash
# Git shortcuts
gs               # git status
ga .             # git add .
gcm "message"    # git commit -m
gp               # git push
glog             # beautiful git log
cleanup          # delete merged branches

# Modern replacements
ls               # → eza with icons and git status
cat              # → bat with syntax highlighting
cd               # → zoxide (smart directory jumping)
find             # → fd (faster file search)
grep             # → ripgrep (faster text search)
```

### System Management
```bash
backup-restore   # Complete environment backup
mise run sync    # Manual dotfiles sync
system-info      # Beautiful system dashboard
weather          # Current weather display
```

## 📋 Interactive Menu

On every login, get a beautiful menu with:
- **Numbered tmux sessions** (1-5 for instant access)
- **SSH connections** from Tabby sync
- **System tools** and information
- **Backup/restore** operations
- **Quick actions** for common tasks

## 🔄 Auto-Sync Architecture

### Smart Detection
1. **Login check** - GitHub API call (~200ms) to compare commit hashes
2. **Background sync** - Non-blocking updates when changes found
3. **Notifications** - Desktop alerts for sync status
4. **Fallback cron** - Daily 6 AM sync for servers without logins

### What Gets Synced
- ✅ **Dotfiles** - All configurations via git
- ✅ **Tools** - Mise automatically installs/updates
- ✅ **Tokens** - Secure gist-based secret management
- ✅ **SSH hosts** - Tabby integration for unified access

## 📁 Repository Structure

```
.dotfiles/
├── 🔧 Core Config
│   ├── .mise.toml          # Tool versions & tasks
│   ├── config/bashrc       # Enhanced shell config
│   ├── config/tmux.conf    # Tmux with plugins
│   ├── .gitconfig          # 40+ git aliases
│   └── .aliases            # 100+ productivity shortcuts
├── 🤖 Automation
│   ├── .scripts/auto-sync.sh      # Smart sync system
│   ├── .scripts/quick-check.sh    # Fast GitHub API checks
│   ├── .scripts/enhanced-menu.sh  # Interactive login menu
│   └── .scripts/backup-restore.sh # Complete state management
├── 🔐 Security
│   ├── .scripts/tabby-sync.sh     # SSH host management
│   └── CLAUDE.md                  # AI assistant rules
└── 📚 Documentation
    └── README.md                   # This file
```

## 🌟 Advanced Features

### Git Workflow Enhancement
```bash
# Smart aliases
glog             # Beautiful graph log
today            # Commits from today
yesterday        # Commits from yesterday
find "message"   # Search commits by message
pushit           # Push current branch with upstream
rebase-main      # Interactive rebase from main
cleanup          # Delete merged branches
```

### Tmux Session Management
- **Auto-restore** - Sessions persist across reboots
- **Global hotkeys** - Ctrl+Alt+1-5 for session switching
- **Smart naming** - Automatic session organization
- **Backup integration** - Save/restore complete state

### System Intelligence
- **Smart cd** - Zoxide learns your navigation patterns
- **Directory jumping** - Instant access to frequent paths
- **System monitoring** - Real-time resource dashboard
- **Network info** - Internal/external IP display

## 🔧 Customization

### Add New Tools
```bash
# Edit mise configuration
vim ~/.dotfiles/.mise.toml

# Add to tools section
[tools]
your-tool = "latest"

# Commit changes
cd ~/.dotfiles
git add . && git commit -m "Add your-tool" && git push
```

### Custom Aliases
```bash
# Edit aliases file
vim ~/.dotfiles/.aliases

# Add your aliases
alias mycommand='your command here'

# Auto-syncs across all machines
```

### SSH Host Management
```bash
# Add hosts via Tabby or direct edit
tabby-sync push    # Push local hosts to gist
tabby-sync pull    # Pull hosts from gist
```

## 🌐 Multi-Machine Workflow

### Initial Setup (New Machine)
```bash
# 1. Clone dotfiles
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles

# 2. Run installer
cd ~/.dotfiles && ./install.sh

# 3. Setup auto-sync
./.scripts/setup-cron.sh

# 4. Download tokens (ask team for gist ID)
gh gist view $TOKENS_GIST_ID > ~/.env_tokens
```

### Daily Usage
- **Make changes** on any machine
- **Auto-sync** happens on login/daily
- **All machines** stay synchronized
- **Zero manual intervention** needed

## 🛠️ Troubleshooting

### Sync Issues
```bash
# Check sync status
tail -f ~/.dotfiles/auto-sync.log

# Manual sync
cd ~/.dotfiles && mise run sync

# Reset sync state
rm ~/.dotfiles/.remote_hash && ~/.dotfiles/.scripts/quick-check.sh sync
```

### Missing Tools
```bash
# Reinstall everything
cd ~/.dotfiles && mise install

# Check tool versions
mise list
```

### Menu Not Showing
```bash
# Test menu directly
~/.dotfiles/.scripts/enhanced-menu.sh force

# Check bashrc loading
source ~/.bashrc
```

## 🎨 Screenshots

### Login Experience
```
🚀 SESSION & CONNECTION MANAGER

📋 TMUX SESSIONS
1) 🟢 main [ATTACHED] 3w
2) 🔵 work [FREE] 1w
3) 🔵 temp [FREE] 2w

🌐 SSH CONNECTIONS (5 hosts)
  🔗 server1 → user@host1.com
  🔗 server2 → user@host2.com

✨ New tmux session
🗑️ Kill tmux session
📦 Sync dotfiles
⚙️ Quick tools
```

### System Information
```
🖥️ SYSTEM INFORMATION
====================

📋 System:
  Host: dev-server
  OS: Ubuntu 22.04 LTS
  Uptime: 5 days, 3 hours

💾 Memory:
  Used: 4.2G/16G (26%)

💿 Disk:
  Root: 45G/100G (45% used)

⚡ CPU:
  Intel Xeon E5-2686 v4
  Cores: 8 | Load: 0.5

🌐 Network:
  IP: 192.168.1.100
  External: 203.0.113.1
```

## 📊 Performance Stats

- **Login time**: ~300ms (with sync check)
- **Sync speed**: ~2-5 seconds (full sync)
- **API check**: ~200ms (hash comparison)
- **Menu load**: ~100ms (gum interface)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📜 License

MIT License - See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- **[Mise](https://mise.jdx.dev/)** - Modern tool version management
- **[Starship](https://starship.rs/)** - Cross-shell prompt
- **[Gum](https://github.com/charmbracelet/gum)** - Glamorous shell scripts
- **[Zoxide](https://github.com/ajeetdsouza/zoxide)** - Smart directory jumping
- **[Modern Unix](https://github.com/ibraheemdev/modern-unix)** - CLI tool inspiration

---

**🚀 Ready to supercharge your development environment?**

Get started with: `git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles && cd ~/.dotfiles && ./install.sh`