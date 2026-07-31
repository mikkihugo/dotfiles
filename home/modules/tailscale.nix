# Home Manager owns the Tailscale client only. The host daemon, its persistent
# state, and tailnet enrolment are system-owned; never install or control them
# from a user activation hook.
{
  config,
  pkgs,
  lib,
  ...
}:
lib.mkIf config.dotfiles.machine.enableTailscale {
  home.packages = [pkgs.tailscale];
}
