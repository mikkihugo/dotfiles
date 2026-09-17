# Codex device-auth safety

`codex login --device-auth` deletes `~/.codex/auth.json` before it issues a
new device code. This was observed on Codex CLI 0.154.0 (2026-09-11): a working
ChatGPT OAuth session became unauthenticated and no automatic backup existed.

Before any login probe, preserve the current credential file:

```bash
cp ~/.codex/auth.json ~/.codex/auth.json.pre-probe
# Run the intended login command.
# Restore after a successful probe if needed:
mv ~/.codex/auth.json.pre-probe ~/.codex/auth.json
```

If device auth has already removed the file, complete the browser flow at
`https://auth.openai.com/codex/device` within 15 minutes. The local CLI keeps
the PKCE challenge; the browser completion recreates `auth.json`.

Prefer non-destructive alternatives when possible:

- `codex login` (browser callback at `127.0.0.1:1455`)
- `codex login --with-api-key`
- `codex login --with-access-token`

The CentralCloud `llm-gateway` provider is unaffected because it uses
`LLM_MUX_API_KEY`. Incident evidence is retained in
`~/.agent-work/plans/codex-default-flip-20260911.md` and the
`singularity-engine` `repo_memory` bank (`kind:bug`).
