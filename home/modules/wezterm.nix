# home/modules/wezterm.nix — WezTerm terminal config
#
# IBM Carbon × Dracula theme: orange (#FF832B) as the signature accent
# ("IBM Big Orange" instead of IBM's traditional blue).
# WezTerm on this host is a native Linux client. Native Windows is a separate
# machine; do not project into /mnt/c (a WSL-only path). Keep the shared source
# in config/wezterm/wezterm.lua and sync the Windows copy through its native
# Windows workflow.
_: {
  home.file.".config/wezterm/wezterm.lua" = {
    source = ../../config/wezterm/wezterm.lua;
    force = true;
  };
}
