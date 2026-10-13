# 2026-10-13: dotfiles → Rust `repo` operator enrollment

Work packet for migrating dotfiles from the local bash `bin/repo` to the
Rust-built `singularity-repository-operator` (consumed via the `singularity-engine`
flake input).

| File | Role |
|---|---|
| `purpose.contract.json` | Why: switch `bin/repo` to the operator ELF. Consumer: every agent shell on this devbox. Contract: `repo --version` reports the operator binary; `repo check nix` and `repo vcs test` pass with the operator as dispatcher. Falsifier: `repo check` fails OR `repo` reports a non-Rust file type. |
| `validation.report.json` | Most recent `purpose-validate-work` output. Currently `ok: false` because the work-spec/evidence bundle has not been authored; that authoring requires the engine-side enrollment change (R3 in the contract) before the work itself can be implemented. Re-run validator after enrollment is live. |
| (future) `work.spec.json`, `evidence.bundle.json`, `current-spec.snapshot.json` | Authored when the engine-side enrollment is in place. The contract intentionally scopes the build on the engine's admission decision, not the local migration. |

**Blocker** (R3 in the contract): `tools/repository-operator/src/operator_floor.rs:44`
declares `pub const ENROLLED_OPERATOR_TARGETS: &[&str] = &["singularity-engine"];`.
Adding `"dotfiles"` requires rebuilding the operator with that line extended.
This is an engine-side change (`/home/mhugo/code/singularity-engine`), not a
dotfiles change. Until the engine patch lands, the operator refuses every
command on the dotfiles checkout with `OPERATOR_ROUTE_NOT_ENROLLED`.

**Re-validate** after the engine-side enrollment change:

```bash
PURPOSE_TOOL_ALLOWED_ROOTS=/home/mhugo/.dotfiles \
  /nix/store/7vrgih17y1y0kgkz3inr5ip29xa5d9yf-purpose-tool-mcp-0.6.168/bin/purpose-validate-work \
  /home/mhugo/.dotfiles/docs/work/2026-10-13-repo-elf-enrollment \
  --repo-root /home/mhugo/.dotfiles
```

Once `ok: true`, complete the work spec and evidence per the engine's
purpose-tool workflow (work packets are emitted and validated, not hand-
authored). Run `purpose-repo-commands convert` and the validator again to
cycle until `authorizes_execution: true` after the engine admission lands.
