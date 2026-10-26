# Durable open-file limit for the systemd user manager.
# The user manager defaulted to soft nofile 1024; the shared Codex
# app-server started under it hit 1024 fds on 2026-10-26 and killed ~20
# jobs. Soft = hard so every user unit and its children inherit 524288.
_: {
  xdg.configFile."systemd/user.conf.d/50-nofile.conf".text = ''
    [Manager]
    DefaultLimitNOFILE=524288:524288
  '';
}
