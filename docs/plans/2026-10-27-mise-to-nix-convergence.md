# Plan: converge tool authority on nix/home-manager (mise → staged reduction)

Date: 2026-10-27
Author: agent (kimi), operator consulted on 2026-10-27 (leaned yes)
Status: **PROPOSED** — phases 1–2 are approved in direction, not yet shipped;
each phase that touches `home/` needs its own commit, `repo check`, and `hms`
verification. Nothing in this plan has been migrated yet.

## Purpose

One update authority per tool name, ending the recurring cost of dual
authority on this box: the 2026-10-27 gcloud vfox-plugin outage, the copilot
self-rewrite lockfile incident, the orphaned `sops` install whose shim falls
through to nix's 3.13.3, the `azure-cli` pipx→pypi backend drift, 15 hollow
mise install dirs and 15 silently shadowed command names. mise executes
third-party Lua plugin code in-process; every third-party plugin this box
runs is a repeat of that outage.

Consumer: this devbox; the flake is `/home/mhugo/.dotfiles`, deployed with
`hms` (flake host `cc-se-sto-devbox-01`).

Evidence base: two read-only sweep lanes on 2026-10-27 (tool inventory
classification; dotfiles HM feasibility). Key facts:

- mise is already 8-places entangled in the flake and **HM-owned today**
  (`home/home.nix:192-204` `programs.mise`, daily timer
  `home/modules/mise-auto-update.nix`, `sessionPath` at `home/home.nix:86`).
- The dominant existing wiring is "HM wrapper in `~/.local/bin` execs the
  mise shim" (`home/modules/ai-tools.nix` — kimi :770, node/npm/npx :795,
  qodercli :822, droid :983, goose :998, vtcode :79). Migrating a tool means
  landing the nix target **first**, then retargeting the wrapper's exec
  line, then removing the mise entry — in that order.
- No npm-package mechanism exists in the flake (zero `nodePackages` /
  `programs.npm` hits). The absorption path for npm CLIs is the already-
  pinned `llm-agents` flake input (`flake.nix:85`, 216 packages): **kimi-code
  2.3.3, copilot-cli 1.0.104, droid 0.250.0, claude-agent-acp 0.97.0,
  kilocode-cli 7.8.18, crush 0.98.2** all currently match the mise installs
  exactly at the pinned rev `fdd62d57` — version-neutral migrations.
- In nixpkgs today: `nodejs_26` 26.11.1 (exact match), `pnpm` 12.9.0
  (unstable overlay), `cntb` 1.7 (exact), `vultr-cli` 3.11.0 (exact,
  attr `vultr`), `wrangler`, `google-cloud-sdk`, `awscli` (PyPI line),
  `azure-cli`, `ollama` 0.40.0 (newer than the mise pin), `ovhcloud-cli`.
- Genuinely un-nixable today (phase 3 tier): `vtcode` (100+ releases/90d,
  no nix packaging), `claude-squad`, `nanobot-ai`, `go:…/gog`,
  `@hrrrsn/mcp-vnc` (abandoned upstream, 0 publishes since 2025-08-04),
  `java` 27 (nixpkgs tops out lower; consumer unverified — check before
  migrating anything to jdk25).

## Phases

- **P0 (done 2026-10-27)** — freeze the fragile class: no new vfox/Lua
  plugins, ever. `gcloud` is the only live one (pinned, runbook
  2026-10-27-mise-gcloud-vfox-plugin-pin.md); the embedded-copy lift
  condition is tracked daily. `oci` plugin clones are dead weight (tool was
  removed from config.toml at 08:51 2026-10-27).
- **P1 — version-neutral, land first** (one flake bump + one tool per
  commit, each verified by `mise env` absence + `command -v` in a fresh
  shell): the six exact llm-agents matches above, then `nodejs_26` +
  `pnpm` (unstable overlay; retarget the `~/.local/bin/{node,npm,npx}` HM
  wrappers), then the exact-matching nixpkgs CLIs (`cntb`, `vultr-cli`).
- **P2 — nix-available, small rework**: `ollama` (drop the stale pin, take
  nix 0.40.0), `wrangler` (nixpkgs 3.80.1, behind mise 4.153.0 by ~50
  releases — acceptable), `ovhcloud-cli`, `qodercli` (llm-agents 1.1.79;
  reconcile the third `~/.qoder` lineage first), `awscli`/`azure-cli`/`b2`
  (PyPI-line tooling; decide pin behavior), `google-cloud-sdk` from nixpkgs
  once the vfox pin's embedded-copy condition is met — the runbook lifts the
  pin, the tool can then stay mise until this phase.
- **P3 — keep mise as the slim fast-churn tier**: `vtcode` plus anything
  with no nix target and real churn. If a tool is abandoned upstream
  (`mcp-vnc`), remove it instead of migrating.
- **P4 — end state**: node/pnpm/java-class runtimes on nix; mise slimmed to
  the P3 tier or removed entirely (the operator decision point), with its
  auto-update timer then scoped to that tier only or retired.

## Invariant

One name, one authority, at every point in time. Before removing a mise
entry: the nix/npm target must already serve the name (fresh-shell
`command -v` proof, version compared). Before adding to nix: the mise entry
must be removed in the same commit. No parallel ownership between commits.

## Falsifiers

- A phase claim ("tool X migrated") is wrong if a fresh login shell still
  resolves the tool to a mise shim or install path.
- The P1 llm-agents assumption is wrong if a flake bump changes any of its
  pinned versions materially (re-verify before each P1 commit).
- The plan itself is wrong if a tool cannot be verified after its HM change
  lands in `hms` — that tool is not migrated; revert the flake bump.

## Explicitly not this plan

- No mass cutover commit. No removal of the daily `mise-auto-update`
  timer before P4. No touching the pinned `gcloud` plugin except through
  its own runbook's lift condition. No new vfox plugins (P0).