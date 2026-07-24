# Work: 2026-07-23-codex-external-harness-orchestration

Disk-first Purpose-first work directory. JSON is authoritative; this README is a pointer.

| File | Role |
|------|------|
| `purpose.contract.json` | Why, consumer, contract, falsifier |
| `work.spec.json` | Scope, requirements, tests, verification |
| `evidence.bundle.json` | Proof after implementation |
| `evidence/` | Test and gate evidence |

## 2026-07-23 run-provenance update (worker: kimi-code, run kimi-2026-07-23-external-run-provenance-01)

- Added the Codex-only launcher `config/codex/bin/codex-external-run.mjs` (installed only at `~/.codex/bin/codex-external-run` via `home/modules/files.nix`): fail-closed per-run provenance records under `$XDG_STATE_HOME/codex/external-runs` (fallback `~/.local/state/codex/external-runs`), 0700/0600 modes, advisory-lock check-and-reserve, no prompt/argv/env/credential persistence.
- Replaced the obsolete "no permanent numeric ceiling" rule with Mikael's hard ceilings: at most 10 total Kimi agents per Kimi coordinator/swarm including the lead, at most 30 Kimi agents globally; resource/provider/independent-lane checks still select a lower live count.
- Tests: `scripts/test-codex-external-run.mjs` (14 launcher behavior contracts, fake child executables, temp XDG state) plus updated `scripts/test-codex-external-harness-skill.mjs`; both wired into `scripts/repo-check.sh`.

## Validation

Hosted `validate_work` MCP cannot read this worktree (`Target is outside allowed roots: /home/mhugo/.dotfiles-worktrees/codex-orchestrator-runbook`), so validation ran with the repo-local Purpose Tool CLI instead:

```bash
node /home/mhugo/code/singularity-engine/fabrics/tools/services/purpose-tool/dist/bin/validate-work.js \
  docs/work/2026-07-23-codex-external-harness-orchestration --repo-root . --require-evidence
# exit 0; ok: true; authorizes_execution: true (writes validation.report.json)
```

`repo check` exits 1 solely on the pre-existing, out-of-scope failure `shell aliases consume the managed Nix tooling` (`home/modules/shell.nix` `hms` alias), which failed identically in the baseline run before any edits (`evidence/repo-check-baseline.log`); all other 57 tests pass and the activation package builds (`evidence/nix-build.log`, exit 0).
