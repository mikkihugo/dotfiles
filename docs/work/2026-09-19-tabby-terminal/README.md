# Work: 2026-09-19-tabby-terminal

JSON is authoritative. This packet adds the hash-pinned Eugeny/Tabby terminal client under Home Manager while deliberately retaining the existing `xterm-256color` terminfo contract. It must not use `pkgs.tabby`, which is the unrelated TabbyML coding-assistant server.
