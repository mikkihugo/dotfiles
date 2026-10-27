# Runbook: mise `gcloud` — vfox-gcloud plugin pin

Date: 2026-10-27
Author: agent (kimi, session on cc-se-sto-devbox-01)
Scope: host tooling on this devbox (mise); not a home-manager file

## Why

Upstream commit [`a291554`](https://github.com/mise-plugins/vfox-gcloud/pull/18)
(PR #18, 2026-10-25) added `hooks/python.lua` and a top-level
`require("python")`. mise resolves shared Lua modules only from a plugin's
`lib/`, so every hook file fails at load time in mise's safe-mode Lua
(`module 'python' not found ... can't load C modules in safe mode`). Same
cause confirmed upstream on macOS: [jdx/vfox-gcloud#19](https://github.com/jdx/vfox-gcloud/issues/19)
(opened 2026-10-27).

Effect beyond the warnings: `env_keys.lua` never returns, so mise gets no
`PATH` / `CLOUDSDK_ROOT_DIR` from the plugin — `gcloud`, `gsutil`, `bq` were
not on PATH and no shims existed. Verified on this box 2026-10-27:
`command -v gcloud` rc=1 in an activated shell, 0 gcloud/gsutil/bq shims
before the fix.

## Current state (the fix)

The plugin is pinned to the last good revision and linked into mise:

- Clone: `~/.local/share/mise/vfox-pins/vfox-gcloud` at `f815af0b1e02e3ded63bfbc368916f3b9f3a3075`
  (`chore(deps): update hk in mise.lock (#17)`, 2026-10-21 — last commit
  before `a291554`).
- Link: `~/.local/share/mise/plugins/gcloud` → that clone.
- Verified after `mise reshim`: `gcloud version` →
  Google Cloud SDK 590.0.1 via shim; `mise env` exports
  `CLOUDSDK_ROOT_DIR`; 0 python warnings in `mise env`/`mise reshim`.

Linux never uses the plugin's Python logic (it is a macOS-only branch), so
the pin loses nothing on this host.

## Lift condition

When [jdx/vfox-gcloud#19](https://github.com/jdx/vfox-gcloud/issues/19) is
closed by a commit that moves `python.lua` to `lib/` (or stops requiring it
top-level), verify and unpin:

```sh
cd ~/.local/share/mise/vfox-pins/vfox-gcloud && git pull   # fetch the fix
mise reshim && mise env 2>&1 | grep -c "module 'python' not found"  # expect 0 (registry plugin again)
mise plugin uninstall gcloud   # remove the pin if the upstream plugin works
mise reshim && gcloud version  # confirm registry plugin serves gcloud
```

If the pulled pin still warns, re-clone: the fix commit is new and the pin
clone is at the branch `main` history — `git pull` is enough either way.

Falsifier: `mise env` emits a `module 'python' not found` warning after
unpinning (the pin was lifted too early), or `mise which gcloud` stops
resolving while the pin is active (the link broke).

## Non-goals

- No change to `~/.config/mise/config.toml` (`gcloud = "latest"` stays).
- No change to the installed SDK at
  `~/.local/share/mise/installs/gcloud/590.0.1`.
- Do not "fix" this in Engine or infra — it is upstream plugin state on the
  host.