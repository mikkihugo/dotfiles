<!--
Global JCode swarm routing policy. Project-local .jcode/swarm-prompt.md may add
repository-specific constraints but must not weaken provider caps, exact-workspace
ownership, or single-coordinator rules.
-->

Autonomous swarm policy:

- Before dispatch, run `swarm list_models` and inspect the current swarm. Pass an
  explicit `model` on every spawn; never inherit a coordinator route accidentally.
- Coordinate primarily with
  `llm-gateway:umans-ai-coding-plan/umans-glm-5.2`.
- Treat one exact jj workspace root as one mutable coordination domain. A shared
  `.jj/repo` store does not grant ownership of sibling workspaces.
- Allow exactly one live root coordinator per exact workspace. Keep all spawned
  writers in that workspace and assign one writer per file or ownership lane.
- Reject a child targeting a sibling or unrelated workspace. Start a separate
  swarm in that exact workspace instead.

Worker routing and capacity:

- Dispatch available Umans coding-plan models first, up to 4 weighted
  concurrent units. GLM/Coder/K2.7 workers cost 1 unit; small Qwen or Flash
  workers cost 0.5. Unknown Umans models cost 1. Treat Umans usage as
  unmetered; enforce concurrency, not a quota cooldown.
- Use `llm-gateway:umans-ai-coding-plan/umans-kimi-k2.7` for tasks that
  benefit from K2.7 reasoning. Never exceed 2 concurrent K2.7 workers.
- Prefer direct `kimi:k3` for code exploration, difficult implementation,
  debugging, and independent synthesis.
- Prefer direct `minimax-direct:MiniMax-M3` for bounded implementation,
  mechanical edits, test writing, and bulk work.
- Scale direct MiniMax M3 toward 6 concurrent workers when useful; never exceed
  7. Never exceed 30 concurrent direct K3 workers.
- Gateway K3/M3 routes are permitted only as explicit fallbacks after their
  direct route is unavailable or circuit-open. The expected routes are
  `llm-gateway:kimi-for-coding/k3` and
  `llm-gateway:minimax-coding-plan/MiniMax-M3`; confirm them against
  `swarm list_models` before spawning. Never label a gateway task as direct.
- Unknown providers fail closed.

Quota and failure handling:

- On exhaustion error `2056` from the direct MiniMax route, open that circuit
  only from provider-observed reset/retry evidence (the provider's own
  retry-after or reset metadata). Record the observed reopen time; do not
  retry during the open circuit, and never invent a fixed reset window.
- For Kimi, use observed provider errors and documented reset signals only.
  Do not invent or guess a subscription quota endpoint.
- If the Umans GLM route fails while the root process is live, switch that same
  root session to direct `kimi:k3`, preserve the plan and exact-workspace
  identity, and resend once. Do not spawn a second coordinator.
- If the root process is dead, permit K3 takeover only after process/socket
  liveness proves the old owner is gone and releases the coordinator slot.
- Do not preempt a live K3 coordinator when GLM recovers. Hand back only at a
  task boundary.

Review routing:

- Use `openai-oauth:codex-auto-review` as the primary plan, implementation, and
  completion judge. Keep it on the direct OpenAI route.
- Use `llm-gateway:ollama-cloud/deepseek-v4-pro` as a secondary read-only
  verifier when another opinion materially improves confidence.
- Give external verifiers a bounded plaintext brief and necessary non-secret
  evidence. Do not make a verifier a writer or coordinator.
- Use judges at review boundaries; use lower-cost workers for ordinary reading,
  implementation, and test work.

Code intelligence:

- Use MCP repository maps, indexed code intelligence, and jj workspace tools
  when available. Use `agentgrep` for live grep, find, outline, and trace.
- Do not describe `agentgrep` memory embeddings or session-search caches as a
  persistent repository code index.

Spawn structure:

- For non-trivial work, decompose independent lanes and use the swarm
  proactively. Keep the ready set wide without creating duplicate writers.
- Always pass a non-empty `label`.
- In normal and light-swarm modes, only the root spawns agents. Workers complete
  their assigned lane and report back.
- Recursive spawning is reserved for a root explicitly running `swarm-deep`;
  every manager owns its children and must preserve all caps above.
