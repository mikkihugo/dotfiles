# evalgate

`evalgate` serializes a critical section with a bounded, attributed file lock.

```text
evalgate [-lock PATH] [-wait 15m] [-hold 15m] [-shared] run -- CMD ARGS...
```

- Exclusive mode is the default. `-shared` permits concurrent readers and
  blocks behind an exclusive holder.
- `-wait` bounds lock acquisition. Timeout prints the holder PID, age, and
  command when available and exits `75` (`gate-timeout`).
- `-hold` bounds child lifetime. `systemd-run` enforces the limit when present;
  otherwise evalgate kills the child process group through Go's command context.
- A completed child returns its exit code. Invalid invocation or child start
  failure exits `64`.

This prevents the 2026-11-13 fleet lock incident, where a stuck holder kept
nix evaluation and garbage collection serialized for 1h51m. Kernel-owned flock
release also handles abrupt gate-process termination.

## Migration watch (operator 2026-11-13)

Follow the FOSDEM-2025 Go-in-Nix program and switch builders on its trigger:

- **Target:** `gobuild.nix` (katexochen/gobuild.nix — GOCACHEPROG next-gen Go
  builder: per-module derivations + incremental caching + patchable
  vulnerabilities). Stated status 2025-02: "highly experimental, not usable
  yet."
- **Trigger:** gobuild.nix lands in nixpkgs (or reaches a tagged stable
  release) — then replace gomod2nix here; the per-module shape carries over.
- **Interim scans:** `check-vuln.sh` (govulncheck, the
  govulncheck-nixpkgs pattern) runs with `check-deps-fresh.sh` + `go test`
  as this tool's proof chain.
- **Falsifier for the current choice:** gomod2nix goes unmaintained, or
  buildGoModule's pinning story retires the single-vendorHash pain — either
  re-evaluates the builder; the per-module architecture stays.

## Fleet Go-tooling rules (gobuild.nix lessons applied early, operator 2026-11-13)

**Vuln-patch runbook** (lesson: deps are visible, patchable derivations):
1. `check-vuln.sh` reports a reachable vulnerability in a pinned module.
2. If fixed upstream: bump `go.mod`, then `nix run github:nix-community/gomod2nix -- generate`, then `check-deps-fresh.sh` green.
3. If not fixed upstream: patch the dep derivation (per-dep fixed-outputs accept `patches`/`overrideAttrs`) and record the CVE + patch expiry in this README until the pin bump removes it.

**Dep-alignment discipline** (lesson: one shared dependency package set):
Identical module versions compile once fleet-wide (same fixed-output hash).
When a second Go tool joins this tree, keep shared dep versions aligned —
a renovate-style bump cadence beats per-tool drift, and the cache sharing
only fires on version equality.

**No-vendor policy** (lesson: setup-hook composability):
Never commit `vendor/` for Nix-built Go tools here; gomod2nix fetches per
module and composes. `vendor/` is gitignored and stays that way.

**GOCACHEPROG note** (lesson: cache as a first-class citizen):
The check scripts pin `GOCACHE` to `~/.cache/go-build` for iteration speed.
GOCACHEPROG-in-Nix (dnr/nix-gocacheprog) is deliberately NOT wired: it is an
impurity ("cache outside of nix" per the FOSDEM landscape slide) and our pins
are the truth. Revisit with gobuild.nix, which makes the cache content-
addressed inside the model.
