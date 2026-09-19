{
  lib,
  pkgs,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  home.file.".local/bin/minimax-responses-compat" = {
    source = ./minimax-responses-compat.py;
    executable = true;
  };

  systemd.user.services.minimax-responses-compat = {
    Unit = {
      Description = "MiniMax Responses compatibility proxy for Grok";
      After = ["default.target"];
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 %h/.local/bin/minimax-responses-compat";
      Restart = "on-failure";
      RestartSec = 3;
      Environment = [
        "MINIMAX_RESPONSES_UPSTREAM=https://api.minimax.io/v1"
        "MINIMAX_RESPONSES_LISTEN_HOST=127.0.0.1"
        "MINIMAX_RESPONSES_LISTEN_PORT=18787"
      ];
    };
    Install.WantedBy = ["default.target"];
  };
}
