# Work: 2026-08-09-swarm-hook-single-flight

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Digest-bound proof for implementation, review, and completion |
| `evidence/` | JUnit XML, gate JSON, traces |

Validate:

```bash
node /home/mhugo/code/singularity-engine/fabrics/tools/services/purpose-tool/dist/bin/validate-work.js \
  docs/work/2026-08-09-swarm-hook-single-flight --repo-root . --require-evidence
```

Scaffold sibling changes with MCP `scaffold_work` or copy this directory as a template.
