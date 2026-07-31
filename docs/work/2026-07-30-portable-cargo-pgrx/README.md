# Work: 2026-07-30-portable-cargo-pgrx

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation (add when done) |
| `evidence/` | Contract, runtime, review, and quality evidence |

Validate:

```bash
nix run path:/home/mhugo/code/singularity-engine/fabrics/tools/services/purpose-tool#validate-work -- docs/work/2026-07-30-portable-cargo-pgrx --repo-root . --require-evidence
```
