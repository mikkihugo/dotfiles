{pkgs, ...}: let
  # Runtime-dir path: tmpfs, per user, gone at logout/reboot. Rewritten by the
  # timer below, so it never outlives the OpenBao secret by more than a period.
  tokenFile = "/run/user/1000/forgejo-token";

  refresh = pkgs.writeShellScript "forgejo-token-file" ''
    set -euo pipefail
    umask 077
    export BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}"
    tmp="$(${pkgs.coreutils}/bin/mktemp "${tokenFile}.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f -- "$tmp"' EXIT
    # The value goes file-to-file only: never argv, never the journal.
    ${pkgs.openbao}/bin/bao kv get -mount=kv -field=token forgejo/cli-mhugo >"$tmp"
    if [[ ! -s "$tmp" ]]; then
      echo "forgejo-token-file: OpenBao returned an empty token; keeping the existing file" >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/mv -f -- "$tmp" "${tokenFile}"
    trap - EXIT
    echo "forgejo-token-file: refreshed ${tokenFile}"
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
        Description = "Write the Forgejo API token from OpenBao to the runtime dir (0600)";
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
      Unit.Description = "Refresh the Forgejo token file from OpenBao";
      Timer = {
        OnStartupSec = "20s";
        OnUnitActiveSec = "6h";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };

    # User services and new login sessions find the file through this variable.
    sessionVariables.FORGEJO_TOKEN_FILE = tokenFile;
  };
}
