{
  config,
  lib,
  ...
}: let
  machineConfigPath = "${config.home.homeDirectory}/.config/dotfiles/machine-role.json";
  machineConfig =
    if builtins.pathExists machineConfigPath
    then builtins.fromJSON (builtins.readFile machineConfigPath)
    else {};
in {
  options.dotfiles.machine = {
    role = lib.mkOption {
      type = lib.types.str;
      default = machineConfig.role or "general";
      description = "Local machine role selected during bootstrap.";
    };

    enableHermesProxy = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableHermesProxy or false;
      description = "Whether this machine should run the Hermes proxy gateway.";
    };

    enableTailscale = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableTailscale or false;
      description = "Whether this machine should install and join tailscale. Set true on laptops/desktops; leave false on servers where tailscale is not needed.";
    };

    tailnetHostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = machineConfig.tailnetHostname or null;
      description = "Optional Tailscale hostname override. Use this when the OS hostname should differ from the tailnet identity, such as WSL nodes that should present a simpler Linux-first name.";
    };

    validateSudoAccess = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.validateSudoAccess or true;
      description = "Whether bootstrap should validate sudo access.";
    };
  };
}
