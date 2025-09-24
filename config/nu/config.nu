# Nushell Configuration
# ~/.dotfiles/config/nu/config.nu

# Welcome message
echo "🚀 Welcome to Nushell - A modern shell with structured data"
echo "   Type 'help' for documentation"
echo "   Type 'sh-switch' to change shells"

# Environment variables
$env.EDITOR = "hx"
$env.VISUAL = "hx"
$env.PAGER = "bat"
$env.BAT_THEME = "OneHalfDark"
$env.FD_THREADS = "4"

# Path configuration
$env.PATH = ($env.PATH | split row (char esep) | prepend [
    "~/.local/bin"
    "~/.dotfiles/.scripts"
    "~/.cargo/bin"
    "~/go/bin"
] | uniq)

# Mise integration

# Starship prompt
if (which starship | is-not-empty) {
    starship init nu | save -f ~/.cache/starship_init.nu
    source ~/.cache/starship_init.nu
}

# Aliases - Modern tools
alias ls = eza
alias ll = eza -la --git --time-style=relative
alias la = eza -a
alias l = eza -l --git
alias tree = eza --tree
alias cat = bat --paging=never
alias grep = rg
alias find = fd --threads=4
alias ps = procs
alias du = dust
alias df = duf
alias top = btop

# Navigation aliases
alias .. = cd ..
alias ... = cd ../..
alias .... = cd ../../..
alias c = cd ~/code

# Git aliases
alias g = git
alias gs = git status
alias ga = git add
alias gc = git commit
alias gp = git push
alias gl = git pull
alias gd = git diff
alias gco = git checkout
alias gb = git branch

# Docker aliases
alias d = docker
alias dc = docker-compose
alias dps = docker ps

# Kubernetes aliases
alias k = kubectl
alias kgp = kubectl get pods
alias kgs = kubectl get services

# Shell switching
alias sh-switch = ~/.dotfiles/.scripts/shell-switcher.sh
alias sh-bash = exec bash --login
alias sh-zsh = exec zsh
alias sh-dune = exec dunesh

# Claude safety
alias claude-shell = ~/.dotfiles/.scripts/claude-shell.sh
alias safe-run = ~/.dotfiles/.scripts/claude-safe-wrapper.sh

# Smart repo navigation
def c [pattern?: string] {
    if ($pattern == null) {
        cd ~/code
    } else {
        let matches = (fd -t d -d 1 $"*($pattern)*" ~/code --base-directory ~/code | lines)
        
        match ($matches | length) {
            0 => { echo $"No repos matching '($pattern)'" }
            1 => { cd $"~/code/($matches | first)" }
            _ => {
                let selected = ($matches | to text | fzf --reverse --height=40% --prompt=$"Multiple matches for '($pattern)': " | str trim)
                if ($selected | is-not-empty) {
                    cd $"~/code/($selected)"
                }
            }
        }
    }
}

# Create repo shortcuts
def create-repo-aliases [] {
    if (ls ~/code | is-not-empty) {
        ls ~/code | where type == dir | each { |it|
            let alias_name = $"c($it.name)"
            alias $alias_name = cd $"~/code/($it.name)"
        }
    }
}
create-repo-aliases

# Better cd with auto-ls
def --env cd [path?: string] {
    let path = ($path | default "~")
    builtin cd $path
    if ((ls | length) < 20) {
        ll
    }
}

# Zoxide integration
def --env z [...args: string] {
    if (which zoxide | is-not-empty) {
        let path = (zoxide query ...$args)
        cd $path
    } else {
        echo "zoxide not installed"
    }
}

# Custom completions
def "nu-complete code repos" [] {
    ls ~/code | where type == dir | get name
}

extern "c" [
    repo?: string@"nu-complete code repos"
]

# Key bindings
$env.config = {
    show_banner: false
    
    keybindings: [
        {
            name: fuzzy_history
            modifier: control
            keycode: char_r
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    { send: menu name: history_menu }
                    { send: menupagenext }
                ]
            }
        }
    ]
    
    history: {
        max_size: 100_000
        sync_on_enter: true
        file_format: "sqlite"
    }
    
    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "fuzzy"
    }
}

# Helper functions
def help-shells [] {
    echo "
Nushell Quick Reference:

Navigation:
  c              - cd to ~/code
  c <pattern>    - cd to repo matching pattern
  z <query>      - smart cd with zoxide
  
Tables and Data:
  ls | where size > 1mb
  ps | where cpu > 10
  open data.json | where score > 90
  
Git:
  gs  - git status
  ga  - git add
  gc  - git commit
  gp  - git push
  
Shell Management:
  sh-switch     - interactive shell switcher
  claude-shell  - resource-limited shell
  safe-run      - run command with limits
"
}
