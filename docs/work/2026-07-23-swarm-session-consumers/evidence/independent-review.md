# Read-Only Review: swarm-session-consumers

- Repo/worktree: `/home/mhugo/.dotfiles-worktrees/swarm-session-consumers` (branch `codex/swarm-session-consumers`)
- Base: `8d91bd315f2ee34647f0e342e82aca7366c2b604`; Head: uncommitted working tree
- Scope: `config/codex/hooks/swarm-messages.mjs`, `scripts/test-swarm-messages.mjs`, `docs/work/2026-07-23-swarm-session-consumers/**`
- VCS reads via `repo vcs status|log|diff` only; no mutations performed.
- Kimi agents used: **3** (lead + 2 read-only review subagents). Ceilings respected (≤3 this swarm, ≤10/swarm, ≤30 global).

## 1. Strengths

- **Precedence and normalization match the contract exactly.** `consumerFor` (config/codex/hooks/swarm-messages.mjs:269-279) implements override > owner > payload digest > persisted fallback; explicit `REPO_MEMORY_SWARM_CONSUMER`/`SE_WORKSPACE_OWNER` values are returned verbatim (trimmed), only derived identities normalize to `<client>-<16hex>`. Every tier is pinned by tests (scripts/test-swarm-messages.mjs:222-246), including verbatim `kimi:<uuid>` forms (:399-409).
- **Careful blank handling.** Both env vars trimmed and treated as absent when empty (:270-273); payload ids go through `session == null ? "" : String(session).trim()` (:276) — `""`, `"   "`, `" \n\t "` all count as absent, verified by test (:415-433).
- **State-file keying is safe.** `safePart` (:20) maps everything outside `[A-Za-z0-9._-]` to `-`, so `kimi:<uuid>` explicit identities are safe in filenames and verbatim on the wire; no path traversal. The `.consumer` fallback file deliberately keys on `client`, not consumer (:229-231).
- **Fail-open preserved.** All fs failures in `persistedFallbackSession` (:233-258) degrade to an unpersisted per-invocation UUID; the EEXIST race is correctly closed with `flag:"wx"` + re-read (:244-251); `main().catch(() => process.exit(0))` (:413) remains the outer net. Nothing new throws on poll/ack/post paths.
- **Real-behavior tests.** Two real HTTP stub servers, real temp state dirs with cleanup, real on-disk state assertions, and a real child-process execution of the hook; only the network seam is stubbed. Independent re-run: **15/15 pass** (~455 ms), matching `evidence/green-result.txt` and `evidence/result.json`.
- **Server-semantics claim verified against Engine source.** New consumer starts at cursor 0 (mcp_tools.go:240,298-307; swarm_messages.go:145-147), poll returns addressed+broadcast history (swarm_messages.go:148), ack is per-(message,consumer) with cursor advance via `GREATEST` (swarm_messages.go:183-197), post idempotency is `(workspace, sender, idempotency_key)` (swarm_messages.go:116-127). The packet's replay assumption is confirmed line-for-line.
- **Genuinely shared adapter.** Despite living under `config/codex/`, the module is exec'd by claude, kimi-code, copilot, cursor, and codex hook configs — one implementation for all clients; the three session-id aliases cover that heterogeneity.
- **Digest hygiene.** All 8 recomputed sha256 digests (artifacts, snapshot, implementation bytes) MATCH the declared values; the evidence was produced against exactly the bytes under review.

## 2. Findings

### Critical (Must Fix)

**C1. The work packet fails the real validator — `validate_work` returns `ok:false, authorizes_execution:false`.**
Ran the actual validator (purpose-tool `validate-work` CLI compiled from the Engine source, `--require-evidence --no-report`, exit 1). Four gates fail:

