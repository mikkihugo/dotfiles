---
name: quality-contracts
description: Use when changing production behavior, tests, policy gates, validators, docs, or exceptions where correctness, hidden debt, magic constants, stale contracts, or silent failures could ship.
---

# Quality Contracts

Quality rules are contracts with consequences and falsifiers, not style
preferences. Invoke them only when they change proof or risk.

Purpose: prevent changes from hiding defects behind prose, exemptions, or weak
tests.
Consumer: agents implementing, reviewing, validating, or documenting behavior.
Failure consequence: gates pass while behavior remains unproved; future agents
trust stale docs or exemptions; failures disappear from evidence.
Falsifier: the change is cosmetic and cannot affect behavior, proof,
observability, policy scope, or a public contract.

## Rules

When any rule applies, state:

`failure consequence: <what breaks>. falsifier: <what would prove this rule wrong>.`

Core contracts:

- No behavior change without failing proof first.
- No completion without a real consumer.
- No judgment call without confidence and falsifier.
- No unexplained magic constants for time, size, retry, limits, or cost; use a
  named constant with units.
- No stale docs or comments on public contracts; docs must match behavior.
- No silent catch, suppression, ignore, or fallback without a written reason and
  an evidence path for diagnosis.
- No policy/lint/test exclusion without owner/path, removal condition, failure
  consequence, and falsifier.
- No hidden compliance debt: do not regenerate exemptions, broaden allow-lists,
  weaken checks, or move code outside scanner scope to make gates pass.

## Proof Shape

- Behavior contract tests prove the intended outcome.
- Degradation tests prove failure modes are bounded.
- Implementation guards are allowed only when labeled as guards, not product
  proof.
- Decision logic belongs in a small pure kernel or equivalent isolated rule set
  with contract tests before orchestration wiring.

## When Blocked

If a rule applies but the consumer, consequence, or falsifier is unclear, stop
with:

`BLOCKED: purpose unclear - <missing field>.`
