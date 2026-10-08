{pkgs, ...}: let
  # Runtime-dir path: tmpfs, per user, gone at logout/reboot. Re-rendered by the
  # timer below (every 5 min; unchanged copies are left alone), so it never outlives
  # the OpenBao secret by more than one period.
  tokenFile = "/run/user/1000/forgejo-token";

  # scripts/forgejo-token-sync renders the token from OpenBao into the runtime
  # file and into every static copy a tool reads (fj, infra scripts, the
  # budget-autofix watchdog), so rotating is one `bao kv patch` plus a refresh.
  # The value goes file-to-file only: never argv, never the journal.
  refresh = pkgs.writeShellScript "forgejo-token-file" ''
    export PATH=${pkgs.lib.makeBinPath [pkgs.coreutils pkgs.gawk pkgs.jq]}
    export BAO_BIN=${pkgs.openbao}/bin/bao
    export FORGEJO_TOKEN_FILE=${tokenFile}
    exec ${pkgs.bash}/bin/bash ${../../scripts/forgejo-token-sync}
  '';
in {
  # Engine's in-process Forgejo client (singularity-repo-embedded, feature
  # `forgejo`) reads FORGEJO_TOKEN_FILE and refuses group/world-readable files.
  # Materialise the token from OpenBao instead of asking anyone to stage one by
  # hand: `bao` authenticates with ~/.vault-token, exactly as
  # home-emergency-backup does.
  systemd.user = {
    services.forgejo-token-file = {
      Unit = {
        Description = "Render the Forgejo API token from OpenBao into the runtime dir and tool copies (0600)";
        # Same rule as the other units here: never restart a live one under a caller.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${refresh}";
        Nice = 19;
        TimeoutStartSec = "1min";
      };
    };

    timers.forgejo-token-file = {
      Unit.Description = "Poll OpenBao and keep the Forgejo token copies current";
      Timer = {
        OnStartupSec = "20s";
        OnUnitActiveSec = "5min"; # a bao rotation reaches every copy within one period, no manual step
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    # User services and new login sessions find the file through this variable.
    sessionVariables.FORGEJO_TOKEN_FILE = tokenFile;
  };
}
