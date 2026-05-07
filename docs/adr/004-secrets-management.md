# ADR-004: Secrets management — SOPS + OpenBao, never plaintext

**Status:** Accepted  
**Date:** 2026-04-21

## Decision

All secrets follow this hierarchy:

| Layer | Tool | Purpose |
|-------|------|---------|
| Source of truth | OpenBao (vault.hugo.dk) | KV v2, k8s auth, OIDC |
| Declarative secrets in repo | SOPS + age | `secrets/*.sops.yaml`, encrypted at rest |
| Runtime injection (k8s) | External Secrets Operator | SecretStore → ExternalSecret → Secret |
| Runtime injection (home) | sops-nix | Decrypts to `/run/secrets/` at hms activation |

**Rules:**

1. `.env` files and bare API keys are **never committed** to any repo.
2. Secrets in k8s come from ESO reading OpenBao — no `kubectl create secret`.
3. Secrets in home-manager come from `sops.secrets.*` — no plaintext in nix files.
4. The OpenBao root token and unseal keys live in SOPS-encrypted files only.
5. Cloudflare API token is scoped to `Zone.DNS:Edit` on `hugo.dk` only — not the global key.
6. Do not reintroduce private gist or plaintext env-file secret sync.

## Key paths in OpenBao (kv/)

| Path | Fields | Used by |
|------|--------|---------|
| `kv/hermes` | `api_server_key` | Hermes agent |
| `kv/openrouter` | `api_key` | Hermes, Toad |
| `kv/mistral` | `api_key` | Hermes |
| `kv/gemini` | `api_key` | Gemini CLI |
| `kv/amp` | `token` | Amp CLI |
| `kv/cloudflare` | `api_token` | Traefik DNS-01 |

## Consequences

- Adding a new secret = add to OpenBao first, then add ESO ExternalSecret or
  sops-nix secret reference, then commit.
- Never use `kubectl exec vault-0 -- bao kv put` without also updating the
  corresponding ESO or sops-nix declaration.
