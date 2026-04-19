{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.dotfiles.machine.enableRemoteAgent {
  systemd.user.services.machine-agent = {
    Unit = {
      Description = "Machine management HTTP agent";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "simple";
      EnvironmentFile = "%h/.config/dotfiles/machine-agent.env";
      ExecStart = "${config.home.homeDirectory}/.local/bin/machine-agent";
      Restart = "always";
      RestartSec = "10s";
    };
    Install.WantedBy = ["default.target"];
  };

  home.shellAliases = {
    machine-agent-status = "systemctl --user status machine-agent";
    machine-agent-logs = "journalctl --user -u machine-agent -f";
  };
}
