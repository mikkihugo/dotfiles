{ config, lib, pkgs, ... }: let
  homeDirectory = config.home.homeDirectory;
  openChamberSecretsDirectory = "${homeDirectory}/.config/openchamber";
  openChamberSecretsPath = "${openChamberSecretsDirectory}/secrets.env";
  openChamberServiceWrapper = pkgs.writeShellScript "openchamber-service" ''
    export PATH="${homeDirectory}/.npm-global/bin:${homeDirectory}/.local/bin:/run/current-system/sw/bin:${pkgs.bun}/bin:/usr/bin:/bin:$PATH"
    exec ${pkgs.bun}/bin/bunx @openchamber/web serve --foreground --port 3000
  '';
in {
  home.activation.ensureOpenChamberSecretsDirectory = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${openChamberSecretsDirectory}"
    chmod 700 "${openChamberSecretsDirectory}"
  '';

  systemd.user.services.openchamber = {
    Unit = {
      Description = "OpenChamber Central Web UI";
      After = [ "network.target" ];
    };

    Install = {
      WantedBy = [ "default.target" ];
    };

    Service = {
      Type = "simple";
      WorkingDirectory = "${homeDirectory}/code";
      Environment = [
        "OPENCHAMBER_HOST=127.0.0.1"
        "OPENCHAMBER_OPENCODE_HOSTNAME=127.0.0.1"
      ];
      EnvironmentFile = openChamberSecretsPath;
      ExecStart = openChamberServiceWrapper;
      Restart = "on-failure";
      RestartSec = "2";
      NoNewPrivileges = true;
    };
  };
}
