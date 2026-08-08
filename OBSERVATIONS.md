# Observations

## 2026-08-08 — repo-check nix gate whitelists activation-referenced scripts by exact name

- Observed: `scripts/repo-check.sh` decides whether to build the activation package from `nix_gate_path_re`, which lists non-nix inputs individually (`^scripts/codex-preferences$`). A new script referenced from a module via `${../../scripts/…}` changes the activation package but does not match the pattern, so `just check` skips the build gate for the very change that introduced it.
- Consumer impact: any future activation hook that calls a new script silently escapes the build gate until someone remembers to extend the regex; the failure mode is a green `just check` on a change that cannot evaluate.
- Evidence: adding `scripts/merge-authorized-keys` required extending `nix_gate_path_re` in the same commit; without it the diff matched only `^home/` for the module edit, and a scripts-only follow-up commit would have skipped the build entirely.
- Follow-up owner: dotfiles maintainer; consider gating on `^scripts/` wholesale, or deriving the input list from the modules rather than restating it.
- Scope decision: this change only appends the one new script to the existing pattern; it does not restructure the gate.

## 2026-08-08 — StrictModes makes home.file unusable for ~/.ssh/authorized_keys

- Observed: sshd on `cc-se-sto-devbox-01` runs `StrictModes yes` while `/nix/store` is `drwxrwxr-t root:nixbld` (group-writable). Managing `authorized_keys` through `home.file` would replace it with a store symlink whose resolved path sits under a group-writable directory.
- Consumer impact: an SSH lockout is the failure mode, and it is not observable from `just check` or a successful `hms` — only from the next login attempt.
- Evidence: `stat -c '%A %U:%G' /nix/store` → `drwxrwxr-t root:nixbld`; `grep StrictModes /etc/ssh/sshd_config` → `StrictModes yes`. Whether sshd's `safe_path()` walk follows the symlink target or the literal `%h/.ssh/authorized_keys` path was not determined — the merge-script approach makes the question moot rather than answering it.
- Follow-up owner: none required; recorded so a future "make authorized_keys declarative" change does not reach for `home.file`.
- Scope decision: this change writes a real 0600 file via an activation hook and does not attempt to prove or disprove the symlink behaviour.

## 2026-07-30 — Engine fabric shell hook depends on caller working directory

- Observed: `nix develop path:/home/mhugo/code/singularity-engine/fabrics/data --command …` fails from an unrelated working directory with `build-cache: cannot locate Engine cache activator`.
- Consumer impact: wrappers that delegate into the Engine fabric must enter `fabrics/data` before starting its development shell.
- Evidence: the pre-activation cargo-pgrx wrapper probe failed from the dotfiles worktree and passed after adding `cd "$flake_dir"`.
- Follow-up owner: `singularity-engine` build-cache shell-hook maintainers; make repository discovery derive from the flake/source path if callers are intended to invoke the shell externally.
- Scope decision: this change only adapts the dotfiles wrapper; it does not modify the read-only Engine checkout.
