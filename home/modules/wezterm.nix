# home/modules/wezterm.nix — WezTerm terminal config
#
# IBM Carbon × Dracula theme: orange (#FF832B) as the signature accent
# ("IBM Big Orange" instead of IBM's traditional blue).
# WezTerm on WSL2 reads config from the Linux home via \\wsl.localhost\...
# Config is managed here; do not edit ~/.config/wezterm/wezterm.lua directly.
_: {
  home.file.".config/wezterm/wezterm.lua" = {
    source = ../../config/wezterm/wezterm.lua;
    force = true;
  };
}
