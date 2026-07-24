# Work: 2026-07-23-opencode-plugin-reset

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation |
| `evidence/` | Test, request-capture, and gate evidence |

Phase 1 (this packet's current state): contract test `scripts/test-opencode-plugin-reset.mjs` captured RED in `evidence/red-proof.json`. The production fix (editing `config/opencode/opencode.json` and `profiles/default/links.json`, deleting the two overlay files) is a later phase.

Validate:

```bash
node /home/mhugo/code/singularity-engine/tool/servers/purpose-tool/dist/bin/validate-work.js \
  docs/work/2026-07-23-opencode-plugin-reset --repo-root .
```
