# Termius Snippets for Better Integration

## Auto-attach to tmux with menu
```bash
bash -l -c 'source ~/.bashrc && source ~/.dotfiles/.scripts/tmux-startup.sh'
```

## Direct project session
```bash
tmux new-session -s ${project} -c ~/projects/${project} || tmux attach -t ${project}
```

## Mosh with tmux (for poor connections)
```bash
mosh --server="LC_ALL=en_US.UTF-8 mosh-server" ${host} -- tmux attach || tmux new
```

## Quick system check
```bash
echo "=== $(hostname) ===" && uptime && free -h && df -h / | tail -1 && tmux ls 2>/dev/null || echo "No tmux sessions"
```

## Auto-create named session
```bash
SESSION="${host%%.*}"; tmux new -s "$SESSION" || tmux attach -t "$SESSION"
```

## Jump through bastion
In Termius, set up:
- Host: your-target-host
- Proxy: your-bastion-host
- Then use normal startup command

## Fix terminal issues
```bash
export TERM=xterm-256color && exec bash -l
```