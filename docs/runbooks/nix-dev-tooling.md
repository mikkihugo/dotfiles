# Nix meta-tools (operator — host mirror)

**Doctrine SoT:** Purpose `using-skills` →
`references/nix-dev-tooling.md` (not a separate catalog skill).
Load via `skill_file_read({ name: "using-skills", path: "references/nix-dev-tooling.md" })`.
Refresh on `bundleHash` via `install_skills`.

Host home-manager may mirror binaries on PATH; PATH is not the instruction source.

| Job | Command |
| --- | ------- |
| Lint/format Nix | `lefthook run pre-commit` or Engine `repo check` |
| Readable build | `nom build` when on PATH |
| Switch + diff | `hms` (`command ls` + `nvd`) when HM aliases applied |

Agents: never raw `jj`/`git` — only `repo vcs`.
