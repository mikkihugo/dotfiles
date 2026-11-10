# Code Workspace

Purpose: local working tree root for live first-party repos and scratch
worktrees. Donor trees are not here.

Consumer: agents starting from `/home/mhugo/code` before choosing a concrete
repository.

## Layout

| Role | Path | Rule |
|---|---|---|
| Delivery | `singularity-engine`; `infra` → `/srv/infra` | land only in an owned task lane |
| First-party tool | `jcode`; `hightower` | edit and land; not a ship authority |
| Research corpus | `prior-art` | `singularity/prior-art`. Important. Do not archive, quarry, or treat as a stray clone |
| Satellite checkout | `centralcloud-postgres` | only local checkout of that forge repo |
| Quarry | `/home/mhugo/quarries/<name>` | read-only harvest; never under `code/` |
| Vendor reference | `/home/mhugo/vendors/` | third-party code; not a quarry; read-only reference — never edit or push from it |
| Upstream contribution | `code/<repo>-upstream` | editable checkout of a third-party repo with your fork as a second remote; PR work only, never a delivery source. (Vendors/ is read-only reference; quarries/ are harvest-only donors — neither is for contributing.) Example: `9router-upstream` → PRs against `decolua/9router`. |
| Detached copies | `/home/mhugo/resting/checkouts` | extra infra and jcode working copies. Not a lane pool |
| Retired ext4 git objects | `/home/mhugo/resting/ext4-git-stores` | old `code/store`. Live stores are btrfs under `/var/lib/git-stores` |
| Scratch | `worktrees/`, `.worktrees/`, `<repo>/.worktrees/` | lane lifecycle only; greenfield editor root is `<repo>/.worktrees/<lane>` where bound (infra: `/srv/infra/.worktrees/…`) |

Do not infer “product” from a `code/` sibling name. `ls ~/code` is live
first-party only.

## Ownership

- First-party repositories own their local rules in their nearest `AGENTS.md`.
  Read the target repo's scoped file before changing files there.
- **singularity-engine:** [AGENTS.md](singularity-engine/AGENTS.md) (workflow) and
  [STYLEGUIDE.md](singularity-engine/STYLEGUIDE.md) (purpose doctrine, RAG doc
  comments, polyglot standards).
  - **This checkout is a READ-ONLY nix mount** (`engine-checkout-readonly`):
    `touch` fails with "Read-only file system". No in-place edits, commits, or
    jj mutations here.
  - It **is** jj-backed (`.jj/` present, `repo vcs` facade). `git` commands fail
    because it is a non-colocated jj repo (no `.git`) — this is **not** "not a
    repo" and not "no VCS surface". Do not claim that.
  - Canonical forge: **Forgejo** `singularity/singularity-engine` (default
    `main`). GitHub is a mirror. `singularity-ng/singularity-engine` is stale.
  - To change files: spawn a **writable** jj workspace off the shared store
    (`repo vcs workspace-create <name> --objective '…'`; `workspace-spawn`
    is the same command). Engine also: `repo lane create`. Never a
    client-local worktree dir. Only if no writable workspace is reachable,
    fall back to the Forgejo contents API (create branch → PUT file → open
    PR) and say so explicitly.
- `/home/mhugo/quarries/` holds read-only donor checkouts. Harvest into Engine
  or infra; do not spawn a workspace, commit, or run Renovate/CI there.
- `/home/mhugo/vendors/` is third-party reference source, not product source
  and not a quarry. Use it to inspect external implementations and compare
  patterns.
- `/home/mhugo/code/worktrees/` and `/home/mhugo/code/.worktrees/` are isolated
  work areas. Do not clean them up unless the task explicitly targets worktree
  lifecycle.
- `/home/mhugo/code/infra` is a symlink to `/srv/infra`; treat `/srv/infra` as
  the source of truth and read its scoped instructions.
- `/home/mhugo/code/prior-art` is the research corpus. Keep it. Detached
  infra and jcode copies live under `/home/mhugo/resting/`, not beside it.

## Rules

- Do not infer repo ownership from path name alone. Check the nearest scoped
  instruction file and Git root first.
- Do not edit vendor source while doing architecture research. Record findings
  in the consuming first-party repo, a plan, or a local note instead.
- Do not mix reference clones into first-party indexes, scans, tests, or build
  inputs unless the task explicitly says to use them as a corpus.
- For cross-repo design work, cite local source paths from both the reference
  repo and the target first-party implementation.

## Verification

- Before edits: `find <target> -name AGENTS.md -print`.
- Before broad repo work: `git -C <target> rev-parse --show-toplevel`. Note
  jj-backed repos (e.g. singularity-engine) have no `.git`; check `.jj/` and use
  `repo vcs` there instead of assuming git failure means "not a repo".
- Before claiming a vendor comparison: list the vendor files read and the local
  first-party files they map to.

## Swarm Land-Before-New Rule

A swarm must integrate and land all completed work (commit → push → PR) before
picking new tasks. When a worker finishes a fix, the coordinator must commit,
push, and open a PR for that fix before dispatching new work. This prevents
fix pile-up in worktrees and ensures no completed work is lost when the swarm
moves on to unrelated tasks. If a swarm dies mid-work, the operator revives it
by healing + re-seeding the remaining plan — not by dispatching a fresh swarm
that duplicates in-flight lanes.
