# home/modules/sshid-key-sync.nix
#
# Detects new keys published at https://sshid.io/mhugo and commits them into
# config/ssh/authorized_keys.sshid so home-manager activation
# (mergeDeclaredAuthorizedKeys, see activation.nix) picks them up on the next
# `hms`. Never touches ~/.ssh/authorized_keys directly and never pushes:
# pushing is git-auto-backup's job, and applying the new key stays tied to
# `hms`, same as every other dotfiles change -- see scripts/sync-sshid-keys
# for why that boundary matters here.
{pkgs, ...}: let
  sync = pkgs.writeShellApplication {
    name = "sshid-key-sync";
    runtimeInputs = [pkgs.python3 pkgs.curl pkgs.git pkgs.libnotify];
    text = ''
      python3 "$HOME/.dotfiles/scripts/sync-sshid-keys"
    '';
  };
in {
  systemd.user.services.sshid-key-sync = {
    Unit.Description = "Sync new sshid.io keys into the dotfiles snapshot";
    Service = {
      Type = "oneshot";
      ExecStart = "${sync}/bin/sshid-key-sync";
    };
  };

  systemd.user.timers.sshid-key-sync = {
    Unit.Description = "Periodically check sshid.io for new keys";
    Timer = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5min";
      Persistent = true;
      Unit = "sshid-key-sync.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
