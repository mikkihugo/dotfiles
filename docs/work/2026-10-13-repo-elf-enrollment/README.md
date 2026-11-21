# 2026-10-13: dotfiles → Rust `repo` operator enrollment

Work packet for migrating dotfiles from the local bash `bin/repo` to the
Rust-built `singularity-repository-operator` (consumed via the `singularity-engine`
flake input).

| File | Role |
|---|---|
| `purpose.contract.json` | Why: switch `bin/repo` to the operator ELF. Consumer: every agent shell on this devbox. Contract: `repo --version` reports the operator binary; `repo check nix` and `repo vcs test` pass with the operator as dispatcher. Falsifier: `repo check` fails OR `repo` reports a non-Rust file type. |
| `validation.report.json` | Most recent validation output. |
| (future) `work.spec.json`, `evidence.bundle.json`, `current-spec.snapshot.json` | Authored when the engine admission lands and the dotfiles-side change executes. |

## Status 2026-11-20 (in flight)

The blocker (R3) is being executed today, in order:

1. **Engine lane `dotfiles-enroll`** (singularity-engine): add `"dotfiles"` to
   `ENROLLED_OPERATOR_TARGETS` (`tools/repository-operator/src/operator_floor.rs:55`;
   currently `["singularity-engine", "infra", "jcode"]`, no test pins the list) and
   expose the operator ELF via `hydraJobs` in Engine's flake so Hydra
   (`infra/apps/hydra-oci`, today a bounded fixture) can build and cache the one
   derivation fleet-wide.
2. **Dotfiles lane `lane-create-verb`** (this repo, staged): delete the generated
   `bin/repo` facade + `.purpose/commands.json` + `.purpose/repo-agent-catalog.json`;
   add the `singularity-engine` flake input projecting `packages.engine-repo`
   (jcode pattern); author `.purpose/repository-operator-target.v1.json`
   (canonical primary `/home/mhugo/.dotfiles`, lane root
   `/home/mhugo/.dotfiles-worktrees`, branch prefix `worktree/`,
   `publication_mode: integration-only`).
3. After (1) lands: re-lock the dotfiles flake pin to the enrolling engine rev,
   then publish lane (2) and verify `repo --version` reports the ELF.

## Decisions and findings

- **Command contract digest** (`command_contract_digest` in the target manifest)
  is the sha256 of the ELF-embedded v2 command grammar — a compatibility
  assertion, never target-supplied policy. Seeded from the live manifest that
  jcode runs today; the operator's own `verify_target_command_contract` refuses
  on mismatch, so a wrong seed fails loudly at first dispatch, not silently.
- **GitHub mirror gap**: the Rust target manifest has no dual-remote
  publication field; dotfiles' Forgejo+GitHub push is reduced to
  integration-only (Forgejo) at enrollment. Follow-up: a mirror-sync mechanism
  for the GitHub dotfiles mirror must be rebuilt outside the operator.
- **One ELF**: consumers import `singularity-engine.packages.repo` (burned-in
  jj/git/ssh/nix paths, consumer-neutral). Per-repo projections only rename the
  binary (`engine-repo` in dotfiles/jcode) so it cannot shadow an in-repo
  launcher. The host `~/.local/bin/repo` shim (home-manager,
  `home/modules/repository-operator.nix`) resolves per-caller: launcher, else
  `#engine-repo`, else refuse.

## Re-validate

After the engine admission lands and the dotfiles lane publishes, re-run the
validator against this packet and author the work spec + evidence bundle.
