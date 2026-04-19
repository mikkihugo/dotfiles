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

    enableOpenclawNode = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableOpenclawNode or false;
      description = "Whether this machine should run the OpenClaw node service.";
    };

    enableRemoteAgent = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableRemoteAgent or true;
      description = "Whether this machine should run the local machine-agent service.";
    };

    validateSudoAccess = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.validateSudoAccess or true;
      description = "Whether bootstrap should validate sudo access.";
    };
  };
}
