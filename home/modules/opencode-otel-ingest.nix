{pkgs, ...}: let
  refresh = pkgs.writeShellScript "opencode-otel-ingest" ''
    export PATH="$HOME/.local/bin:/run/current-system/sw/bin:${pkgs.lib.makeBinPath [pkgs.coreutils pkgs.gawk pkgs.openbao pkgs.kubectl]}"
    export BAO_BIN=${pkgs.openbao}/bin/bao
    exec ${pkgs.bash}/bin/bash ${../../scripts/sync-opencode-swarm-otel-from-bao.sh}
  '';
in {
  home = {
    file = {
      ".config/centralcloud/otel-ingest.env.example" = {
        source = ../../config/centralcloud/otel-ingest.env.example;
        force = true;
      };
      ".config/opencode/serve-with-otel.sh" = {
        source = ../../config/opencode/serve-with-otel.sh;
        executable = true;
        force = true;
      };
      # pnpm's global shim execs the store binary directly and bypasses ~/.local/bin/opencode,
      # so TUI-spawned `serve --service` missed fleet OTLP. Delegate to the HM wrapper.
      ".local/share/pnpm/bin/opencode" = {
        executable = true;
        force = true;
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          exec "$HOME/.local/bin/opencode" "$@"
        '';
      };
    };
  };

  systemd.user = {
    services.opencode-otel-ingest = {
      Unit = {
        Description = "Render opencode-swarm OTLP ingest env from OpenBao (0600)";
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${refresh}";
        Nice = 19;
        TimeoutStartSec = "1min";
      };
    };

    timers.opencode-otel-ingest = {
      Unit.Description = "Poll OpenBao and keep opencode OTLP ingest env current";
      Timer = {
        OnStartupSec = "25s";
        OnUnitActiveSec = "5min";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
