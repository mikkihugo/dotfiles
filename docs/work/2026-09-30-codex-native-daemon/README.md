# Codex native daemon migration

Operator mandate: Mikael requested replacing the custom dotfiles daemon launcher and timer with native managed-daemon lifecycle.

PurposeContract and WorkSpec describe the scope and executable proof. The migration is reversible through the previous Home Manager module and package links. Runtime restart is authorized by the operator request.

## Verified result

The production update completed with CLI, selected package and running daemon at 0.159.2. The native updater is running, legacy systemd units are absent, remote control remains enabled, and the guardian remains masked. Repeated enable-remote-control/start preserved the daemon PID. The fresh TUI picker lists GPT-6.1-Sol.

Initial migration activation artifacts and logs record the earlier CLI-pinned handover; production-update-final.txt records the subsequent production selection. The final module uses production update before stopping the old owner, bootstraps initial setup only, and uses start for later activations.

Full Home Manager activation was not applied because the primary checkout contains unrelated changes. The native runtime migration was applied independently. Publication also repairs a stale test for the committed JCode allowlist removal, without changing provider configuration.