1. `evidence:changed-file-manifest` — evidence.bundle.json:137 declares `"source": "bounded-implementer-report"`, and evidence/changed-files.json:2 repeats it. The validator requires exactly `"repository-vcs-facade"` in both the inline manifest and the artifact bytes (work-harness.ts:823-833, 842). **The changed-file manifest cannot pass the real validator as written.** Minimal fix: regenerate the manifest from `repo vcs status` output, set `source: "repository-vcs-facade"` in both places, recompute both digests.
2. `coverage:red-first:T1` and `coverage:red-first:T2` — the validator requires the red-proof artifact to be JSON parseable as `{result_id, status:"failed", observed_at}` matching the `red_proof` block (work-harness.ts:763-767). `evidence/red-proof.txt` is plain-text test output, so `redArtifactFailed=false` → both red-first gates fail despite the RED run being genuine. Minimal fix: emit the red run as a JSON result record (same shape as `evidence/result.json`, status `failed`, observed_at `2026-07-23T23:06:31Z`) and point `red_proof.output_uri` at it, or relax the worker's claim and drop `must_fail_first` — the former is correct.
3. `schema:evidence` — the `reviews[0]` entry (evidence.bundle.json:195-202) violates evidence-bundle/v3: missing required `subject_digest`, `verdict`, `artifact_id`, `observed_at`, `independent`; carries disallowed `kind`, `status`, `note`, `requested_at`. Minimal fix: reshape the pending coordinator-review entry to the schema fields.

Failure scenario: the Codex coordinator runs the claim_done gate (`validate_work(require_evidence=true)`), it fails closed, and the packet cannot be landed as-is — or worse, the gate is skipped and an invalid packet becomes the durable record.

### Important (Should Fix)

**I1. `??` chain drops valid session-id aliases when an earlier alias is present-but-blank.**
config/codex/hooks/swarm-messages.mjs:275-276: `payload.session_id ?? payload.sessionId ?? payload.conversation_id` short-circuits on nullish only. A payload like `{session_id: "", sessionId: "abc"}` resolves to `""` and falls into the persisted per-client+workspace fallback — the one identity that cannot distinguish concurrent sessions, silently recreating the shared-cursor/ack-theft bug this change exists to fix.
Minimal fix: iterate the three keys and take the first whose trimmed string form is non-empty:
```js
for (const key of ["session_id", "sessionId", "conversation_id"]) {
  const v = payload[key];
  const t = v == null ? "" : String(v).trim();
  if (t) return `${base}-${sessionDigest(t)}`;
}
```

**I2. No test proves legacy client-keyed state is neither read nor acked — evidence overclaims.**
work.spec.json:64 (R2 criterion 3), purpose.contract.json:52 (invariant), and evidence.bundle.json:99 (T2: "legacy client-keyed state is not created or read") assert the legacy file is unread/unacked, but the suite only proves legacy files are not *created* (scripts/test-swarm-messages.mjs:368-369). A regression re-introducing client-keyed `readState`/ack would go green while acking root-era deliveries.
Minimal fix: add a test that pre-seeds `codex--engine.json` with a pending entry, runs `runHook` with a session payload, and asserts the legacy file's bytes are unchanged and no ack carried a bare `codex` consumer.

**I3. Migration strands messages addressed to legacy identities — loss, not redelivery; packet implies otherwise.**
Server-side, poll filters `recipient=$3 OR recipient='all'` (swarm_messages.go:148) and ack enforces the same recipient boundary (swarm_messages.go:176). Messages addressed to `root`/bare clients are never delivered to `codex-<digest>` and can never be acked by it; the orphaned legacy state file's pending entries die with it. Broadcasts replay (acceptable duplication); addressed messages are stranded permanently once nobody polls as `root`. The `migration_caveat` (evidence.bundle.json:165-169) records only the replay side. Tolerable for a "coordination, not authority" bus, but should be stated plainly.
Minimal fix: amend the caveat to state addressed-to-legacy messages are stranded, not redelivered; optionally a one-time drain as the legacy identity before cutover.

### Minor (Nice to Have)

