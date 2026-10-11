# Work: 2026-10-11-dotfiles-flake-inputs-latest

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation (add when done) |
| `evidence/` | JUnit XML, gate JSON, traces |

Validate:

```bash
purpose-validate-work docs/work/2026-10-11-dotfiles-flake-inputs-latest
```

Scaffold sibling changes with MCP `scaffold_work` or copy this directory as a template.
