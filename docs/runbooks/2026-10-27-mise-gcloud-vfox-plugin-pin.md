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

Revised 2026-10-27 13:00 UTC after the fix landed upstream.

The plugin defect is fixed upstream: [jdx/vfox-gcloud#19](https://github.com/jdx/vfox-gcloud/issues/19)
was closed at 12:07 UTC 2026-10-27 by PR #20 (merge `8bc2e33aa741c0935f219e0d5791f0dc92569ed9`),
which moves `python.lua` to `lib/`. **That alone is not enough to lift this
pin.** mise also vendors an *embedded* copy of this plugin inside its own
binary (`crates/vfox/embedded-plugins/vfox-gcloud` upstream), and that
embedded copy is still broken — `lib/` contains only `components.lua` — at
mise `v2026.10.20`, `v2026.10.21`, and mise `main` at the time of revision
(jdx/mise#15034, the embedded-copy issue, closed 12:14 UTC 2026-10-27 saying
a re-sync is still needed). Because mise prefers the filesystem plugin dir
over the embedded copy, this pin's clone is what keeps gcloud working; if
the pin is removed before a mise release re-syncs the embedded copy,
unpinning falls back to the broken embedded copy and gcloud re-breaks.

Lift the pin only when BOTH hold:

1. The **latest mise release** has `crates/vfox/embedded-plugins/vfox-gcloud/lib/python.lua`
   (check: `curl -sL "https://api.github.com/repos/jdx/mise/contents/crates/vfox/embedded-plugins/vfox-gcloud/lib?ref=<TAG>" | grep python.lua`).
2. The locally installed mise is that release or newer (`mise version`).

Then refresh the pin clone first — its HEAD is **detached** at `f815af0`,
so a plain `git pull` fails; fetch and check out:

```sh
git -C ~/.local/share/mise/vfox-pins/vfox-gcloud fetch origin
git -C ~/.local/share/mise/vfox-pins/vfox-gcloud checkout -f origin/main
mise env 2>&1 | grep -c "module 'python' not found"   # expect 0
mise plugin uninstall gcloud                          # back to the registry plugin
mise reshim && mise env 2>&1 | grep -c "module 'python' not found"  # expect 0
gcloud version                                        # confirm registry plugin serves gcloud
```

If the final check warns, re-create the pin: re-checkout `f815af0` in the
pin clone is not needed (origin/main is fixed); instead re-restore the
symlink `~/.local/share/mise/plugins/gcloud -> ~/.local/share/mise/vfox-pins/vfox-gcloud`
and file upstream that the embedded copy regressed.

A daily tracker watches this condition. If the local checkout of this
runbook is missing while `origin/main` carries it, work off `origin/main` —
the canonical checkout may have lagged (see the dotfiles main reconciliation
note on the coordination mailbox).

Falsifier: `mise env` emits a `module 'python' not found` warning after
unpinning (the pin was lifted too early), or `mise which gcloud` stops
resolving while the pin is active (the link broke).

## Non-goals

- No change to `~/.config/mise/config.toml` (`gcloud = "latest"` stays).
- No change to the installed SDK at
  `~/.local/share/mise/installs/gcloud/590.0.1`.
- Do not "fix" this in Engine or infra — it is upstream plugin state on the
  host.