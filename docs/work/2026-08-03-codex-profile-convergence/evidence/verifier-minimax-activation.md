# Verifier MiniMax activation proof

Observed on 2026-08-03 after the gateway deployment and the isolated-worktree
Home Manager activation.

- The authenticated `goose-models` catalog listed `auto-minimax` with
  `ctx=1000000` and `caps=chat,tools,reasoning`.
- The same catalog listed `ollama-cloud/nemotron-3-ultra` with
  `caps=chat,tools`, without `reasoning`.
- `/home/mhugo/.local/bin/home-manager switch --flake
  /home/mhugo/.dotfiles-worktrees/codex-verifier-minimax-land-20260803#cc-se-sto-devbox-01`
  completed successfully.
- The resulting managed profile is a Home Manager store link and declares
  `model = "auto-minimax"`, `model_provider = "llm-gateway"`, and
  `web_search = "disabled"`; it does not persist a reasoning-effort override.
- The root config still declares `model = "gpt-5.6-sol"` and
  `model_provider = "openai"`.
- A fresh bounded process,
  `codex exec --ephemeral --skip-git-repo-check --profile external-verifier`,
  reported `model: auto-minimax`, `provider: llm-gateway`,
  `reasoning effort: low`, and returned `VERIFIER_OK`.

This replaces the prior verifier route because its inherited low Codex
Responses effort was rejected with `unsupported_model_capability` for
reasoning; no opaque Responses state was passed to the external process.
