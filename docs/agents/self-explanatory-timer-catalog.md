# Self-explanatory timer catalog (cc-se-sto-devbox-01)

Date: 2026-09-11
Source: `systemctl --user list-unit-files '*.timer'` + `systemctl --user list-timers --all` + `systemctl list-timers --all`. Total: 35 timer unit-files on disk (25 user + 10 system); 23 user unit-files currently appear in `list-timers --all` (21 distinct names; `hot-source-fsn1.timer` and `engine-workspace-reconcile.timer` are loaded but have no `NEXT` schedule on the captured snapshot).
Naming convention: `<scope>-<subject>-<verb>.timer` (best-effort; many entries use parens as placeholders where the unit name does not decompose cleanly).
Scope note: this catalog covers only **devbox systemd timers**. Kubernetes CronJobs on the cluster (≈30 entries; `kubectl get cronjobs -A`) are tracked separately and out of scope.

## Why this exists

A previous version of this devbox had a mix of timer names — some with all
three fields (e.g. `jcode-swarm-fleet-watchdog.timer`), some with only the
scope (e.g. `jcode-gc.timer`). When triaging a runbook at 03:00, "which
timer cleans X?" required a `systemctl cat` to read the unit. This
catalog is the agent-side lookup: every timer is mapped to a
self-explanatory phrase so an agent or operator can answer the
question without leaving the terminal.

## User timers (23 unit-files on disk / 21 active in list-timers)

| Timer | Cadence | Scope | Subject | Verb | Self-explanatory |
|---|---|---|---|---|---|
| `health-alarm.timer` | 1m | (engine) | service health | alarm | Engine self-health ping; emits the OTel `service.health` metric the cluster alertmanager watches |
| `jcode-swarm-fleet-watchdog.timer` | 5m | jcode | swarm fleet | watchdog | Pings the jcode swarm Fleet remote to confirm its heartbeat is fresh; pages if it has been silent too long |
| `reap-abandoned-searches.timer` | 5m | (jcode) | abandoned searches | reap | Sweeps jcode search tables for `status='abandoned'` rows older than the grace window and drops them |
| `dotfiles-auto-update.timer` | 30m | dotfiles | (sources) | auto-update | Re-evaluates `~/.dotfiles` flake and rebuilds home-manager activation when inputs change |
| `hot-source-hel1.timer` | 30m | hot-source | hel1 | (rebuild) | Rebuilds the devbox hot-path nix closures used by interactive `direnv` sessions (e.g. `se-vcs`, `repo`) |
| `hot-source-fsn1.timer` | 30m (`OnCalendar=*:15/30:00`; loaded but no `NEXT` on snapshot) | hot-source | fsn1 | (rebuild) | FSN1 counterpart of `hot-source-hel1.timer`; unit file present, currently outside the active schedule |
| `sshid-key-sync.timer` | 30m | sshid | key | sync | Pulls the operator SSH pubkey into `~/.ssh/authorized_keys` so the nixos-host-operator can reach this host |
| `budget-autofix-watchdog.timer` | 20m | budget | (events) | autofix watchdog | Watches for budget-overshoot events and auto-applies a cost-cap fixup |
| `jcode-swarm-auto-deploy.timer` | 25m | jcode | swarm | auto-deploy | Triggers a fleet auto-deploy of jcode-worker if a newer image is published |
| `jcode-workspace-janitor.timer` | 30m | jcode | workspace | janitor | Cleans orphan jcode worktrees under `~/.kimi-code/scratch` |
| `disk-cleanup.timer` | 1h | (system) | disk | cleanup | Trims the devbox's `/var/log` and `/tmp` when disk usage crosses threshold |
| `home-emergency-backup-fsn1.timer` | 12h | home | emergency backup | (fsn1) | Snapshots `~` to FSN1 backup target on emergency criteria |
| `home-emergency-backup-hel1.timer` | 24h | home | emergency backup | (hel1) | Snapshots `~` to HEL1 backup target on emergency criteria |
| `jcode-session-cleanup.timer` | 24h | jcode | session | cleanup | Prunes kimi-code session files > 7d old |
| `engine-workspace-reconcile.timer` | 24h | engine | workspace | reconcile | Reconciles `engine-git-bind-mount` and lane registry rows; closes the `engine-workspace-reconcile` sweep cycle |
| `purpose-first-audit.timer` | 24h | purpose-first | (drift) | audit | Audits every repo's `.purpose/lock.json` against the live managed block and reports drift |
| `jcode-gc.timer` | 24h | jcode | (build artifacts) | gc | Garbage-collects jcode session/build artifacts |
| `nix-gc-sweep.timer` | 24h | nix | gc roots | sweep | Sweeps the Nix store GC roots that the devbox no longer needs |
| `systemd-tmpfiles-clean.timer` | 24h | systemd | tmpfiles | clean | Runs `systemd-tmpfiles --clean` for `/tmp` age-out |
| `mise-auto-update.timer` | 24h | mise | (toolchain) | auto-update | Refreshes `mise` runtime shims to the latest pinned toolchain |
| `long-term-cleanup.timer` | weekly (Sun 04:00) | nix | long-term cache | cleanup | Weekly Nix-managed long-term cache cleanup (Sunday 04:00) |
| `nix-index-update.timer` | weekly | nix | (file index) | update | Weekly Nix-generated file-index update |
| `engine-worktree-cleanup.timer` | daily 04:40 | engine | worktree | cleanup | Retires stale `singularity-engine` jj task workspaces via `repo vcs workspace-reconcile` |

