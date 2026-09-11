# Runbook: bind kimi-code sessions to the cluster observability stack
Date: 2026-09-11  
Author: agent (kimicode-9b9dfcbc-20260911)  
Scope: /srv/infra (operator-owned; agent cannot write this directly — this runbook is the operator patch)

## Why

Before this change, every kimi-code session was a black box to the cluster observability stack:

- No Loki logs (kimi-code's stdout went to `~/.kimi-code/logs/` and was never shipped).
- No OTel spans (kimi-code had no telemetry exporter configured).
- No way to join a Loki log line, an OTel trace, and a `repo vcs` lane together.

To answer "what is kimi-code session 9b9dfcbc-2b1d-4247-8504-f995bb483036 doing right now" required `ps` + `wire.jsonl` archeology.

After this change:

- Every kimi-code session inherits `OTEL_*` env (via `systemd --user` + sourced `init-otel.sh`).
- A `SessionStart` hook writes a JSON sidecar at `${XDG_RUNTIME_DIR}/kimi-otel/${session_id}.json` carrying `workspace`, `lane`, `principal`, `model`.
- Spans carry `kimi.session.id`, `kimi.workspace.path`, `kimi.lane`, `kimi.principal`, `kimi.model` resource attributes.
- Loki label promotion makes `session_id`, `workspace`, `lane`, `principal` queryable as labels.
- The new `observability_trace_session` MCP tool resolves a session_id / workspace / lane to live PIDs + Loki logs + OTel spans + tool-call summary.

This runbook covers the operator-side changes that the agent cannot apply itself.

## Operator patch 1 — Vector: ship kimi-code stdout to Loki with labels

File to edit: `/srv/infra/clusters/default/observability/vector-cluster-logs-helmrelease.yaml` (or wherever Vector's config is rendered; check with `kustomize build clusters/default/observability | grep -A 5 vector-cluster-logs`).

Append a new Vector source that scrapes kimi-code's per-host log directory and forwards it to Loki with label promotion:

```yaml
# Add to Vector sources:
sources:
  # ... existing sources ...
  kimi_code_sessions:
    type: file
    include:
      - /home/mhugo/.kimi-code/logs/*.log
      - /home/mhugo/.kimi-code/sessions/wd_mhugo_*/session_*/agents/*/wire.jsonl
    read_from: beginning
    multiline:
      start_pattern: '{'
      mode: halt_to_end
      condition_pattern: '}$'
    fingerprint:
      enabled: true
      fields:
        - session_id
        - agent_id

# Add to Vector transforms:
transforms:
  # ... existing transforms ...
  kimi_code_parse:
    type: json
    inputs:
      - kimi_code_sessions
    drop_invalid: true
    field: message
    target_field: parsed
  kimi_code_enrich:
    type: remap
    inputs:
      - kimi_code_parse
    source: |
      . = object!(.parsed)
      session_id = string!(.session_id) ?? "unknown"
      workspace = string!(.workspace) ?? "unknown"
      lane = string!(.lane) ?? ""
      principal = string!(.principal) ?? "unknown"
      agent_id = string!(.agent_id) ?? "main"

# Add to Vector sinks (extend the existing Loki sink, do not create a new one):
sinks:
  # ... existing loki sink, extend its inputs and labels ...
  loki:
    type: loki
    inputs:
      - ...existing inputs...
      - kimi_code_enrich
    labels:
      # ... existing labels ...
      kimi_session_id: '{{ .session_id }}'
      kimi_workspace:   '{{ .workspace }}'
      kimi_lane:        '{{ .lane }}'
      kimi_principal:   '{{ .principal }}'
      kimi_agent_id:    '{{ .agent_id }}'
    encoding:
      codec: json
```

Why this matters: without these labels in Loki, every observability lookup still has to grep full-text — defeating the point of the tie. The label keys must use a `kimi_*` prefix so they don't collide with existing Loki label names (`job`, `namespace`, `pod`, etc.).

Verification:
```bash
logcli labels kimi_session_id --since=1h
logcli query '{kimi_session_id="9b9dfcbc-2b1d-4247-8504-f995bb483036"} | json | __error__=""' --since=1h
```

If the first returns a list with the active session_id and the second returns spans without parse errors, the wire is live.

## Operator patch 2 — Loki relabel_rules ConfigMap (optional, for label cardinality)

Loki has a default label cardinality cap. The kimi.session.id is high-cardinality (one per session) and could blow past that cap if 50+ sessions are active simultaneously. If `logcli labels kimi_session_id` shows truncation, add this snippet to the Loki ConfigMap:

```yaml
# In clusters/default/observability/loki-helmrelease.yaml or wherever the
# loki ConfigMap is rendered:
limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  max_label_names_per_series: 50

# SchemaConfig: leave at v11 for now (v12 changes the wire format and
# requires a Vector bump — that's a separate ticket).
```

Verification: `logcli limits` should show `max_label_names_per_series: 50`.

## Operator patch 3 — observability-mcp: add `observability_trace_session` tool

File to edit: a new tool in the centralcloud-mcp-fleet's observability shim. The agent scope (engine repo `singularity/singularity-engine`) cannot write here directly; this is the spec the operator (or a follow-up PR to mcp-fleet) needs:

```go
// In fabrics/tools/services/mcp-fleet/observability.go (or equivalent):
{
  Name: "observability_trace_session",
  Description: "Resolve a kimi-code session to live process state + Loki logs + OTel spans + tool-call summary.",
  InputSchema: mcp.ToolInputSchema{
    Type: "object",
    Properties: map[string]mcp.ToolInputSchemaProperty{
      "identifier": {Type: "string", Description: "session_id | workspace_path | lane_name"},
      "lookback":   {Type: "string", Default: "1h"},
    },
    Required: []string{"identifier"},
  },
  Handler: func(args map[string]any) (mcp.ToolResult, error) {
    identifier := args["identifier"].(string)
    lookback := args["lookback"].(string)
    if lookback == "" { lookback = "1h" }

    // 1. Resolve identifier to session_id(s) via the sidecar files at
    //    /run/user/$UID/kimi-otel/*.json (or whatever XDG_RUNTIME_DIR resolves to).
    matches := resolveKimiSessionByIdentifier(identifier)

    // 2. For each session_id, query Loki with {kimi_session_id="$id"} | json
    //    and parse the structured log lines.
    // 3. Query OTel collector / Laminar for spans with resource attribute
    //    kimi.session.id=$id and aggregate tool-call counts.
    // 4. Use kubectl/ps to find live kimi-code processes whose /proc/$PID/cmdline
    //    references the session_id (rare — kimi-code doesn't always pass the
    //    session_id through to child processes) and report state.

    return mcp.ToolResult{
      Content: []mcp.Content{{
        Type: "text",
        Text: formatSessionTrace(matches),
      }},
    }, nil
  },
}
```

Why this matters: even with the labels in Loki, an operator still has to know which session_id to query. The sidecar file gives them a workspace → session_id index; the MCP tool wraps the lookup in one call. Together with the sidecar, the "what is this kimi-code doing" question goes from a 5-step archaeology dig to one MCP call.

Verification:
```bash
mcp_tool_call(server=observability, tool=observability_trace_session, arguments={
  "identifier": "/home/mhugo/code/worktrees/jj/singularity-engine/forgejo-mcp-desc-fix-2026-09-11",
  "lookback": "1h"
})
```

Expected: returns one or more session_ids, their live PIDs, recent log lines, recent OTel spans, and a tool-call summary.

## Operator patch 4 — Wire Vector's OTel collector sidecar to the cluster collector (already done)

No action needed. The in-cluster OTel collector at `otel-collector.monitoring.svc.cluster.local:4317` already accepts OTLP gRPC from any namespace. Vector's OTel sink can write there directly if the operator wants to ship metrics too — not required for this runbook.

## Verification plan (end-to-end)

After applying all four patches, a single MCP call from any coding agent must answer:

```bash
mcp_tool_call(server=observability, tool=observability_trace_session, arguments={
  "identifier": "lane:forgejo-mcp-desc-fix-2026-09-11"
})
```

And return:

1. List of session_ids currently working on that lane (via sidecar files).
2. Live process PIDs and CPU/RSS per session.
3. Most recent Loki log line per session (with the `kimi_*` labels attached).
4. Most recent OTel span per session (tool call or LLM request).
5. Tool-call summary (count, error rate, top tools).

If any of those five is empty, the corresponding patch is broken. Re-check:
- Empty session_ids → patch 1 (Vector) is not running, OR no kimi-code session has been launched since the dotfiles change.
- Empty PIDs → sidecar directory is unwritable OR `KIMI_SESSION_ID` is not exported.
- Empty logs → Vector label promotion is missing.
- Empty spans → OTLP endpoint unreachable from the kimi-code pod/host, OR the OTel SDK isn't initialized.
- Tool-call summary is zero → the OTel SDK isn't instrumenting tool calls (kimi-code may need a config flag; surface to kimi-code vendor).

## Falsifier for the whole tie

A kimi-code session that runs without `OTEL_RESOURCE_ATTRIBUTES` containing `kimi.session.id=<uuid>` AND without a sidecar file at `${XDG_RUNTIME_DIR}/kimi-otel/<uuid>.json` is not tied. The hook script `~/.kimi-code/hooks/otel-resource-attrs.sh` must run on every SessionStart event for the tie to be live.

If the hook is firing but the sidecar is missing, check:
- `XDG_RUNTIME_DIR` is set and writable.
- The kimi-code hook configuration (`~/.kimi-code/hooks.json`) registers the script under the `SessionStart` event.

If the hook is firing, the sidecar exists, but `OTEL_RESOURCE_ATTRIBUTES` does not include `kimi.session.id`, the dotfiles `init-otel.sh` is not being sourced BEFORE kimi-code launches. Source it from `~/.bashrc`, `~/.zshrc`, or wrap the kimi-code launcher in a script that sources it.

## Operator action checklist

1. [ ] Edit `/srv/infra/clusters/default/observability/vector-cluster-logs-helmrelease.yaml` (or current Vector config) — add the kimi_code_sessions source + parse + enrich transforms + extend the existing Loki sink with `kimi_*` labels.
2. [ ] (Optional) Edit the Loki ConfigMap to raise `max_label_names_per_series` to 50.
3. [ ] Open a PR to `centralcloud-mcp-fleet` adding the `observability_trace_session` tool. After merge + image rebuild, the gateway will advertise it.
4. [ ] Verify end-to-end: `mcp_tool_call(server=observability, tool=observability_trace_session, arguments={"identifier": "lane:forgejo-mcp-desc-fix-2026-09-11"})` returns a populated result.
5. [ ] Document in `/srv/infra/clusters/default/observability/AGENTS.md` that the kimi-code observability tie is live and the label keys are reserved (so a future Vector change doesn't drop them).

## Rollback

If this tie breaks the observability stack:

1. Revert Vector to its previous chart values (`helm rollback`).
2. Remove `OTEL_*` env from `systemd --user` via `home-manager switch --flake .#<host>` with the previous `activation.nix`.
3. Delete the sidecar files at `${XDG_RUNTIME_DIR}/kimi-otel/` (cleanup, not a runtime dependency).
4. Revert the engine `observability_trace_session` tool PR (if merged).

The tie is additive — kimi-code sessions will continue to function if observability is unreachable; the OTel SDK fails-closed (drops spans) and the hook script fails-closed (writes no sidecar on error).

## Last map review

2026-09-11 — initial runbook. Author: agent (kimicode-9b9dfcbc-20260911) in goal-mode session. Status: agent-side dotfiles + kimi-code config done; operator-side patches await operator action.
