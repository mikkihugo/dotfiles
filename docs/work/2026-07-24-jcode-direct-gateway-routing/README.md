# Work: 2026-07-24-jcode-direct-gateway-routing

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Digest-bound completion proof |
| `evidence/` | Test, runtime, review, and falsifier records |

Validate:

```bash
purpose-validate-work docs/work/2026-07-24-jcode-direct-gateway-routing --repo-root . --require-evidence
```

The provider/server slice is deployed from the isolated dotfiles worktree but is
not committed, integrated, or published. The broader J-Code autonomy matrix is
outside this packet.
