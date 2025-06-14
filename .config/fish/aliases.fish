#!/usr/bin/env fish
# Fish aliases for Rust utilities and modern tools

# Only create aliases if the tool exists
function safe_alias
    set cmd $argv[1]
    set target $argv[2]
    if command -v $target &>/dev/null
        alias $cmd $target
    else if test -x "$HOME/.local/share/mise/installs/$target/latest/$target"
        alias $cmd "$HOME/.local/share/mise/installs/$target/latest/$target"
    end
end

# Rust-based replacements for core utils
if command -v rg &>/dev/null
    alias grep 'rg'
end

if command -v fd &>/dev/null
    alias find 'fd'
end

if command -v eza &>/dev/null
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza -la --icons --group-directories-first --git'
    alias lt 'eza --tree --level=2 --icons'
    alias tree 'eza --tree --icons'
else
    alias ll 'ls -alF'
    alias la 'ls -A'
    alias l 'ls -CF'
end

if command -v lsd &>/dev/null
    # Alternative to eza
    alias lls 'lsd -la'
end

if command -v bat &>/dev/null
    alias cat 'bat --paging=never'
    alias less 'bat --paging=always'
end

if command -v bottom &>/dev/null
    alias top 'bottom'
    alias btm 'bottom'
    alias htop 'bottom'
end

if command -v btop &>/dev/null
    alias top 'btop'
    alias htop 'btop'
end

if command -v dust &>/dev/null
    alias du 'dust'
end

if command -v duf &>/dev/null
    alias df 'duf'
end

if command -v sd &>/dev/null
    alias sed 'sd'
end

if command -v delta &>/dev/null
    alias diff 'delta'
end

if command -v hyperfine &>/dev/null
    alias time 'hyperfine'
end

if command -v tokei &>/dev/null
    alias wc 'tokei'
    alias loc 'tokei'
end

if command -v grex &>/dev/null
    alias regex 'grex'
end

if command -v xh &>/dev/null
    alias http 'xh'
    alias https 'xh --https'
end

# Development tools
if command -v gitui &>/dev/null
    alias gg 'gitui'
end

if command -v lazygit &>/dev/null
    alias lg 'lazygit'
end

if command -v lazydocker &>/dev/null
    alias ld 'lazydocker'
end

if command -v yazi &>/dev/null
    alias fm 'yazi'
    alias ranger 'yazi'
end

if command -v helix &>/dev/null
    alias hx 'helix'
    alias vi 'helix'
    alias vim 'helix'
end

if command -v zellij &>/dev/null
    alias zj 'zellij'
    alias tmux 'zellij'
end

# Git helpers
if command -v git-cliff &>/dev/null
    alias changelog 'git-cliff'
end

if command -v gitleaks &>/dev/null
    alias leaks 'gitleaks detect'
end

# Container tools
if command -v dive &>/dev/null
    alias docker-analyze 'dive'
end

if command -v k9s &>/dev/null
    alias k9 'k9s'
end

# Utilities
if command -v gron &>/dev/null
    alias json-grep 'gron'
end

if command -v jq &>/dev/null
    alias json 'jq'
end

if command -v yq &>/dev/null
    alias yaml 'yq'
end

if command -v navi &>/dev/null
    alias cheat 'navi'
    alias howto 'navi'
end

if command -v just &>/dev/null
    alias j 'just'
end

if command -v watchexec &>/dev/null
    alias watch 'watchexec'
end

# Shell navigation (zoxide needs special handling)
if command -v zoxide &>/dev/null
    # Don't alias cd to z in fish - use the z command directly
    alias cdi 'zi'  # interactive mode
end

# Directory shortcuts
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'
alias ~ 'cd ~'
alias c 'cd ~/code'

# Safety nets
alias cp 'cp -i'
alias mv 'mv -i'
alias rm 'rm -i'
alias mkdir 'mkdir -p'

# Docker shortcuts
if command -v docker &>/dev/null
    abbr d 'docker'
    abbr dc 'docker compose'
    abbr dps 'docker ps'
    abbr dpsa 'docker ps -a'
    abbr di 'docker images'
    abbr dx 'docker exec -it'
    abbr dlog 'docker logs -f'
    abbr drm 'docker rm (docker ps -aq)'
    abbr drmi 'docker rmi (docker images -q)'
end

# Kubernetes
if command -v kubectl &>/dev/null
    abbr k 'kubectl'
    abbr kgp 'kubectl get pods'
    abbr kgs 'kubectl get services'
    abbr kgd 'kubectl get deployments'
    abbr kgi 'kubectl get ingress'
    abbr klog 'kubectl logs -f'
    abbr kexec 'kubectl exec -it'
end

if command -v kubectx &>/dev/null
    alias kctx 'kubectx'
    alias kns 'kubens'
end

# Python
if command -v python3 &>/dev/null
    alias py 'python3'
    alias python 'python3'
end

if command -v uv &>/dev/null
    alias pip 'uv pip'
    alias venv 'uv venv'
end

# System info
alias ports 'netstat -tuln 2>/dev/null || ss -tuln'
alias myip 'curl -s https://checkip.amazonaws.com'
alias weather 'curl wttr.in'

# Quick edits
alias fishrc 'eval $EDITOR ~/.config/fish/config.fish; and source ~/.config/fish/config.fish'
alias aliases 'eval $EDITOR ~/.config/fish/aliases.fish; and source ~/.config/fish/aliases.fish'
alias reload 'source ~/.config/fish/config.fish'

# Fun stuff
alias matrix 'cmatrix -s'
alias starwars 'telnet towel.blinkenlights.nl'

# Mise shortcuts
if command -v mise &>/dev/null
    abbr mi 'mise install'
    abbr mu 'mise use'
    abbr ml 'mise list'
    abbr mr 'mise run'
    abbr mx 'mise exec'
end

# Quick directory listing
abbr lsa 'ls -la'
abbr lst 'ls -lat'  # by time
abbr lss 'ls -laS'  # by size

# System management
alias diskspace 'df -h | /usr/bin/grep -E "^(/dev/|tmpfs)" | sort'
alias meminfo 'free -h; and echo ""; and ps aux --sort=-%mem | head'
alias cpuinfo 'lscpu | /usr/bin/grep -E "^(Model name|CPU\\(s\\)|Thread|Core)"'

# Network
alias listening 'ss -tlnp 2>/dev/null || netstat -tlnp'
alias connections 'ss -tan | /usr/bin/grep ESTABLISHED'

# Process management
alias psg 'ps aux | /usr/bin/grep -v grep | /usr/bin/grep'
alias topmem 'ps aux --sort=-%mem | head -20'
alias topcpu 'ps aux --sort=-%cpu | head -20'