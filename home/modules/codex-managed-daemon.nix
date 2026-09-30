{
  config,
  pkgs,
  lib,
  ...
}: {
  # Purpose: one native owner selects the daemon package and manages its lifecycle.
  # Consumer: Codex sessions using the shared local app-server.
  # Contract: docs/work/2026-09-30-codex-native-daemon/purpose.contract.json
  # fields purpose, consumer, contract, and invariants.
  # What tests should verify: contract ownership, native package selection,
  # version agreement at migration, and retirement of the standalone units.
  home.activation = {
    retireStandaloneCodexDaemon = lib.hm.dag.entryBetween ["linkGeneration"] ["writeBoundary"] ''
      codex_cli="${config.home.homeDirectory}/.local/bin/codex"
      if [ -x "$codex_cli" ]; then
        legacy_daemon="$(${pkgs.systemd}/bin/systemctl --user show --property=LoadState --value codex-managed-daemon.service)"
        case "$legacy_daemon" in
          loaded) "$codex_cli" app-server daemon update || exit $? ;;
          not-found) ;;
          *) echo "Unexpected legacy Codex unit state: $legacy_daemon" >&2; exit 1 ;;
        esac

        legacy_timer="$(${pkgs.systemd}/bin/systemctl --user show --property=LoadState --value codex-server-auto-update.timer)"
        if [ "$legacy_timer" != "not-found" ]; then
          ${pkgs.systemd}/bin/systemctl --user disable --now codex-server-auto-update.timer
          ${pkgs.systemd}/bin/systemctl --user stop codex-server-auto-update.service
        fi

        legacy_daemon="$(${pkgs.systemd}/bin/systemctl --user show --property=LoadState --value codex-managed-daemon.service)"
        if [ "$legacy_daemon" != "not-found" ]; then
          ${pkgs.systemd}/bin/systemctl --user disable --now codex-managed-daemon.service
        fi

        # Also retire the old projections when these activation entries are
        # applied alone, without deploying unrelated Home Manager settings.
        for legacy_unit in codex-managed-daemon.service codex-server-auto-update.service codex-server-auto-update.timer; do
          legacy_path="${config.home.homeDirectory}/.config/systemd/user/$legacy_unit"
          if [ -L "$legacy_path" ]; then
            case "$(${pkgs.coreutils}/bin/readlink "$legacy_path")" in
              /nix/store/*) ${pkgs.coreutils}/bin/rm "$legacy_path" ;;
            esac
          fi
        done
      fi
    '';

    bootstrapCodexManagedDaemon = lib.hm.dag.entryAfter ["reloadSystemd"] ''
      codex_cli="${config.home.homeDirectory}/.local/bin/codex"
      if [ -x "$codex_cli" ]; then
        if [ ! -f "${config.home.homeDirectory}/.codex/app-server-daemon/settings.json" ]; then
          "$codex_cli" app-server daemon bootstrap --remote-control
        else
          "$codex_cli" app-server daemon enable-remote-control
          "$codex_cli" app-server daemon start
        fi
      fi
    '';
  };
}
