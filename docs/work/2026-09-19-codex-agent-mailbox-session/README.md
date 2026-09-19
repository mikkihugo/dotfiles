# Codex direct mailbox session

The interactive Codex MCP reader must use `${principal}-agent`; the Home Manager
turn-boundary hook already uses `${principal}-hook`. This packet excludes server
authorization and all foreign inbox state.
