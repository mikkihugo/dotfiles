# home/modules/kimi-code-otel.nix — observability PER-USER hook installer
#
# Operator-owned OTel defaults (`OTEL_EXPORTER_OTLP_ENDPOINT`,
# `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER`, base `OTEL_RESOURCE_ATTRIBUTES`,
# `OTEL_PROPAGATORS`, `OTEL_BSP_*`) live in `/srv/infra/clusters/default/
# observability/otel-ingest.yaml` plus the host-rendered `/etc/otel/
# defaults.env` (`hosts/_shared/otel-defaults.nix`, imported by every
# managed NixOS host). Per `/srv/infra/clusters/default/observability/
# AGENTS.md:24`: "In-cluster apps write OTLP only to
# `otel-collector.monitoring.svc`; the collector fans out to Tempo and
# Laminar." That contract belongs to the operator tier, not to a
# per-user home-manager module.
#
# What THIS module owns — the per-user half only:
#
#   1. The SessionStart hook (`config/kimi-code/hooks/otel-resource-attrs.sh`).
#      Reads kimi-code's stdin JSON contract (runHook.ts:132 →
#      matchHooks.ts:60-65), appends session-scoped keys onto the
#      operator-rendered `OTEL_RESOURCE_ATTRIBUTES` (strips any prior
#      `kimi.session.*`/`kimi.workspace.*`/etc. keys first so re-runs are
#      idempotent), and writes a JSON sidecar to
#      `${XDG_RUNTIME_DIR:-/run/user/$UID}/kimi-otel/${session_id}.json`
#      that an observability lookup tool can resolve without parsing
#      `wire.jsonl`.
#   2. The shell-sourced env bridge (`~/.config/kimi-code/init-otel.sh`).
#      Sources the operator-rendered `/etc/otel/defaults.env` so a kimi-code
#      launched outside systemd still inherits the defaults; surfaces a
#      one-shot warning when the file is missing so the gap is observable.
#   3. `KIMI_HOOK_SESSION_START` so a shell-driven re-run of the hook finds it.
#
# Falsifier: a kimi-code session with no JSON sidecar at the path above,
# or with `kimi.session.id` / `kimi.workspace.path` absent from
# `OTEL_RESOURCE_ATTRIBUTES`, means the hook didn't fire — either
# `install-swarm-hooks.mjs` skipped it or the operator defaults file is
# missing and the hook's preamble `cat $defaults_file` failed.
{config, ...}: {
  home.file = {
    ".config/kimi-code/init-otel.sh" = {
      source = ../../config/kimi-code/init-otel.sh;
      executable = false;
      force = true;
    };
    ".kimi-code/hooks/otel-resource-attrs.sh" = {
      source = ../../config/kimi-code/hooks/otel-resource-attrs.sh;
      executable = true;
      force = true;
    };
  };

  home.sessionVariables = {
    KIMI_HOOK_SESSION_START = "${config.home.homeDirectory}/.kimi-code/hooks/otel-resource-attrs.sh";
  };
}
