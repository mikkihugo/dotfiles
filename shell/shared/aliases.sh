#!/bin/bash
# Shared aliases sourced by any interactive shell

have() {
  command -v "$1" >/dev/null 2>&1
}

if have rg; then
  alias grep='rg'
fi

if have fd; then
  alias find='fd'
fi

if have eza; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -la --icons --group-directories-first'
  alias lt='eza --tree --level=2 --icons'
else
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
  alias lt='ls -la'
fi

if have bat; then
  alias cat='bat --paging=never'
fi

if have procs; then
  alias ps='procs'
fi

if have dust; then
  alias du='dust'
else
  alias du='du -h'
fi

if have duf; then
  alias df='duf'
else
  alias df='df -h'
fi

if have sd; then
  alias sed='sd'
fi

if have btop; then
  alias top='btop'
  alias htop='btop'
elif have htop; then
  alias top='htop'
fi

if have delta; then
  alias diff='delta'
fi

if have doggo; then
  alias dig='doggo'
fi

if have hyperfine; then
  alias time='hyperfine'
fi

if have zoxide; then
  alias cd='z'
fi

if have hx; then
  alias vi='hx'
  alias vim='hx'
fi

if have tokei; then
  alias wc='tokei'
fi

if have watchexec; then
  alias watch='watchexec'
fi

if have jaq; then
  alias jq='jaq'
fi

if have gron; then
  alias json='gron'
fi

if have git; then
  alias g='git'
  alias gs='git status'
  alias ga='git add'
  alias gc='git commit'
  alias gp='git push'
  alias gl='git pull'
  alias gd='git diff'
  alias gco='git checkout'
  alias gb='git branch'
  alias glog='git log --oneline --graph --decorate'
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd ~'
alias c='cd ~/code'

alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'
alias mkdir='mkdir -p'

if have docker; then
  alias d='docker'
  alias dc='docker compose'
  alias dps='docker ps'
  alias di='docker images'
fi
unset -f have
