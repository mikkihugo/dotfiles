# TODO

## Architecture (revised 2026-04-20)

The custom Go secrets control plane and the Rust `secret-tui` /
`machine-agent` tools were retired after adversarial review flagged
credential-reuse and unbounded-exec flaws, and because every piece had a
better off-the-shelf replacement already deployed.

Current split:

| Concern               | Component                         | Network     |
|-----------------------|-----------------------------------|-------------|
| Human identity        | Authentik (lldap backend, passkey)         | public      |
| Service/machine auth  | OpenBao OIDC + AppRole                     | tailnet     |
| Runtime secrets       | OpenBao KV v2 at `kv/`                     | tailnet     |
| Declarative secrets   | SOPS + age (in this repo)                  | git         |
| Network layer         | Tailscale / headscale                      | overlay     |
| Desired state         | home-manager (this repo)                   | pull, `hms` |
| Admin actions         | OpenBao UI at `kv.infra.centralcloud.com/ui` | public/OIDC |

No custom control-plane service. No home-grown device-pairing protocol.
Humans authenticate to Authentik with a passkey; machines authenticate
to OpenBao with AppRole SecretIDs handed out during bootstrap.

## Secrets model

**Declarative, git-tracked** → `secrets/*.yaml`, SOPS-encrypted with age
keys recipients listed in `.sops.yaml`. Used for config that needs to be
reproducible across `hms` runs (SSH keys, long-lived API keys that predate
OpenBao). No runtime rotation.

**Dynamic, runtime** → OpenBao KV v2 via `BAO_ADDR`. Read with
`bao kv get kv/<path>`. Rotated without rebuilds. Used for service tokens,
LLM provider keys, OAuth client secrets, AppRole SecretIDs.

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

- **Fresh-machine bootstrap** (fetch age key + SSH keys
  from OpenBao with correct paths/permissions) — keep as a small shell
  script in `bootstrap/steps/`, no new binary.
- **age key rotation** (generate → bao put → re-encrypt every sops file
  → commit) — keep as a script, no new binary.

## Bootstrap

`install.sh` → `bootstrap/steps/*.sh` → home-manager.

Current gaps:
- First-run machine setup still handles sudo/role.
- First-run age-key fetch: currently SOPS-decrypts `personal-servers-ssh.yaml`
  in activation.nix. Migrate to `bao kv get kv/mhugo/age_private_key` once
  every host has an AppRole — until then SOPS is fine.

## OpenBao policies to define

- `mhugo` — full RW on `kv/mhugo/*`, `kv/personal/*` (user's own secrets)

## Immediate next steps

1. ~~Install `bao` CLI on all machines via home-manager~~ ✓
2. Confirm `bao login -method=oidc` flow on laptop + bunker
3. Write `bootstrap/steps/20-bao-bootstrap.sh` — reads AppRole SecretID
   (provisioned out-of-band at first enroll), logs into bao, fetches
   per-machine secrets to the right files

## Not doing (decisions logged)

- Custom WireGuard/Headscale control plane — use plain Tailscale
- Per-machine MCP servers — use central orchestration and existing host
  supervisors instead
- Central web UI for approvals — OpenBao's UI covers it
- Rust rewrite of anything — Go for new infra tooling where it fits the
  deployed ecosystem
- mTLS for machine → control-plane — Tailscale's WireGuard identity is
  good enough at this scale, and OIDC/AppRole handles app-layer auth
