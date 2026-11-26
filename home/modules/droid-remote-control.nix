# Factory Droid Remote Control: one managed daemon and provider-env owner.
#
# Purpose: Manage the Factory Droid Remote Control daemon lifecycle through
# the dotfiles Home Manager profile instead of an ad hoc foreground process.
# Consumer: Factory Remote Control clients and the operator on
# cc-se-sto-devbox-01.
# Contract: docs/work/2026-10-27-droid-remote-control/purpose.contract.json
# fields purpose, consumer, contract, failure_boundary, and invariants.
# What tests should verify: contract ownership, the managed Droid command,
# registration conditions, ordered SOPS-backed provider-env rendering,
# environment injection, and restart after any daemon exit.
#
# Runtime checks:
#   systemctl --user status droid-remote-control.service
#   python3 docs/work/2026-10-27-droid-remote-control/evidence/check-runtime.py
# After first registration, start the daemon with:
#   systemctl --user start droid-remote-control.service
# After provider-key rotation, refresh both services with:
#   systemctl --user restart droid-provider-config.service droid-remote-control.service
# The CLI is npm-managed and auto-update is off, so update it by hand and
# restart the unit (https://docs.factory.com/remote-control.md):
#   npm install -g droid@latest && systemctl --user restart droid-remote-control.service
{
  config,
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  homeDir = config.home.homeDirectory;
  providerEnv = "${homeDir}/.config/factory/droid.env";
  renderProviderEnv = pkgs.writeShellApplication {
    name = "render-droid-provider-env";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      target="${providerEnv}"
      install -d -m 700 "$(dirname "$target")"

      temporary="$target.tmp.$$"
      cleanup() {
        if [ -n "$temporary" ]; then
          rm -f -- "$temporary"
        fi
      }
      trap cleanup EXIT

      render_provider_env() {
        key="$1"
        secret_file="$2"
        if [ ! -s "$secret_file" ]; then
          echo "Droid provider secret is missing: $secret_file" >&2
          return 1
        fi
        secret="$(cat "$secret_file")"
        printf '%s=%s\n' "$key" "$secret"
        unset secret
      }

      umask 077
      {
        render_provider_env \
          "MINIMAX_API_KEY" \
          "${config.sops.secrets.minimax_api_key.path}"
        render_provider_env \
          "KIMI_API_KEY" \
          "${config.sops.secrets.kimi_api_key.path}"
        render_provider_env \
          "OLLAMA_API_KEY" \
          "${config.sops.secrets.ollama_api_key.path}"
      } > "$temporary"
      chmod 600 "$temporary"
      mv -f "$temporary" "$target"
      temporary=""
    '';
  };
  onDevbox = lib.toLower hostname == "cc-se-sto-devbox-01";
in {
  systemd.user.services.droid-provider-config = lib.mkIf onDevbox {
    Unit = {
      Description = "Render Factory Droid provider credentials";
      Requires = ["sops-nix.service"];
      After = ["sops-nix.service"];
      Before = ["droid-remote-control.service"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${renderProviderEnv}/bin/render-droid-provider-env";
      UMask = "0077";
      RemainAfterExit = true;
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.droid-remote-control = lib.mkIf onDevbox {
    Unit = {
      Description = "Factory Droid Remote Control daemon";
      After = [
        "default.target"
        "droid-provider-config.service"
      ];
      Requires = ["droid-provider-config.service"];
      # Registration is machine-local and account-facing, so dotfiles never
      # create or remove it. The service starts only after registration exists.
      ConditionPathExists = [
        "%h/.local/bin/droid"
        "%h/.factory/computer.json"
      ];
      # The start limit is the guard that makes Restart=always safe: a daemon
      # that cannot start stops after 5 attempts in 5 minutes instead of
      # looping forever.
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
      # sd-switch, invoked by Home Manager on switch, reads this and leaves a
      # changed unit running instead of restarting it.
      X-RestartIfChanged = false;
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/droid daemon --remote-control";
      EnvironmentFile = "%h/.config/factory/droid.env";
      # Factory never wakes a Remote Control computer whose daemon is offline,
      # so the unit comes back after any exit, not only after a failure
      # (https://docs.factory.com/remote-control.md).
      Restart = "always";
      RestartSec = "5s";
      KillMode = "control-group";
    };
    Install.WantedBy = ["default.target"];
  };
}
