# home/modules/wezterm.nix — WezTerm terminal config
#
# IBM Carbon × Dracula theme: orange (#FF832B) as the signature accent
# ("IBM Big Orange" instead of IBM's traditional blue).
# WezTerm runs on Windows — it reads from the Windows filesystem, not WSL2.
# Both paths are kept in sync: Linux (for tooling) + Windows (what WezTerm reads).
# Do not edit either path directly — edit config/wezterm/wezterm.lua instead.
_: {
  home.file.".config/wezterm/wezterm.lua" = {
    source = ../../config/wezterm/wezterm.lua;
    force = true;
  };

  # Windows path — this is what WezTerm on Windows actually reads.
  # Hardcoded to the Windows user profile via the WSL2 /mnt/c mount.
  home.file."/mnt/c/Users/mikki/.config/wezterm/wezterm.lua" = {
    source = ../../config/wezterm/wezterm.lua;
    force = true;
  };
}
