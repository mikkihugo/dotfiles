# OTel / observability tie — boundary between `~/.dotfiles` and `/srv/infra`

This document records WHERE OTel / observability configuration lives in the
two authoritative trees, so the next agent does not re-duplicate operator
config in user config.

## TL;DR

| Concern                                  | Tree                                  | Path                                                                                |
| ---------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------- |
| OTLP collector deployment                | `/srv/infra`                          | `clusters/default/observability/otel-ingest.yaml`                                  |
| OTLP endpoint, service name, defaults    | `/srv/infra`                          | `hosts/_shared/otel-defaults.nix` (proposed; renders `/etc/otel/defaults.env`)     |
| Public OTLP ingest (`otel-ingest.centralcloud.net`) | `/srv/infra` (operator)        | `clusters/default/observability/AGENTS.md`; BasicAuth at `kv/otel-ingest`            |
| kimi-code SessionStart hook              | `~/.dotfiles` (per-user session attrs) | `config/kimi-code/hooks/otel-resource-attrs.sh`                                    |
| kimi-code shell env bridge               | `~/.dotfiles` (per-user)              | `config/kimi-code/init-otel.sh` → sources `/etc/otel/defaults.env`                  |
| JSON sidecar (`${XDG_RUNTIME_DIR}/kimi-otel/${session_id}.json`) | `~/.dotfiles` (per-user state) | written by the hook; operator observes via `observability-mcp.observability_trace_session` |
| `KIMI_HOOK_SESSION_START`                | `~/.dotfiles` (per-user path)         | `home.sessionVariables` in `home/modules/kimi-code-otel.nix`                       |

## Why the split

Per `/srv/infra/clusters/default/observability/AGENTS.md:22`:

> In-cluster apps write OTLP only to `otel-collector.monitoring.svc` (gRPC
> `:4317` or HTTP `:4318`); the collector fans out to Tempo and Laminar.
> External clients use `https://otel-ingest.centralcloud.net` with
> BasicAuth from OpenBao `kv/otel-ingest` (client material also at
> `kv/tenants/shared/otel-ingest-client`).

That contract belongs to the operator tier. A host agent's
`~/.dotfiles` should not re-declare `OTEL_EXPORTER_OTLP_ENDPOINT`, the
operator-set `OTEL_SERVICE_NAME` default, or any batch processor knob
(`OTEL_BSP_*`). If the collector migrates to a new Service name, the
operator config changes once; per-user dotfiles must not need to.

What the per-user side genuinely owns:

- **The SessionStart hook script**. It depends on `$HOME` (for
  `XDG_RUNTIME_DIR` and for the sidecar write path), it reads kimi-code's
  stdin JSON contract (mandatory per `agent-core-v2`'s `runHook.ts:132`),
  and it appends session-scoped keys onto the operator-rendered
  `OTEL_RESOURCE_ATTRIBUTES`. That work cannot move to `/srv/infra` —
  kimi-code is a per-user process; the hook has to land at
  `~/.kimi-code/hooks/` so every user account points at its own copy.
- **`KIMI_HOOK_SESSION_START`** so a shell-driven manual re-run of the hook
  finds it without re-deriving `~/.kimi-code/hooks/otel-resource-attrs.sh`.
- **The shell env bridge (`~/.config/kimi-code/init-otel.sh`)** —
  sources `/etc/otel/defaults.env` so a kimi-code process launched
  *outside* systemd (interactive shell, SSH session, pre-existing tmux
  server) still picks up the operator defaults.

## Anti-patterns to avoid

| Don't                                                                                | Why                                                                                                                   |
| ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Hardcode `OTEL_EXPORTER_OTLP_ENDPOINT` in `~/.dotfiles`                              | Duplicates operator config; breaks on collector migration.                                                              |
| Per-user `systemd.user.sessionVariables.OTEL_*` in `home-manager`                    | Same duplication, with the extra hazard that home-manager switch silently overrides operator-rendered defaults.        |
| Static `config/kimi-code/otel-resource-attrs.env` checked into `~/.dotfiles`         | Sits on the boundary — the hook DELETED this in 2026-09-11; defaults live with the operator now.                       |
| Two runbooks covering the same flow in both trees                                    | Per `/srv/infra/AGENTS.md:21`: "Operational runbooks are infra-owned and live only in `docs/runbooks/`."             |
| `~/.dotfiles/home/modules/forgejo-pr-autofix.nix` or `git-auto-backup.nix`           | Removed 2026-09-11 from `~/.dotfiles`. Operator-grade concerns; belong at `/srv/infra/clusters/...` or `hosts/_shared/`. |

## Migration trail

- **Before 2026-09-11** — `~/.dotfiles` had `systemd.user.sessionVariables`
  duplicating every `OTEL_*` default + a checked-in `otel-resource-attrs.env`
  file. Two orphan modules (`forgejo-pr-autofix.nix`, `git-auto-backup.nix`)
  sat in `home/modules/` but were never imported.
- **2026-09-11** — refactor to `~/.dotfiles` (PR #30 head `27eb29c4`).
  Introduced the per-user SessionStart hook + JSON sidecar, but kept the
  duplicate env defaults.
- **2026-09-11 (follow-up)** — this branch. Stripped the duplicate
  env defaults; rewrote `init-otel.sh` to source `/etc/otel/defaults.env`;
  deleted the two orphan modules; added this document.

## Consumer checklist

| Question                                                                           | Answer                                                                                                                                       |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Where does `OTEL_EXPORTER_OTLP_ENDPOINT` come from?                                 | `/srv/infra/hosts/_shared/otel-defaults.nix` → `/etc/otel/defaults.env` → `~/.config/kimi-code/init-otel.sh` (sourced).           |
| Where does `OTEL_RESOURCE_ATTRIBUTES` get its BASE static defaults?                | Same path — the operator file.                                                                                                               |
| Where do session-scoped keys (`kimi.session.id`, `kimi.workspace.path`, etc.) come from? | The `~/.kimi-code/hooks/otel-resource-attrs.sh` SessionStart hook; appended at runtime; idempotent strip+append on re-run.       |
| Where does the JSON sidecar go?                                                    | `${XDG_RUNTIME_DIR:-/run/user/$UID}/kimi-otel/${session_id}.json`. Per-user.                                                              |
| Where is the hook registered?                                                      | `~/.kimi-code/config.toml` via `config/agent-hooks/install-swarm-hooks.mjs` SessionStart entry.                                              |
| Who fixes a missing OTLP endpoint?                                                 | `/srv/infra` — the operator file path applies the host module.                                                                              |
| Who fixes a missing JSON sidecar?                                                  | `~/.dotfiles` — the hook fires at SessionStart. Check `kimi-code --no-session` or `~/.kimi-code/config.toml` SessionStart event list.   |

## Last map review

2026-09-11 — split established; both orphan modules deleted;
init-otel rewritten to source operator file; this doc added.
