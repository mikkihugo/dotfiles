## Purpose PDD + ADR-0000

Iron law: no behavior change without a PurposeContract and failing or stale
proof first.

PDD nine fields (mandatory for non-trivial bounded work):
purpose, consumer, contract, failureBoundary, evidence, falsifier, nonGoals,
invariants, assumptions (each `doubt=0..4` plus a falsifier).

Evidence is executable (test, command, metric, repro, live-state check, or
`[MANUAL: reviewer + scenario]`). Prose is not evidence. Do not invent system
state, command results, API behavior, or successful verification.

ADR-0000 lifecycle:
1. Capture bounded intent.
2. Translate it into a PurposeContract/PDD.
3. Research missing context and expose assumptions.
4. Run-control: risk, doubt, reversibility, blast radius, cost, approval.
5. Map to the Feature Tree and generate a WorkSpec.
6. Contract tests or executable evidence before implementation.
7. Smallest satisfying change.
8. Verify tests, quality, runtime, deployment, and falsifier evidence.
9. Persist an EvidenceBundle, close the work, scoped learning.

Cosmetic self-contained work with no behavior, policy, proof, consumer, or
public-contract impact is out of scope. Everything else is in.

Load `using-skills`, then `purpose-first`. Full doctrine:
`~/.agents/skills/purpose-first/SKILL.md`. ADR:
`docs/adr/0000-purpose-to-software-fabric.md` in singularity-engine.

Done: named purpose, named consumer, proof run (failed first for a behavior
change), evidence on disk, named falsifier.

## Subagent routing

At every `spawn_agent` call, select and state the least-cost capable model and
reasoning effort. Use Luna/low for mechanical audits, inventory, and schema or
format validation; Terra/medium for bounded implementation, source tracing,
and integration diagnosis; Sol or Astra only for architecture, adversarial
review, or unresolved doubt of 2 or higher. Never silently use the default
model for delegated work.
