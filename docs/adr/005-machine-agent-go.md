# ADR-005: Machine agent in Go + tsnet, narrow RPCs only

**Status:** Accepted — implementation pending  
**Date:** 2026-04-21

## Context

The Rust `machine-agent` was retired after adversarial review flagged an
unbounded-exec vulnerability: the command allowlist forwarded arbitrary
arguments and working directory, allowing arbitrary file reads and service
control via any bearer token.

A replacement is needed for per-machine observability (health, logs, service
status) reachable from the central Hermes agent and any future dashboard.

## Decision

Build `tools/machine-agent/` in **Go** using `tailscale.com/tsnet`.

**Why Go:**
- tsnet, OpenBao client, and OIDC client ecosystems are Go-native.
- No Rust rewrites — Go for all new infra tooling.

**Why tsnet:**
- The agent joins the tailnet as its own node — no port-forwarding, no
  public exposure, no firewall rules.
- Identity is Tailscale WireGuard + OpenBao AppRole at the application layer.

### RPC surface (explicit methods — no `Exec`, no arbitrary file read)

| Method | Returns |
|--------|---------|
| `HealthGet` | uptime, degraded systemd units, disk %, load |
| `ServiceStatus(name)` | `systemctl --user status <name>` for hard-coded allowlist |
| `ServiceLogs(name, lines)` | journalctl tail for the same allowlist |
| `AgentVersion` | build info |

**Allowlisted units:** `openclaw-node`, `hermes-proxy`, `dotfiles-auto-update`

Nothing else. PTY sessions, reverse tunnels, file transfer, and
desired-state reconciliation are **permanently deferred** — use `hms` or
`ssh` instead.

### Auth

- Per-machine OpenBao AppRole. SecretID at `~/.config/machine-agent/secret_id`,
  chmod 600, rotated on re-enrollment.
- OpenBao policy `machine-agent`: auth only — no secret read access.
- Tailscale node identity is the network-layer proof; AppRole is the
  application-layer proof.

### Upgrade path

`go install` pinned to a flake input + systemd user unit restart driven by
`dotfiles-auto-update`. Managed via `home/modules/machine-agent.nix`.
Enabled per-machine via `dotfiles.machine.enableRemoteAgent = true` in
`machine-role.json`.

## Consequences

- `tools/machine-agent/` scaffold is the next concrete coding task.
- `home/modules/machine-agent.nix` already has the systemd unit definition —
  it is wired up once the binary exists.
- Bootstrap step `bootstrap/steps/20-bao-bootstrap.sh` must provision the
  AppRole SecretID at enroll time.
- `enableRemoteAgent` stays `false` by default until the agent ships.
