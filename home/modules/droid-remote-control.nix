# Factory Droid Remote Control: one managed daemon owner.
#
# Purpose: Manage the Factory Droid Remote Control daemon lifecycle through
# the dotfiles Home Manager profile instead of an ad hoc foreground process.
# Consumer: Factory Remote Control clients and the operator on
# cc-se-sto-devbox-01.
# Contract: docs/work/2026-10-27-droid-remote-control/purpose.contract.json
# fields purpose, consumer, contract, failure_boundary, and invariants.
# What tests should verify: contract ownership, the managed Droid command,
# registration conditions, default-target enablement, and failure restart.
{
  lib,
  hostname ? "",
  ...
}: {
  systemd.user.services.droid-remote-control =
    lib.mkIf
    (lib.toLower hostname == "cc-se-sto-devbox-01") {
      Unit = {
        Description = "Factory Droid Remote Control daemon";
        After = ["default.target"];
        # Registration is machine-local and account-facing, so dotfiles never
        # create or remove it. The service starts only after registration exists.
        ConditionPathExists = [
          "%h/.local/bin/droid"
          "%h/.factory/computer.json"
        ];
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
        # A Home Manager switch must not disconnect a live Remote Control
        # session merely because the unit text changed.
        X-RestartIfChanged = false;
      };
      Service = {
        Type = "simple";
        ExecStart = "%h/.local/bin/droid daemon --remote-control";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = ["default.target"];
    };
}
