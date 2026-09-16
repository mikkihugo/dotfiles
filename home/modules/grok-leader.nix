# Shared Grok leader: one backend for TUI/ACP clients.
#
# Clients still need `[cli] use_leader = true` in ~/.grok/config.toml (Grok
# owns that file; Home Manager does not pin it). Cursor worker stays off.
{
  lib,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  systemd.user.services.grok-leader = {
    Unit = {
      Description = "Grok shared leader process";
      After = ["default.target"];
      ConditionPathExists = "%h/.local/bin/grok";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      # Wrapper unsets XAI_API_KEY and execs ~/.grok/bin/grok (OIDC).
      ExecStart = "%h/.local/bin/grok agent leader --no-exit-on-disconnect --no-auto-update --relay-on-demand";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = ["default.target"];
  };
}