> Note: `budget-autofix-watchdog` and `engine-worktree-cleanup` were
> not given new names; both already convey the scope + subject + verb.

> Coverage caveat: a row in this table is **documentation**, not runtime
> truth. Two user unit-files (`nix-index-update.timer`, `long-term-cleanup.timer`)
> were missing from the original draft and were back-filled on 2026-09-11
> after the adversarial review. The drift detector below catches this if it
> re-occurs.

## System timers (10)

| Timer | Cadence | Scope | Subject | Verb | Self-explanatory |
|---|---|---|---|---|---|
| `devbox-disk-pressure.timer` | 5m | devbox | disk pressure | (alert) | Polls `df` and triggers `devbox-disk-pressure.service` if free% < threshold |
| `jcode-primary-refresh.timer` | 30m | jcode | primary | refresh | Refreshes the jcode canonical primary checkout (per NixosHost operator) |
| `logrotate.timer` | daily | (system) | logs | rotate | Standard logrotate |
| `engine-default-refresh.timer` | 30m | engine | default | refresh | Re-evaluates the singularity-engine default branch into the read-only mount |
| `devshell-prewarm.timer` | 1h | devbox | devshells | prewarm | Pre-warms direnv shells for active lanes so `cd` is instant |
| `nix-gc.timer` | 12h | nix | (store) | gc | `nix-collect-garbage` based on the nix-gc-sweep output |
| `nix-generation-prune.timer` | 24h | nix | generations | prune | Removes old Nix system generations |
| `systemd-tmpfiles-clean.timer` | 24h | systemd | tmpfiles | clean | Same name as user-level one but for system paths |
| `fstrim.timer` | weekly | (system) | (ssds) | fstrim | TRIMs SSDs |
| `k3s-host-split-dns.timer` | weekly | k3s | host split dns | (refresh) | Triggers k3s split-DNS refresh on host-local changes |

## Suggested renames (operator-gated)

If a future cleanup pass renames for consistency, here is the proposal.
Each is a 1-line change in the corresponding unit file or `.nix` source:

