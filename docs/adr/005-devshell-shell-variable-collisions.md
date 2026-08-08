# ADR-005: The devShell environment occupies generic shell-variable names

**Status:** Accepted  
**Date:** 2026-08-08

## Context

`bin/repo`'s help text tells every agent and operator to run
`eval "$(direnv export bash)"` once per session. `.envrc` loads
`devShells.default` (`flake.nix`), a `mkShell` derivation whose environment is
exported with `__structuredAttrs`. That environment occupies roughly thirty
short, generic-word variable names in the calling shell.

Measured in a clean environment (`env -i`, this repo's worktree):

```
name=nix-shell-env
out=/home/mhugo/.dotfiles-worktrees/<wt>/outputs/out
system=x86_64-linux
```

`direnv`'s own export banner lists them: `name`, `out`, `outputs`, `system`,
`shell`, `shellHook`, `builder`, `phases`, `patches`, `stdenv`, `strictDeps`,
`doCheck`, `doInstallCheck`, `buildPhase`, `buildInputs`, `nativeBuildInputs`,
`propagatedBuildInputs`, `propagatedNativeBuildInputs`, `cmakeFlags`,
`configureFlags`, `mesonFlags`, `preferLocalBuild`, `dontAddDisableDepTrack`,
and the `depsBuildBuild*` / `depsBuildTarget*` / `depsHostHost*` /
`depsTargetTarget*` family. Re-verify with `direnv export bash` (note it emits a
*diff*, so a shell that already loaded direnv shows nothing — this is why the
collision is easy to miss).

**This already caused a bad commit on `main.`** Commit
`14fe1d0d1df1b48060babfcf3e588ed4a9e76f69` reads
`chore(nix-shell-env): commit in-flight worktree state before landing`. Its
scope should have been the worktree's name. A driver script iterated worktrees
with `name` as its loop variable and called `eval "$(direnv export bash)"`
inside that loop; the devShell's `name` won and every commit message it
generated was wrongly scoped.

Scope of what was established: the variables above are demonstrably occupied,
and the wrongly scoped commit is direct evidence of a real collision. The exact
condition under which `direnv export` *re-asserts* a value the caller has since
overwritten was not pinned down — a minimal loop that set `name` and re-ran the
export did not reproduce the overwrite. Treat the names as unsafe rather than
relying on a model of when the overwrite fires.

## Decision

1. Do not use any name from the list above as a local or loop variable in a
   shell script or inline driver shell that runs inside this repo's devShell.
2. Prefix instead: `wt_name`, `worktree_name`, `out_dir`, `target_system`.
3. Compute values that must survive a direnv load **before** the `eval`, or keep
   them in prefixed names. Paths derived before the eval are safe — that is why
   the wrongly scoped commit still went to the correct worktree: its `$log` and
   `$wt` were computed before the collision and only the label was wrong.
4. When a script both loads direnv and loops, prefer loading once outside the
   loop.

## Consequences

- A wrongly scoped commit is cosmetic; the same collision in a variable that selects
  a *path* or a *branch* is not. That is the risk this ADR exists to prevent.
- The list is environment-derived, not repo-authored: it can change when the
  devShell changes. It is documentation, not a gate. A lint that greps scripts
  for these names as assignment targets would make it enforceable, and is
  deliberately left as future work rather than asserted here.
- `bin/repo` is generated from `.purpose/commands.json` and stamped
  "Do not edit", so this cannot be documented there durably. Per ADR-001,
  `docs/adr/` is the mechanism agents are required to read at session start.
