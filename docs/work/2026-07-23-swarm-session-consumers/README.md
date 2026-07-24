# Work: 2026-07-23-swarm-session-consumers

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation |
| `evidence/` | RED proofs, GREEN result, changed-files manifest, independent review |

Final contract (fix round 2026-07-23, task `2026-07-23-swarm-session-consumers-fix`):

- Derived identities are `<client>-<32 hex>`: SHA-256 of the whole non-blank
  session id truncated to 32 lowercase hex characters (128 bits,
  collision-resistant, not mathematically unique).
- The payload session id is the first non-blank trimmed value among
  `payload.session_id`, `payload.sessionId`, and `payload.conversation_id`; a
  blank or non-string earlier alias never masks a valid later one, and
  `payload: null` is safe.
- Explicit `REPO_MEMORY_SWARM_CONSUMER` / `SE_WORKSPACE_OWNER` identities have
  surrounding whitespace normalized (trimmed); the remaining internal value and
  punctuation are opaque.
- Deferred-ack state files are keyed by a readable sanitized prefix plus a
  128-bit digest of the full opaque consumer+workspace pair, so consumers with
  equal sanitized prefixes (e.g. `a:b` vs `a-b`) keep distinct files and
  independent ack state. A legacy client-keyed state file is left byte-for-byte
  unchanged and is not used for ack state.
- An empty persisted fallback file left by a crashed writer is removed and
  rewritten once instead of replaying fresh unpersisted identities.

Migration boundary (breaking, accepted): the Engine repo-memory server scopes
polling to the recipient — `internal/store/swarm_messages.go:148` filters
`recipient=$3 OR recipient='all'` and `:176` enforces the same boundary on ack.
Messages already addressed server-side to legacy recipients (`root` or bare
client names) are therefore **not delivered** to the new digest-suffixed
consumer; they are stranded, not redelivered, and broadcasts replay to each new
consumer once. No dual-consumer/dual-ack migration is added in this slice;
operators must repost any still-needed legacy-addressed message.

Independent review (`reviews` in `evidence.bundle.json`, artifact
`evidence/independent-review.md`) returned "With fixes" against the pre-fix
packet; this round addresses C1, I1–I3, and adjacent minors. Final review,
VCS, land, publication, and Home Manager activation remain with the Codex
coordinator; the fix lane performs no VCS mutations.

Validate:

```bash
purpose-validate-work docs/work/2026-07-23-swarm-session-consumers --require-evidence
```
