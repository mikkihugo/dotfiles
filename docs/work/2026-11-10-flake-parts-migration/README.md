# 2026-11-10-flake-parts-migration

DRY flake restructure of `~/.dotfiles` (flake-utils → flake-parts, modular
per-system files, extracted central overlay, guard wrapper single-sourced from
the infra flake input), plus the fleet-wide jj 0.47.1 pin alignment it
absorbed.

- `purpose.contract.json` — canonical purpose contract (amended per the
  operator's long-term-fix directive: guard single-sourcing).
- `work.spec.json` — WorkSpec v4 with EARS requirements R1–R4.
- `current-spec.snapshot.json` — snapshot reference.
- `evidence/` — contract tests and proofs:
  - `equivalence-check.sh` — T1/T2 contract test (structural + store-path
    equivalence vs `baseline-outputs.json` and the same-tree reference).
  - `capture-baseline.sh` — output capture (also used for post-change capture).
  - `baseline-outputs.json` / `post-outputs.json` — pre-change and post-change
    consumer-output store paths.
  - `reference-mkhome.nix` — same-tree old-mechanism reconstruction for the
    tree-sensitive homeConfigurations.
  - `t1-red-pre-change.txt` / `t1-green-post-change.txt` — failing-first and
    passing runs.

Authoritative records are the JSON files; this README is a pointer only.
