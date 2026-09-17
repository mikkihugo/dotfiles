# Codex coordination root-session recovery

Origin: Mikael's 2026-09-17 instruction to repair and land the Codex bus hook.

Observed baseline: this session's automatic Codex hook used
`principal=codex-01a0af9f, session=codex-01a0af9f` and repo-memory rejected it
as foreign-owned. A direct sweep with the same principal and
`session=codex-01a0af9f-root` succeeded and returned the signed inbox capability.

Scope: only the canonical Codex hook and its contract test. The pre-existing
foreign bare session is preserved and never claimed, deleted, or rewritten.