| Current | Proposed |
|---|---|
| `jcode-gc.timer` | `jcode-build-artifacts-gc-daily.timer` |
| `nix-gc.timer` | `nix-store-gc-twelve-hourly.timer` |
| `nix-gc-sweep.timer` | `nix-gc-roots-sweep-daily.timer` |
| `engine-default-refresh.timer` | `engine-default-branch-refresh-half-hourly.timer` |
| `engine-workspace-reconcile.timer` | `engine-workspace-reconcile-daily.timer` |
| `engine-worktree-cleanup.timer` | `engine-worktree-cleanup-daily.timer` |
| `purpose-first-audit.timer` | `purpose-first-drift-audit-daily.timer` |
| `jcode-session-cleanup.timer` | `jcode-session-prune-daily.timer` |
| `jcode-workspace-janitor.timer` | `jcode-workspace-janitor-half-hourly.timer` |
| `jcode-swarm-auto-deploy.timer` | `jcode-swarm-auto-deploy-quarter-hourly.timer` |
| `jcode-swarm-fleet-watchdog.timer` | `jcode-swarm-fleet-watchdog-five-minutely.timer` |
| `budget-autofix-watchdog.timer` | `budget-autofix-watchdog-twenty-minutely.timer` |
| `reap-abandoned-searches.timer` | `reap-abandoned-searches-five-minutely.timer` |
| `hot-source-hel1.timer` | `hot-source-hel1-rebuild-half-hourly.timer` |
| `disk-cleanup.timer` | `disk-cleanup-hourly.timer` |
| `dotfiles-auto-update.timer` | `dotfiles-auto-update-half-hourly.timer` |
| `sshid-key-sync.timer` | `sshid-key-sync-half-hourly.timer` |
| `mise-auto-update.timer` | `mise-auto-update-daily.timer` |
| `home-emergency-backup-fsn1.timer` | `home-emergency-backup-fsn1-twelve-hourly.timer` |
| `home-emergency-backup-hel1.timer` | `home-emergency-backup-hel1-daily.timer` |
| `devbox-disk-pressure.timer` | `devbox-disk-pressure-five-minutely.timer` |
| `devshell-prewarm.timer` | `devshell-prewarm-hourly.timer` |
| `jcode-primary-refresh.timer` | `jcode-primary-refresh-half-hourly.timer` |
| `k3s-host-split-dns.timer` | `k3s-host-split-dns-weekly.timer` |
| `fstrim.timer` | `ssd-fstrim-weekly.timer` |
| `logrotate.timer` | `logrotate-daily.timer` |
| `systemd-tmpfiles-clean.timer` | `systemd-tmpfiles-clean-daily.timer` |
| `nix-generation-prune.timer` | `nix-generations-prune-daily.timer` |

> All renames require operator authority (these are Nix-managed systemd
> units or system-level unit files outside `repo vcs` scope).

## Self-audit

- Snapshot source: `systemctl --user list-unit-files '*.timer'` + `systemctl --user list-timers --all` + `systemctl list-timers --all` captured 2026-09-11.
- Falsifier (drift detector): any enabled timer unit-file that is **not** documented in either table above is a documentation bug. The detector below catches it.

  ```sh
  #!/usr/bin/env bash
  # self-explanatory-timer-catalog drift detector
  set -euo pipefail
  catalog=~/.dotfiles/docs/agents/self-explanatory-timer-catalog.md

  live_user=$(systemctl --user list-unit-files '*.timer' --no-legend --state=enabled,disabled,static,generated \
              | awk '{print $1}' | sed 's/\.timer$//' | sort -u)
  live_sys=$(systemctl list-unit-files '*.timer' --no-legend --state=enabled,disabled,static,generated \
             | awk '{print $1}' | sed 's/\.timer$//' | sort -u)

  # Extract timer names from the markdown pipe tables (column 2 of every data row)
  docd=$(awk -F'|' '/^\| `/ && $2 ~ /timer/ {gsub(/[` ]/,"",$2); print $2}' "$catalog" \
         | sed 's/\.timer$//' | sort -u)

  # Globally sorted + de-duplicated union of live timers (comm needs sorted input).
  # systemd-tmpfiles-clean legitimately appears in both user and system; dedupe it.
  live_all=$(printf '%s\n%s\n' "$live_user" "$live_sys" | sort -u)

  # Only flag live timers missing from the catalog (catalog may legitimately
  # mention more than is enabled, e.g. masked units).
  comm -23 <(printf '%s\n' "$live_all") <(printf '%s\n' "$docd")
  ```

  Anything that prints is a live timer with no entry in the catalog.
  Re-run after editing; empty output = no drift. The exit status of the
  script is `comm`'s (0 = no common suppression, 1 = items only-in-file1
  printed, 2 = error). The drift signal is the printed text, not the exit
  code — do not gate on the exit code alone.

- What the detector does NOT catch:
  - Cadence / `OnCalendar` drift on a documented timer (the column is prose).
  - `Description=` field drift (the catalog has its own phrase).
  - Service unit pairing drift (catalog tracks timers, not their `.service`).
  - K8s CronJobs (out of scope).

- Coverage caveat: timers I didn't list (zero here, post-2026-09-11 review) would mean a timer exists that has no self-explanatory entry; that's a documentation bug, not a runtime bug.
