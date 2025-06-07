# 🚀 Modern Development Environment Dotfiles

GitOps-style configuration management for a supercharged development environment.

## ✨ Features

### 🛠️ Development Tools
- **Mise** - Modern, fast version manager (asdf replacement)
- **Python 3.12.8** - With SQLite support 
- **Node.js 22.16.0** - Latest LTS
- **Go 1.22.0** - Systems programming
- **Rust** - Modern systems language

### 🎨 Modern CLI Tools
- **Starship** - Beautiful, fast shell prompt
- **Bat** - Better cat with syntax highlighting
- **Exa** - Better ls with icons and colors
- **FD** - Better find command
- **FZF** - Fuzzy finder for everything
- **Hyperfine** - Command benchmarking
- **LazyGit** - Interactive Git TUI
- **k9s** - Kubernetes cluster TUI

### 🖥️ Terminal Experience  
- **Tmux** - Auto-starting session management
- **Mosh compatibility** - Fixed scrolling issues
- **Smart aliases** - Productivity shortcuts
- **Auto-completion** - For Git, GitHub CLI, etc.

## 🚀 Quick Start

### Public Repo Installation (No Auth Required):
```bash
# Clone without authentication
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh

# Optional: Setup tokens after installation
env-setup    # For encrypted token management
```

### Manual installation:
```bash
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
chmod +x install.sh
./install.sh
```

## 📁 Repository Structure

```
.dotfiles/
├── .mise.toml             # Mise configuration
├── .tool-versions         # Legacy ASDF compatibility
├── install.sh             # Automated setup script
├── bootstrap.sh           # Minimal bootstrap script
├── config/
│   ├── bashrc             # Bash configuration
│   ├── aliases            # Command aliases
│   ├── tmux.conf          # Tmux configuration
│   └── starship.toml      # Starship prompt config
├── .scripts/
│   ├── tmux-startup.sh    # Tmux session manager
│   ├── tmux-auto-name.sh  # Auto-name sessions
│   └── tmux-save-restore.sh # Session persistence
├── CLAUDE.md              # AI assistant instructions
└── README.md              # This file
```

## 🎯 What Gets Installed

### Core Environment
- **Mise** - Modern version manager (Rust-based, faster than asdf)
- **Starship** - Cross-shell prompt
- **Tmux** - Terminal multiplexer with auto-start
- **Modern CLI tools** - bat, exa, fd, fzf, etc.

### Development Languages  
- **Python 3.12.8** - With SQLite support
- **Node.js 22.16.0** - Latest LTS
- **Go 1.22.0** - Google's language
- **Rust** - Systems programming

### Productivity Tools
- **LazyGit** - Interactive Git interface
- **GitHub CLI** - GitHub from command line
- **k9s** - Kubernetes cluster management
- **FZF integrations** - Fuzzy search everywhere

## ⚙️ Configuration Features

### Smart Aliases
```bash
ls    # → exa with icons
cat   # → bat with syntax highlighting  
lg    # → lazygit
k     # → kubectl
ta    # → tmux attach
```

### Tmux Auto-start
- **SSH sessions** automatically start tmux
- **Smart session management** (create/attach/choose)
- **Mosh scrolling fixed** with proper terminal overrides

### Starship Prompt
Shows context-aware information:
- 🌿 Git branch and status
- 🐍 Python version
- ⬢ Node.js version  
- ☸️ Kubernetes context
- ⏰ Current time

## 🔧 Customization

### Modify configurations:
```bash
cd ~/.dotfiles
# Edit any config file
vim config/aliases
# Commit and push changes
git add . && git commit -m "Update aliases"
git push
```

### Add new tools:
```bash
# Add to .mise.toml
# Edit the [tools] section
vim .mise.toml
# Update install script
vim install.sh
```

## 📦 GitOps Workflow

### Initial setup on new machine:
```bash
git clone https://github.com/mikkihugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles && ./install.sh
```

### Update environment:
```bash
cd ~/.dotfiles
git pull
./install.sh  # Re-run to apply changes
```

### Sync changes from current machine:
```bash
cd ~/.dotfiles
# Copy updated configs
cp ~/.bashrc config/
cp ~/.tmux.conf config/
# Commit and push
git add . && git commit -m "Update config"
git push
```

## 🌐 Remote Development

### SSH/Mosh Integration
- **Auto tmux** on SSH connections
- **Mosh wrapper** with optimized settings
- **Connection monitoring** tools

### Cloud Development
Perfect for:
- **Remote servers** 
- **Container development**
- **Cloud IDEs**
- **Multiple machine sync**

## 🛠️ Troubleshooting

### Python SQLite Issues
The install script automatically handles SQLite headers for Python compilation.

### Tmux Not Auto-starting
Check that the SSH detection works:
```bash
echo $SSH_CLIENT
source ~/.tmux-auto.sh
```

### Missing Tools
Re-run installation:
```bash
cd ~/.dotfiles && ./install.sh
```

## 🤝 Contributing

1. Fork this repository
2. Create your feature branch
3. Commit your changes  
4. Push to the branch
5. Create a Pull Request

## 📜 License

MIT License - Feel free to use and modify!

## 🙏 Acknowledgments

- [Mise](https://mise.jdx.dev/) - Modern version manager
- [ASDF](https://asdf-vm.com/) - Original version manager
- [Starship](https://starship.rs/) - Beautiful prompt
- [Tmux](https://github.com/tmux/tmux) - Terminal multiplexer
- [Modern CLI tools](https://github.com/ibraheemdev/modern-unix) - Inspiration

---

**Happy coding!** 🚀 If you have questions, open an issue!