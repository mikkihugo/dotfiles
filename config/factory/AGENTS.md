# Personal Droid mission preference

- When a task has a measurable optimization target (runtime, test speed, build size, quality metric, or similar), invoke the `autoresearch` skill and establish a baseline before changing code.
- In Missions, put the experiment command, metric direction, files in scope, constraints, and termination condition in the plan so workers can run non-interactively.
- Use autoresearch for repeated optimization experiments; use ordinary debugging for one-off diagnosis or correctness fixes without a measurable optimization target.
- Record each experiment result and retain only changes that improve the primary metric without violating the stated checks.

## Dispatch throttle (mandatory, 2026-10-28)

Before dispatching ANY subagent or background worker, take a slot from the
dispatch gate. Do not dispatch past the cap.

```bash
~/.local/bin/dispatch-gate acquire <label> [worker-session-id]
~/.local/bin/dispatch-gate release <N>        # always, including on failure
~/.local/bin/dispatch-gate status             # the ledger
~/.local/bin/dispatch-gate health             # which upstreams are LIVE
```

- The gate exits **2** when all slots are in use, or when every candidate
  upstream already has its maximum workers. That is the throttle working, not an
  error: wait for a slot, or release one, and dispatch then.
- **Pass the worker session id** when you acquire. The gate then tracks the
  worker by its own session file and reclaims the slot when that worker ends or
  goes silent, so a crashed worker cannot hold the gate for hours. Without it the
  slot falls back to a 6h age limit.
- Default cap is 20 concurrent worker slots (`DISPATCH_GATE_MAX` to change), and
  **at most 12 workers per upstream** (`DISPATCH_GATE_MAX_PER_UPSTREAM`). The
  per-upstream cap is the real throttle: a worker may run, but it must not create
  a thirteenth worker on one upstream. The 2026-10-28 incident was SEVEN workers on
  ONE upstream. A slot whose worker process is gone is reclaimed on the next gate
  call; any slot still held after 6h is reaped.
- Use the **complexity** the gate prints when you dispatch. Each slot maps to an
  upstream model through the host router (127.0.0.1:20128): light ->
  `custom:9Router-7` (Qwen3.6-35B-A3B combo, 3B active), medium ->
  `custom:9Router-6` (Qwen3.8-27B combo, dense), heavy ->
  `custom:9Router-5` (MiniMax M3.1 Flash combo, the worker model).
  `custom:9Router-4` (MiniMax M3) is reserved for orchestration and is not a
  worker slot. Workers that all resolve to the same model id share one
  upstream and trip its rate limit together.
- **Check upstream health before dispatching**: `~/.local/bin/dispatch-gate health`
  probes every configured model in parallel and prints LIVE/DEAD. Measured
  2026-11-10: **all eight upstreams are LIVE** (`custom:9Router-0..7`, HTTP 200).
  - Probe with the configured `model` id, NOT the `displayName`. The old
    `mmg/MiniMax-*` displayNames resolve to a broken `minimax-code-global`
    account and answer `503 [401] invalid access token`; the combo ids
    (`minimax-m3`, `minimax-m3.1-flash` — renamed from `mmg-m3`/`mmg-m31-flash`
    on 2026-11-07, the old names no longer exist) fall back to a working
    account and answer `200`. A probe that uses the displayName reports a LIVE
    upstream as dead — that mistake was made here on 2026-10-28 and briefly
    moved two healthy upstreams off the worker tiers (and on 2026-11-07 the
    stale `mmg/*` ids broke the claude-code sonnet/opus slots until the
    settings were repointed at the combos). Read the `model` field from
    `~/.factory/settings.json`; that is the id the router is given.
  - The gate refuses to hand out a slot on an upstream that fails its probe, so
    a genuinely dead upstream cannot take a worker.
  - Re-run `health` when a worker dies unexpectedly: a dead upstream and a bad
    prompt look identical in a handoff.
- Why this is mandatory: on 2026-10-28, seven workers were dispatched at once
  with the same effective model. Every one of them died with
  `model_rate_limited` after hours of work. All five lanes' surviving commits
  had to be rescued manually to `rescue/*` refs because their owning sessions
  were already gone. The work was recoverable only because jj keeps every
  commit in the shared store; nothing published it.
- A worker that dies does not release its slot. The gate reaps it after 6h, and
  `dispatch-gate status` shows the ledger.