- **M1. Partial/empty `.consumer` file never self-heals** — swarm-messages.mjs:236-256. If `writeFileSync(flag:"wx")` creates the file but fails mid-write, every future invocation reads `""`, regenerates, hits EEXIST, and returns a fresh unpersisted UUID per hook fire — full broadcast-history replay at cursor 0 on every fire, forever, until manual removal. Fix: on empty EEXIST re-read, `unlinkSync` and retry the write once.
- **M2. Non-string object session ids collapse** — :276. `String({})` is `"[object Object]"`; any structured session id makes all such sessions share one digest. Low likelihood (real payloads use strings). Fix: `typeof session === "string"` guard, treat non-strings as absent.
- **M3. Birthday-bound comment ~5x optimistic** — :223-225. p ≈ n²/2⁶⁵ ≈ 2.7e-8 for n=10⁶, not ~5e-9. Negligible either way (per-client prefixing shrinks n further); doc nit on a load-bearing-looking number.
- **M4. `safePart` collisions between distinct explicit identities** — :20,196-198. `a:b` and `a-b` map to one state file, merging pending lists; mismatched-recipient acks then fail and stay pending forever. Pathological names only; worth a comment.
- **M5. `payload: null` now throws for library callers** — :291. `consumerFor` dereferences `payload.session_id` on all events; `main`'s catch keeps process-level fail-open, but `payload ?? {}` is trivial.
- **M6. Test-file `sessionDigest` re-implements the hook helper** — scripts/test-swarm-messages.mjs:19-20. Derived expectations pass if both copies drift together to a wrong algorithm. Fix: pin one known-answer vector (literal precomputed digest).
- **M7. SessionStart idempotency test is near-tautological** — :435-471. Passes the consumer explicitly via env, so identical keys follow from identical input. Format and cross-consumer distinctness are covered; derived-consumer stability is only indirectly covered by the continuity test (:299).
- **M8. "Concurrent sessions" test is fully sequential** — :342. It proves state isolation and no cross-ack, not an actual race; the `flag:"wx"` first-use race is untested. Name overstates slightly.
- **M9. red-proof.txt line numbers drifted** — evidence/red-proof.txt:31,47,64 cite 383/411/431; current lines are 387/415/435 (post-RED comment edits). Test names match; traceability intact; cosmetic.

## 3. Evidence-integrity verdict (work packet)

**Digests: truthful.** All 8 recomputed sha256 values match (4 evidence artifacts, snapshot, both implementation files against working-tree bytes). RED proof is genuine — the three failing tests still exist under identical names and fail for exactly the claimed reasons (prefix collision, missing digest format/blank handling, SessionStart key collision). GREEN is genuine — independently reproduced 15/15. Test-list in `result.json` matches the current suite exactly; changed-files.json content matches `repo vcs status` exactly (2 modified + 9 untracked packet files).

**Validator status: FAILING.** Despite truthful content, the packet does not pass the real `validate_work(require_evidence=true)` gate: exit 1, `ok:false`, `authorizes_execution:false`, 4 failed gates (changed-file-manifest source, red-first T1/T2 artifact shape, reviews schema). One partial overclaim: "legacy state not created **or read**" — only "not created" is tested (I2).

Verdict: **evidence content is honest but the packet is schema/gate-invalid and must be repaired before it can serve as the landing record.**

## 4. Ready-to-land verdict: **With fixes**

The implementation is correct, well-tested, and fail-open; the server-semantics assumption is verified. Land after: (a) repairing the packet so `validate_work(require_evidence=true)` passes (C1 — hard gate), (b) fixing the blank-alias `??` short-circuit (I1 — the one real behavioral hole), (c) adding the legacy-state unread/unacked test or narrowing the claim (I2), and (d) stating the addressed-message stranding plainly (I3). Minors can follow later.

## 5. Agent count

**3 Kimi agents** used: the lead (orchestration, VCS facade reads, validator run, report) + 2 read-only review subagents (implementation slice; tests/evidence slice). Within the 3-agent swarm limit and all standing ceilings.
