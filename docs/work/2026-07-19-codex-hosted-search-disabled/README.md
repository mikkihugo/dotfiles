# Work: 2026-07-19-codex-hosted-search-disabled

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation |
| `evidence/` | Test, request-capture, and gate evidence |

Validate:

```bash
node /home/mhugo/code/singularity-engine/tool/servers/purpose-tool/dist/bin/validate-work.js \
  docs/work/2026-07-19-codex-hosted-search-disabled --repo-root .
```
