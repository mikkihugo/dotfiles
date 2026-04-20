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
      description = "Whether this machine should run the legacy OpenClaw node service.";
    };

    enableHermesProxy = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableHermesProxy or false;
      description = "Whether this machine should run the Hermes proxy gateway. Mutually exclusive with enableOpenclawNode at runtime (both write to ~/.hermes / ~/.openclaw respectively; a single host can run both services concurrently but they share no state).";
    };

    enableRemoteAgent = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.enableRemoteAgent or false;
      description = "Whether this machine should run the local machine-agent service. Disabled by default until the Go+tsnet rewrite lands — the legacy Rust agent was removed after Codex flagged its exec surface as too broad.";
    };

    validateSudoAccess = lib.mkOption {
      type = lib.types.bool;
      default = machineConfig.validateSudoAccess or true;
      description = "Whether bootstrap should validate sudo access.";
    };
  };
}
