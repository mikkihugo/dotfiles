---
name: sf-debug-scan
description: Use when the operator says diag, diag sf, run diag, do a diag, check sf, scan sf, sf scan, sf check, scan traces, scan logs, scan spans, scan journal, anything wrong, anything flapping, is sf ok, is sf healthy, debug sf, troubleshoot sf, sf debug, sf health, what's happening, status check, quick check, eye on sf, debug scan, or asks to investigate any SF runtime anomaly, error, stall, or flapping in .sf/, the sf-server pod, Laminar spans, or cluster logs before changing code.
---

# SF Debug Scan

One-shot, evidence-first scan of SF runtime state. Read-only by default.

**Purpose:** surface every concrete SF runtime signal in one pass so the
operator (and the agent) can act on evidence rather than guesses. This
includes both hard failures (errors, permission denials, crashes) and
soft outcome degradation: SF may be running and emitting no errors while
still producing wrong or sub-optimal results at the prompt/decision level
(ignored instructions, poor tool selection, model routing regressions,
repetitive supervisor empty-responses, triage grounding loss).

**Consumer:** any AI agent (Copilot CLI, Claude Code, Gemini) running on the
host with `.sf/` and kubectl access, called in response to a "diag" /
"check sf" / "scan traces" / "is sf ok" / "anything flapping" type request.

**Failure consequence:** agents answer "looks fine" while SF is either broken
or under-performing: hard errors hidden in another backend, permission
denials degrading retrieval, or the supervisor/children producing empty or
off-policy outcomes that the user experiences as "not following instructions".
In all cases operators restart pods or edit code without seeing the real
cause.

**Falsifier:** a run that returns "everything looks fine" while any of the
following are true in the system:

- `process-supervisor.json` has `state != "running"` for any required child,
- `process-supervisor.json` has `recentRestartCount > 0` or `restartCount > 3`
  for any required child,
- `/api/ready` or `/api/healthz` returns `ready: false` or a failing check,
- `kubectl get events -n sf-server` shows unreported Warning events in the
  last 15 minutes,
- `uok-diagnostics.json` `classification != "healthy"`,
- `uok-parity-report.json` `currentErrorEvents > 0` or
  `criticalMismatches > 0`,
- `sf-feedback-queue-failed.jsonl` has unreported entries,
- Laminar `status = 'error'` spans with `count >= 5` are unreported,
- an advisory-lock holder with `age > 60s` and `state = 'idle'` is unreported,
- a VectorChord grant gap exists while `code-index-freshness-error` events
  are in the journal,
- `sf_code_index_state` has `status='failed'` or `error IS NOT NULL`,
- `sf_code_index_state` has `status='stale'` with `indexed_at` older than 7d
  while `.sf/runtime/code-index-warmup.json` shows `status=warming` and
  `shardsDone` empty (index stall),
- the pod runs **both** `sf:headless:<repo>` and `sf:autonomous:<repo>` for
  the same project (writer-lock race),
- more than one `sf:autonomous:<same-repo>` or more than one `sf:rpc:<same-repo>`
  child is unreported,
- advisory locks use `sf-writer:public` for a multi-project pod (wrong lock
  namespace — should be `sf-writer:repo_<identity>`),
- a pod has `restartCount > 3`,
- an `auto-exit` with `reason="flow-audit:recent-errors"` is unreported,
- `supervisor-agent:*` traces show repeated `empty-response`, `runner-error`,
  `tick-degraded`, or `grounding degraded` decisions,
- recent journal triage entries show `review-gate-blocked`,
  `review-code-disagree`, or `challenger-override` clusters that correlate
  with user-facing "ignored instruction" reports.

If any of those are present but missing from the summary, the scan is broken —
fix the skill, don't soften the output.

## When to Use

Use when:

- Operator says any trigger phrase above (verbatim or close paraphrase).
- Operator asks "is sf healthy", "what's happening with sf", "is anything
  wrong", or any open-ended health check.
- After any non-trivial code change lands, before saying "ready".
- When asked to investigate any error, stall, anomaly, or flapping in
  `.sf/`, the sf-server pod, Laminar spans, or cluster logs.

Do NOT use when:

- Operator asks a direct question with a one-source answer (e.g., "what
  milestone is active" -> read `.sf/STATE.md` directly, not the full scan).
- Operator wants to change behavior, fix a bug, or implement a feature ->
  load `systematic-debugging` or `test-driven-development` instead.
- Operator asks about a non-SF system.
- Operator wants to dispatch a unit, kill a process, or open a write
  transaction -> this skill is read-only; ask before mutating anything.

## Procedure

Run Steps 0 -> 10 in order. Skip a step only if its precondition fails.
Quote ISO timestamps in the summary.

**MCP-first (observability server):**

- **Procedure text:** `skill_sf-debug-scan`, `skill://sf-debug-scan`, or prompt
  `sf-debug-scan` — load before writing diag instructions or runbook steps.
- **Live evidence:** `sf_debug_scan` (verdict, falsifierHits, template, markdown).

Before writing procedural instructions, checklists, or operator handoffs for this
scan: load this skill and derive steps from it. Do not reconstruct the runbook
from memory or paste trigger lists into AGENTS.md / prompts.

Confirm the `observability` MCP server is answering:

1. Call `observability_status`.
2. For a full pass in one round-trip, call **`sf_debug_scan`** — it runs Steps
   0/1/4a/5b/6 server-side plus Laminar/cluster-log probes and returns:
   - `verdict`: `healthy` | `degraded` | `broken`
   - `falsifierHits`: programmatic hits against the skill falsifier list
   - `template`: structured JSON matching the Output Template sections below
   - `markdown`: pasteable scan text (same shape as the template)
   - `raw`: underlying probe payloads for drill-down
   Prefer rendering `markdown` to the operator or diffing `template` over time.
3. Otherwise use atomic tools: `sf_health`, `sf_workers`,
   `sf_warmup_markers`, `trace_find_errors`, `cluster_logs_errors`, etc.
4. If `observability_status` reports `ok: false` or a tool call returns
   a fetch/connection error, retry the tool **once**. If it still fails,
   fall back to the kubectl commands documented for that step and surface
   the MCP degradation explicitly in the output (e.g. "MCP status: partial;
   Laminar via kubectl fallback").

This avoids silently missing data when the MCP server is partially
reachable (observability_status succeeds but a specific tool endpoint is
degraded) or when a transient fetch failure occurs mid-scan. `sf_health`
is still the first MCP call after the status probe because it returns
code-index state, advisory locks, blocked models, and SHA drift in one
round-trip, replacing the manual CNPG queries in Steps 3 and 9 when it
succeeds.

### Step 0 -- Tooling health (cheap, run first)

```bash
date -u +%FT%TZ
ls -la dist/loader.js .sf/runtime/process-supervisor.json 2>&1 | head
```

If `dist/loader.js` is older than `src/loader.ts`, `bin/sf-from-source` will
trigger `build:core` mid-scan and mask what you're observing. Either
`kubectl exec` into the pod, or warn the operator and stop.

### Step 1 -- SF runtime health (MCP `sf_health` + host files)

Call `sf_health` via the observability MCP. This returns:
- `codeIndexes[]` — per-repo: status, chunkCount, commitSha, headSha, shaDrift
- `advisoryLocks[]` — lock holder pid, state, clientAddr, ageSeconds
- `blockedModelsByRepo` — blocked providers per project

Then read the host-side runtime files (MCP doesn't have filesystem access):

```bash
cat .sf/runtime/process-supervisor.json            # web + headless-supervisor running?
cat .sf/runtime/uok-diagnostics.json              # verdict, classification, issues
cat .sf/runtime/uok-parity-report.json | jq '{criticalMismatches,currentErrorEvents,freshUnmatchedRuns,liveAutoLock,statuses}'
cat .sf/runtime/sf-metrics.prom                   # flush_success_total, flush_duration_ms, database_status
cat .sf/runtime/supervisor-intentional-pause-hold.json 2>/dev/null
cat .sf/runtime/triage-hold-cooldown.json 2>/dev/null
cat .sf/runtime/halt-state.json 2>/dev/null
cat .sf/runtime/last-triage-at
cat .sf/runtime/last-progress.json 2>/dev/null
```

If `sf_health` MCP is unavailable, read blocked models from host files:

```bash
cat .sf/runtime/blocked-models.json
```

### Step 2 -- Journal + supervisor traces (today, host tree)

```bash
DATE=$(date -u +%F)
wc -l .sf/journal/${DATE}.jsonl
jq -r '.eventType' .sf/journal/${DATE}.jsonl | sort | uniq -c | sort -rn
tail -n 5 .sf/journal/${DATE}.jsonl | jq -c '{ts,eventType,rule,reason:.data.reason,exitCode:.data.exitCode,signal:.data.signal,outcome:.data.outcome}'
find .sf/traces -type f -mmin -60 | sort | tail -20
ls -t .sf/traces/supervisor-agent:*.jsonl 2>/dev/null | head -3 | \
  xargs -I{} sh -c 'echo "--- {} ---"; tail -n 4 {}'
grep -E '"(auto-exit|triage-apply-failed|server-shutdown-signal|code-index-freshness-error|host-error)"' \
  .sf/journal/${DATE}.jsonl | tail -n 20
```

Pay attention to **outcome-quality signals**, not just errors:
- `workflow-command-complete` events where `data.outcome` is `fail` or `block`.
- `triage-apply-*` events clustered with `review-gate-blocked`,
  `review-code-disagree`, or `challenger-override` — these indicate the
  autonomous review loop is disagreeing with itself, which often surfaces
  to users as "SF didn't follow the instruction."
- `supervisor-agent:*` trace `type` values:
  - `supervisor-agent-tick-degraded`, `supervisor-agent-decision` with
    `feedbackKind=supervisor-agent:tick-degraded`
  - `deterministicFailure` or `runner-error`
  - `empty-response`
  - `autonomous-proposer-triggered` with no subsequent queued milestones

These are soft-failure modes: no crash, no ERROR span, but the expected
outcome (a dispatched unit, a merged triage, a resumed milestone) was not
produced.

Note: `code-index-freshness-error` events now include `data.error` with the
actual error message — check it instead of kubectl-exec for the cause.

### Step 2a -- `sf headless trajectory` (repo-native timeline)

```bash
timeout 30 ./bin/sf-from-source headless trajectory \
  --from "$(date -u -d '6 hours ago' +%FT%TZ)" \
  --to "$(date -u +%FT%TZ)" --skip-state
```

Joins journal + Laminar + state DB rows. Skip if Step 0 warned about
stale dist (rebuild would mask the scan).

### Step 3 -- Advisory lock + failed feedback queue

**Advisory locks come from `sf_health` (Step 1).** Only run the manual
kubectl query if the MCP was unavailable:

```bash
tail -n 3 .sf/runtime/sf-feedback-queue-failed.jsonl | jq -c '{queuedAt,id,subcommand,failure:.failure[0:200]}'
tail -n 3 .sf/runtime/sf-reconcile-queue-failed.jsonl 2>/dev/null
# Fallback only — sf_health MCP already returned this:
SF_PG_POD=$(scripts/sf-pg-pod.sh)
kubectl -n databases exec "$SF_PG_POD" -c postgres -- psql -tAX sf_production -c "
  SELECT l.pid, l.granted, a.client_addr, a.state, a.backend_start,
         now() - a.backend_start AS age
  FROM pg_locks l JOIN pg_stat_activity a USING (pid)
  WHERE l.locktype = 'advisory'
  ORDER BY l.granted DESC, age DESC;
" 2>&1 | head -15
```

SF refuses to displace a live backend; if the holder is stuck, the
operator terminates it.

### Step 4 -- Laminar error spans (last 1h)

**Preferred: use observability MCP `trace_find_errors` and `trace_summarize`.**
Fallback to kubectl if MCP is unreachable:

```bash
# Fallback only — prefer trace_find_errors MCP tool
kubectl -n monitoring exec laminar-clickhouse-0 -- clickhouse-client -q "
  SELECT name,
         simpleJSONExtractString(attributes, 'sf.worker') AS worker,
         count() AS cnt
  FROM spans
  WHERE status = 'error' AND start_time > now64(9) - INTERVAL 1 HOUR
  GROUP BY name, worker ORDER BY cnt DESC LIMIT 20;
"
kubectl -n monitoring exec laminar-clickhouse-0 -- clickhouse-client -q "
  SELECT name,
         simpleJSONExtractString(attributes, 'sf.worker') AS worker,
         arrayStringConcat(
           arrayMap(e -> simpleJSONExtractString(tupleElement(e, 3), 'exception.type'),
                    events), '; '
         ) AS exc_type,
         count() AS cnt
  FROM spans
  WHERE status = 'error'
    AND start_time > now64(9) - INTERVAL 1 HOUR
    AND (arrayExists(e -> simpleJSONExtractString(tupleElement(e, 3), 'exception.type') = '42501',
                     events)
         OR simpleJSONExtractString(attributes, 'db.system') = 'postgresql')
  GROUP BY name, worker, exc_type ORDER BY cnt DESC LIMIT 10;
"
```

### Step 4a -- Observability MCP (preferred over kubectl)

When the `observability` MCP server is reachable, use its bounded read-only
tools: `observability_status`, **`sf_debug_scan`**, `sf_health`,
`sf_workers`, `sf_warmup_markers`, `sf_process_supervisor`,
`sf_journal_recent`, `sf_trajectory`, `trace_list_services`, `trace_find`,
`trace_find_errors`, `trace_get <trace_id>`, `trace_summarize <trace_id>`,
`cluster_logs_search`, `cluster_logs_errors`, `cluster_logs_top`,
`span_db_errors`, `pod_recent_errors`.

**Backend degradation is not MCP disconnection.** `observability_status`
reporting `clusterLogsClickHouse: "fetch failed"` while Laminar / Loki are
reachable means the cluster-logs backend is degraded -- surface it
explicitly, do not mistake it for "no errors".

### Step 4b -- Cluster-logs (MCP `cluster_logs_errors` or kubectl fallback)

**Preferred: `cluster_logs_errors` MCP tool.** Fallback:

```bash
# Fallback only — prefer cluster_logs_errors MCP tool
kubectl -n monitoring exec cluster-logs-clickhouse-0 -- clickhouse-client -q "
  SELECT timestamp, namespace, pod, message
  FROM cluster_logs.logs
  WHERE timestamp > now() - INTERVAL 15 MINUTE
    AND message ILIKE '%error%'
  ORDER BY timestamp DESC LIMIT 20;
"
```

### Step 5 -- STATE.md

```bash
cat .sf/STATE.md
```

Note: `Active Milestone: None` + `Phase: pre-planning` is normal. Do not
silently dispatch units against parked milestones -- wait for explicit
`/unpark <id>`.

### Step 5b -- Server readiness probe (always run)

The HTTP readiness and health endpoints are cheap and authoritative. Run
them from inside the pod so they exercise the same network path as the
web client, not just the local host loopback.

```bash
POD=$(kubectl get pods -n sf-server -l app.kubernetes.io/name=sf-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n sf-server "$POD" -- curl -fsS http://localhost:4000/api/ready | head -c 500
kubectl exec -n sf-server "$POD" -- curl -fsS http://localhost:4000/api/healthz | head -c 500
```

Report `ready: false`, any failing `checks.*` field, or `db.backend`
without `db.urlConfigured`.

### Step 6 -- Pod-level evidence (always run)

**Preferred MCP:** `sf_workers` (process inventory + `duplicateWarnings`),
`sf_warmup_markers`, `sf_process_supervisor`. Fall back to kubectl when MCP
is degraded.

Pod-level evidence is no longer conditional: warning events, recent
restarts, and supervisor process state catch degradation before the
journal/Laminar paths surface it.

```bash
kubectl get pods -n sf-server -l app.kubernetes.io/name=sf-server -o wide
kubectl get events -n sf-server --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10
POD=$(kubectl get pods -n sf-server -l app.kubernetes.io/name=sf-server -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n sf-server "$POD" --tail=200 | \
  grep -E 'sf-server|code-index|tokenizer|VectorChord|planning-flow-gate|zero-progress|SIGTERM|Unhandled|permission denied|stream idle|write lost'
# Fallback only — prefer sf_workers MCP tool:
kubectl exec -n sf-server "$POD" -- ps aux | grep -E 'sf:|supervisor|tini' | sort -k11
```

**Worker inventory (multi-project pod):** expect exactly one
`sf:autonomous:<repo>` per project in `SF_WEB_AUTONOMOUS_PROJECTS`. Flag:

- `sf:headless:<repo>` alongside `sf:autonomous:<repo>` — competes for
  `sf-writer:repo_<id>` (web `/autonomous` workflow-command or compaction
  resume in RPC/headless; isolated child owns autonomous).
- duplicate `sf:autonomous:<repo>` or duplicate `sf:rpc:<repo>` — orphan
  children from restarts; only the bridge supervisor should respawn.
- `sf:triage:<repo>` is normal during repair; it must not hold sf-writer.

`sf_workers.duplicateWarnings` should list headless+autonomous races and
duplicate same-kind workers when MCP is current.

```bash
# Fallback only — prefer sf_warmup_markers MCP tool:
for P in singularity-forge continuity vectordrive; do
  echo "=== $P ==="
  jq -c '{status,shardsDone,pid,startedAt,error}' \
    /home/mhugo/code/$P/.sf/runtime/code-index-warmup.json 2>/dev/null || echo "(no marker)"
done

kubectl exec -n sf-server "$POD" -- sh -c '
  cd /home/mhugo/code/singularity-forge &&
  node /home/mhugo/code/singularity-forge/dist/loader.js headless --output-format json query' | head -40
```

### Step 7 -- Common production errors cheat sheet

When Steps 1-6 surface one of these signatures, the table tells you the
exact grant, migration, or operator action. Quote the span exception or
pod log line that matched.

| Signature | Cause | Fix |
|---|---|---|
| `exception.type='42501'` + `permission denied to examine "cron.database_name"` | sf_production role lacks `pg_read_server_settings` grant | `GRANT pg_read_server_settings TO sf_production_user;` |
| `exception.type='42501'` + `permission denied for table <name>` | sf_production role lacks table-level INSERT/DELETE grant | Grant missing permissions on the table |
| `exception.message` containing `does not exist` | Schema migration not applied | Run pending migration or add column via `sf-db-schema-pg.js`; compare to `PG_SCHEMA_VERSION` |
| `permission denied for table tokenizer` (in journal) | VectorChord grant gap: missing `tokenizer_catalog` / `bm25_catalog` grant | See Step 9 |
| Pod log: `Unhandled rejection` | Async promise not awaited -> `unhandledRejection` -> `process.exit(1)` | Find the un-awaited async call and add `await` |
| Pod log: `Cannot find module ... telemetry.js` | Stale Nix image referencing old import path | Rebuild + push new image |
| Self-feedback journal: `kind uses unknown domain` | New feedback kind not in `ALLOWED_KIND_DOMAINS` | Add kind to the array in `self-feedback.js` |
| Self-feedback queue: `requires a write-mode open` | RPC drain path opens read-only when it should open write-mode | Trace call site; open with `openWriteDatabase` |
| Self-feedback queue: `sf-writer:repo_... advisory lock held by pid N` | Live backend holds the repo writer lock | Operator terminates holder explicitly (SF refuses auto-recovery) |
| Pod `ps`: `sf:headless:<repo>` + `sf:autonomous:<repo>` both running | `/autonomous` or compaction-resume started autonomous in RPC/generic headless while bridge child owns writer | Stop using chat `/autonomous`; use `POST /api/autonomous/start`; kill stray `sf:headless` only after operator approval |
| Journal `code-index-freshness-error` with `advisory lock held` while caller already in write mode | `ensureWriteDatabaseOrSkip` re-opened DB (self-lock race) | Fixed in `db-owned-write.ts` — verify pod has rebuilt `dist/` |
| `code-index-warmup.json` `warming` + `shardsDone:[]` + stale `sf_code_index_state` | Inline warmup never progressed (writer held by wrong process, or detached spawn died with `stdio:ignore`) | Confirm `sf:autonomous:*` holds lock; indexing runs **in that process**, not `headless codebase indexer warmup` |
| `auto-exit` `feature-map-gate-failed` + lock errors in Laminar | `reconcileFeatureMap` skipped (no write authority) so gate sees stale reconciliation | Fix writer contention first; grants on `public.feature_*` are usually fine |

### Step 8 -- Observability topology

| Component | Cluster address | Port | Use |
|---|---|---|---|
| Observability MCP | `observability-mcp.centralcloud-mcp.svc.cluster.local` | 8097 | `sf_debug_scan`, `sf_health`, traces, cluster logs |
| SF Server | `sf-server.sf-server.svc.cluster.local` | 4000 | `/api/health/sf`, `/api/diag/*` (MCP proxies) |
| Laminar App Server | `laminar-app-server.monitoring.svc.cluster.local` | 8000 / 8002 (REST), 8001 (gRPC) | OTLP ingest + REST query |
| Laminar Query Engine | `laminar-query-engine.monitoring.svc.cluster.local` | 8903 | gRPC; not for direct curl |
| Laminar ClickHouse | `laminar-clickhouse.monitoring.svc.cluster.local` | 8123 | Spans / traces / signal events / Laminar logs |
| Cluster-logs ClickHouse | `cluster-logs-clickhouse.monitoring.svc.cluster.local` | 8123 | Vector-captured k8s stdout/stderr |
| Quickwit | `laminar-quickwit.monitoring.svc.cluster.local` | 7280 | Laminar log search backend |
| Loki | `loki.monitoring.svc.cluster.local` | 3100 | Legacy / secondary log query |
| Laminar Frontend | `laminar-frontend.monitoring.svc.cluster.local` | 5667 | Web UI (sign-in required) |

### Step 9 -- VectorChord / code index health

**Code index state comes from `sf_health` (Step 1).** The `codeIndexes[]`
array includes repo, status, chunkCount, commitSha, headSha, and shaDrift.

Only run the manual kubectl queries if `sf_health` was unavailable or
you need the extension/grant details:

```bash
SF_PG_POD=$(scripts/sf-pg-pod.sh)

# Extensions present?
kubectl -n databases exec "$SF_PG_POD" -c postgres -- psql -tAX sf_production -c "
  SELECT extname, extversion FROM pg_extension
  WHERE extname ~ 'vector|vchord|tokenizer' ORDER BY extname;"

# Grant check for the degraded case
kubectl -n databases exec "$SF_PG_POD" -c postgres -- psql -tAX sf_production -c "
  SELECT table_name, privilege_type FROM information_schema.role_table_grants
  WHERE grantee = 'sf_production_user'
    AND table_name IN ('tokenizer_catalog', 'bm25_catalog')
  ORDER BY table_name, privilege_type;"
```

Cross-check `code-index-freshness-error` events in the journal (now with
`data.error`) — when those are present and grants are missing, that's the
diagnosis.

**Index stall without PG error:** when `sf_code_index_state.status` is
`stale`/`indexing` but `indexed_at` is days old and the warmup marker shows
`warming` with empty `shardsDone`, the writer process is not completing
`indexFullRepo`. Check Step 6 worker inventory before blaming VectorChord.

**Do not use** `sf headless codebase indexer warmup` for prod full-repo
reindex — it hits the 300s headless RPC timeout. Server-side path:
`ensureCodeIndexFresh` in the `sf:autonomous` / `sf:rpc` write holder.

### Step 10 -- Decision rules

| Question | First source | Fallback |
|---|---|---|
| Postgres write failed with permission denied? | Laminar `status='error'` + `exception.type='42501'` | `information_schema.role_table_grants` |
| Postgres query failed with "column does not exist"? | Laminar span exception message | `sf_schema_migrations` vs `PG_SCHEMA_VERSION` |
| Pod crash? | Cluster-logs ClickHouse (pod LIKE 'sf-server%') | `kubectl logs <pod> --previous --tail=200` |
| Autonomous flow wedged? | Journal `auto-exit` + supervisor trace `watchdog-action` | `sf headless trajectory --unit <unit-id>` |
| Code index stale? | `sf_code_index_state` (Step 9) + warmup marker (Step 6) | `code-index-freshness-error` events |
| Writer lock race / duplicate workers? | `ps aux` in pod (Step 6) | Laminar `db.*` + journal lock messages |
| LLM worker error? | Laminar `span_type='LLM'` + `status='error'` | `sf_metrics_flush_duration_ms` in metrics |
| Open-ended "is anything wrong" with no symptom? | Steps 0 -> 6 in order | Add missing check to this skill |

## Output Template

Use this verbatim so scans can be diffed over time:

```
## SF Debug Scan -- <ISO timestamp>

### Health verdict
- process supervisor: <healthy|web down|supervisor down|fused>
- uok diagnostics:    <classification> -- <N> issues
- uok parity:         <ok|degraded> -- <N> current errors, <N> critical mismatches
- autonomous flow:    <running|paused (reason)|halted (reason)>
- metrics flush:      <N> successes, last <N>ms, db_status=<0|1>
- blocked model lanes: <N> providers (<list>)
- server readiness:   <ready|not ready>  ready checks: <pass|fail list>
- pod warning events: <N> in last 15m
- pod workers:        <sf:autonomous per repo; flag headless/duplicate rpc>

### Today's journal (<N> entries)
- top: <type>=<count> ...
- notable: auto-exit=<N>, triage-apply-failed=<N>, code-index-freshness-error=<N>, server-shutdown-signal=<N>

### Supervisor last watchdog pass
- <ISO>: action=<resume-stopped|observe|restart-child|...> reason="<reason>" feedbackKey=<key>

### Failed feedback queue (latest)
- <id>: <subcommand> -- <first 200 chars of failure>

### Postgres advisory lock
- holder pid=<N> backend_start=<ISO> client=<ip> age=<duration> state=<state>

### Laminar (last 1h)
- <name> on <worker>: <cnt>
- latest error span: <name> -- <exception.type>: <exception.message first 80 chars>

### VectorChord / code index (via sf_health MCP or kubectl)
- code indexes: <N> repos, <status counts>, shaDrift=<true/false per repo>
- warmup markers: <per-repo status/shardsDone/pid or N/A>
- extensions: vector=<ver>, vchord=<ver>, pg_tokenizer=<ver>, vchord_bm25=<ver> (kubectl only)
- tokenizer_catalog grant: <present|absent>  bm25_catalog grant: <present|absent> (kubectl only)

### STATE.md
- phase: <pre-planning|...>  active milestone: <id or None>  next action: <text>

### Decision rule applied
- question: <what the operator asked>
- first source: <Laminar|journal|cluster-logs|sf_code_index_state|...>
- result: <found here | escalated to <next>>

### Suggested next actions
1. <ranked concrete step>
2. <ranked concrete step>
3. <ranked concrete step>
```

## Rationalization Counters

You will be tempted to skip steps. Recognize and invert:

- "The journal looks normal, skip Laminar." -> No. Pod logs miss DB-level
  exceptions that span events record. Always cross-check Laminar.
- "The process supervisor says running, no need to check uok-diagnostics."
  -> No. uok is the SF kernel's own health check; supervisor only knows
  about its two child processes.
- "Advisory lock is held, but it's an old PID -- skip." -> No. A live
  backend holding the lock for >60s idle is the bug, not a stale read.
- "I'll just describe what I see instead of filling the template." -> No.
  The template exists so scans can be diffed. Skip a field only if you ran
  the probe and the result was empty.
- "Build is stale, I'll let bin/sf-from-source rebuild mid-scan." -> No. A
  mid-scan rebuild masks what you're observing. Use `kubectl exec` into
  the pod or warn + stop.

## Hard Rules

- **Skills author instructions.** Load this skill (or `skill://sf-debug-scan`)
  before writing diag procedures, summaries, or handoffs. Cite loaded steps;
  do not improvise from memory.
- **Read-only by default.** Never start a unit, kill a process, or open a
  write transaction. Ask before mutating anything.
- **Evidence-first.** Every claim cites a journal line, trace line, span
  attribute, or runtime field.
- **Quote timestamps.** When you say "the last supervisor pass did X",
  include the ISO timestamp from the trace so the operator can correlate.
- **Never claim "no errors" without checking Laminar.** Pod logs miss
  DB-level exceptions.
- **Never duplicate trigger lists inline** in AGENTS.md, CLAUDE.md, prompts,
  or MCP `instructions`. This skill's frontmatter `description` is the trigger
  source of truth. Operator sync: `~/.dotfiles/.../sf-debug-scan/SKILL.md`;
  MCP bundle: `scripts/skills/sf-debug-scan/SKILL.md`.

## Verification

Before claiming the scan done:

1. Walk the falsifier list (top of skill) -- every true condition appears
   in the output.
2. Output matches the template verbatim (with N/A for fields you didn't
   probe, never blank).
3. Every "Suggested next action" is concrete and ranked.
4. If a rebuild warning was triggered in Step 0, it appears in the
   summary header so the operator knows the scan was partially obscured.
