# Direct WezTerm devbox mux

This packet records the corrected topology: the Windows WezTerm GUI connects
to the devbox's native WezTerm SSH multiplexer. The obsolete Vega, PowerShell,
and tmux launcher is removed; the same Lua source remains safe when loaded by
the Linux-side remote mux server.

The Windows client starts with `connect devbox`. New tabs use the named
`devbox` domain, while the remote server uses its local login shell.
