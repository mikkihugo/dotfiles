# TODO

## Architecture (revised 2026-04-20)

The custom `vault.hugo.dk` Go control plane and the Rust `secret-tui` /
`machine-agent` tools were retired after Codex adversarial review flagged
credential-reuse and unbounded-exec flaws, and because every piece had a
better off-the-shelf replacement already deployed.

Current split:

| Concern               | Component                         | Network     |
|-----------------------|-----------------------------------|-------------|
| Human identity        | Authelia (lldap backend, passkey) | public      |
| Service/machine auth  | OpenBao OIDC + AppRole            | tailnet     |
| Runtime secrets       | OpenBao KV v2 at `kv/`            | tailnet     |
| Declarative secrets   | SOPS + age (in this repo)         | git         |
| Network layer         | Tailscale / headscale             | overlay     |
| Desired state         | home-manager (this repo)          | pull, `hms` |
| Admin actions         | OpenBao UI at `vault.hugo.dk`     | tailnet-UI  |
| Per-machine RPC       | machine-agent (Go+tsnet, planned) | tailnet     |

No custom control-plane service. No home-grown device-pairing protocol.
Humans authenticate to Authelia with a passkey; machines authenticate
to OpenBao with AppRole SecretIDs handed out during bootstrap; all of
it reaches `vault.hugo.dk` over Tailscale only.

## Secrets model

**Declarative, git-tracked** → `secrets/*.yaml`, SOPS-encrypted with age
keys recipients listed in `.sops.yaml`. Used for config that needs to be
reproducible across `hms` runs (SSH keys, long-lived API keys that predate
OpenBao). No runtime rotation.

**Dynamic, runtime** → OpenBao KV v2 at `vault.hugo.dk/v1/kv/`. Read with
`bao kv get kv/<path>`. Rotated without rebuilds. Used for service tokens,
LLM provider keys, OAuth client secrets, AppRole SecretIDs.

## Machine agent (Go + tsnet, pending)

Replaces the deleted `machine-agent-rust`. Same purpose — per-machine
management surface — but built around **narrow RPCs, not `exec`**.

Constraints:
- Embed Tailscale via `tailscale.com/tsnet` so the agent joins the tailnet
  as its own node; no port-forwarding, no public exposure.
- Per-machine OpenBao AppRole. SecretID stored at
  `~/.config/machine-agent/secret_id`, chmod 600, rotated on re-enrollment.
- RPC endpoints are explicit methods, not a command allowlist:
  - `HealthGet` — uptime, systemd degraded units, disk %, load
  - `ServiceStatus(name)` — `systemctl --user status <name>` output for a
    hard-coded allowlist of unit names (openclaw-node, hermes-proxy,
    dotfiles-auto-update)
  - `ServiceLogs(name, lines)` — journalctl tail for the same allowlist
  - `AgentVersion` — build info for health dashboards
  - No `Exec`. No arbitrary file read.
- Upgrade path: `go install` + systemd user unit restart driven by
  `dotfiles-auto-update`.

Deferred (add only when a concrete need shows up):
- PTY sessions
- Reverse tunnels
- File transfer
- Desired-state reconciliation (use `hms` instead)

## Secret-tui replacement

Decided: **don't build one**. The `openbao` CLI already covers the daily
secrets flow:

```bash
bao login -method=oidc          # passkey in browser, 8h token
bao kv get kv/cerebras           # read
bao kv put kv/cerebras api_key=… # write (if policy permits)
bao kv list kv/                  # browse
```

For the two things `bao` doesn't do for you:

- **Fresh-machine bootstrap** (fetch age key + SSH keys + `.env_tokens`
  from OpenBao with correct paths/permissions) — keep as a small shell
  script in `bootstrap/steps/`, no new binary.
- **age key rotation** (generate → bao put → re-encrypt every sops file
  → commit) — keep as a script, no new binary.

## Bootstrap

`install.sh` → `bootstrap/steps/*.sh` → home-manager.

Current gaps:
- `05-machine-setup.sh` still prompts for openclaw/sudo/role. Keep.
- Machine-agent prompts removed; re-add only once the Go agent lands.
- First-run age-key fetch: currently SOPS-decrypts `personal-servers-ssh.yaml`
  in activation.nix. Migrate to `bao kv get kv/mhugo/age_private_key` once
  every host has an AppRole — until then SOPS is fine.

## OpenBao policies to define

- `mhugo` — full RW on `kv/mhugo/*`, `kv/personal/*` (user's own secrets)
- `openclaw` — RO on `kv/{kimi,minimax,deepseek,openrouter,groq,openclaw}`
- `mail-ingest` — RO on `kv/{office365,mistral,lightrag}`
- `machine-agent` — no secrets; only auth method for proving identity to
  a future central dashboard (if one ever gets built)

## Immediate next steps

1. ~~Install `bao` CLI on all machines via home-manager~~ ✓
2. Confirm `bao login -method=oidc` flow on laptop + bunker
3. Mint AppRoles for openclaw + mail-ingest; wire SecretID into their
   systemd `EnvironmentFile` (not in-repo SOPS)
4. Start the Go machine-agent scaffold (`tools/machine-agent/`)
5. Write `bootstrap/steps/20-bao-bootstrap.sh` — reads AppRole SecretID
   (provisioned out-of-band at first enroll), logs into bao, fetches
   per-machine secrets to the right files

## Not doing (decisions logged)

- Custom WireGuard/Headscale control plane — use plain Tailscale
- Per-machine MCP servers — central MCP bridge can call into the agent
  over tsnet
- Central web UI for approvals — OpenBao's UI covers it
- Rust rewrite of anything — Go for all new infra tooling (tsnet, bao
  client, OIDC client ecosystems are Go-native)
- mTLS for machine → control-plane — Tailscale's WireGuard identity is
  good enough at this scale, and OIDC/AppRole handles app-layer auth
