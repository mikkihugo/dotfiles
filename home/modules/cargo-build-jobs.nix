# home/modules/cargo-build-jobs.nix — bound how many rustc ONE cargo may spawn.
# Devbox-only: this is tuned to a measured host, see WHY -2 below.
#
# WHY
# This box runs many AI coding agents concurrently. Cargo defaults `-j` to
# nproc, so every agent's build claims every core regardless of how many other
# builds are already running. 47 concurrent cargo/rustc was measured on
# 2026-09-07 — roughly 3x oversubscription of the CPU. On the 32-core host of
# 2026-11-07 the same oversubscription reached a load average above 1300.
#
# WHAT ACTUALLY GOES WRONG (measured 2026-09-07, not assumed)
# The visible failure is builds dying with "terminated by signal 15". That is
# NOT an out-of-memory kill, and reading it as one leads to the opposite fix:
#   - memory.events at /sys/fs/cgroup/user.slice, user-1000.slice and the
#     session scope holding agent cargo all read `oom 0, oom_kill 0`.
#     oom_kill counts GLOBAL kernel OOM kills of tasks in the cgroup, so those
#     zeros are real evidence. (`high`/`max` being 0 proves nothing here — they
#     can only fire when a limit is set, and none is.)
#   - journalctl -k across all 5 boots: zero OOM hits. systemd-oomd is running
#     but inert (empty oomd.conf, every slice at ManagedOOM*=auto) and logged
#     zero kill actions in 14 days. earlyoom is not installed at all.
#   - The kernel OOM killer and systemd-oomd both send SIGKILL, never SIGTERM.
#     `systemctl show <session>.scope -p KillSignal` returns KillSignal=15,
#     FinalKillSignal=9 — every systemd-mediated stop here sends SIGTERM first
#     BY DESIGN. Signal 15 fingerprints the timeout/deadline family.
# Memory pressure is real (user.slice peaked at 52.8 GiB of 62.7) but it never
# killed anything: there is 31.4G of zram swap, so the box swaps rather than
# kills, and zram compression burns the same cores rustc wants. Pressure shows
# up as SLOWNESS, and slowness is what trips wall-clock deadlines.
#
# So the lever is CPU oversubscription, not memory. Capping jobs means each
# build gets more of the machine and finishes sooner, which makes deadline
# kills less likely. Note this is the OPPOSITE of a systemd MemoryHigh
# throttle, which was the obvious-looking fix and would have made builds
# slower and therefore killed more often.
#
# WHY AN ENV VAR AND NOT ~/.cargo/config.toml
# `[build] jobs` in CARGO_HOME would be the natural home for this, but
# scripts/test-sccache-profile-scope.sh asserts every host evaluates
# `home.file.".cargo/config.toml"` to null: sccache is infra-owned
# (/srv/infra hosts/_shared/nix-cache.nix) and home-manager must not own that
# file, because owning it is how sccache settings would creep back in. That
# contract is deliberate, so this uses CARGO_BUILD_JOBS, the documented env
# equivalent of build.jobs, and leaves the file unclaimed.
#
# WHY A STATIC CAP AND NOT A SHARED JOBSERVER
# A host-wide GNU-make jobserver is the only mechanism that adapts across
# concurrent, uncooperative cargo invocations, and it does work here — cargo
# inherits a pool from MAKEFLAGS with no make parent, and an explicit `-j16`
# does not escape it (both verified 2026-09-07). It is deliberately NOT used
# yet, because a persistent pool has a failure mode that lands exactly on the
# problem above: tokens are LOST PERMANENTLY when a consumer is killed.
# Measured directly — a pool of 4 tokens dropped to 2 after one SIGTERM'd
# consumer and never recovered. On a host where builds are being SIGTERM'd,
# such a pool drains monotonically until every build runs at -j1, which is
# slower, which causes more deadline kills, which leak more tokens. A shared
# jobserver here needs a supervised holder that resets the pool; that is a
# separate change and is not smuggled in with this one.
#
# WHY -2, AND WHY DEVBOX-ONLY
# Negative values mean "nproc - N", so this tracks core count rather than
# pinning a number. On this 32-core host that yields 30 — which is NOT a cap:
# three agents at 30 jobs each is ~3x oversubscription, measured 2026-11-07
# with load average above 1300 on 32 cores. The value below is chosen so the
# RESULT is the intended concurrency, not so the arithmetic looks tidy.
#
# It is scoped to the devbox because the number only makes sense against a
# measured core count — on a smaller laptop cargo clamps the negative result
# instead of erroring (verified: CARGO_BUILD_JOBS=-20 on a 16-core box still
# builds), so a shared value would silently serialize those hosts.
#
# WHY CARGO IS LOCAL AND NIX IS NOT (measured 2026-11-07)
# The remote fleet builders are a NIX feature, not a cargo feature. nix.conf
# declares `builders = ssh-ng://...` for three fleet hosts with `max-jobs = 0`,
# so `nix build` offloads every derivation it can. Cargo has no equivalent:
# `cargo build` compiles on whichever machine runs it, and only reaches the
# fleet by being wrapped in a Nix derivation (buildRustPackage / crate2nix).
# So a cargo test for the operator crate is ALWAYS local, and the only lever
# on this host for cargo concurrency is this cap. Nix's own budget is
# `cores = 2` per builder, which is unrelated to this value.
#
# FALSIFIER / SCOPE
# `CARGO_BUILD_JOBS=0` errors with `error: jobs may not be 0`, which is how
# this was verified to be honoured at all. An explicit `cargo -j N` on the
# command line still wins, as does a repo that sets `build.jobs` in its own
# .cargo/config.toml — that precedence is intended.
# LIMITATION: home.sessionVariables reach agent shells by INHERITANCE from the
# login session (verified — NIX_REMOTE/KUBECONFIG/COLORTERM are present both
# in an agent shell and inside another agent's live process tree). The
# BASH_ENV loader does not source hm-session-vars, so sessions already running
# at activation time keep the old environment. Landing this is not the same as
# it taking effect: check with `printenv CARGO_BUILD_JOBS` in a NEW session.
#
# MEMORY: `capped` (added 2026-10-10)
# The 2026-09-07 finding above held until 2026-10-10 17:21, when host memory
# exhaustion (MemAvailable 25G -> 3.5G in 12 min, zram swapping instead of
# killing) hung the VM until it was hard-reset. `capped <cmd...>` runs a heavy
# build in its own transient scope with a hard MemoryMax, so a runaway build
# is OOM-killed alone instead of taking every session down. It is opt-in: a
# PATH shim cannot catch builds because each repo's devShell puts its own
# cargo first. The host-wide backstop is systemd-oomd on user.slice
# (/srv/infra hosts/cc-se-sto-devbox-01). No MemoryHigh here, per WHY above:
# throttling builds makes them slower and trips deadlines.
# Override the ceiling with CAPPED_MEMORY_MAX (default 24G).
# Falsifier: `capped sh -c 'cat /proc/self/cgroup'` prints a run-*.scope path,
# and `systemctl --user show <that scope> -p MemoryMax` is not infinity.
{
  lib,
  pkgs,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  # An ABSOLUTE job count, not "nproc - N".
  #
  # The old value was "-8", chosen when this host had 16 cores, where it
  # yielded 8 jobs. The host now has 32 cores, so "-8" yields 24 — the
  # opposite of a cap — and three agents each claiming 24 jobs oversubscribed
  # the box to a load average above 1300 on 32 cores (measured 2026-11-07).
  # An absolute 2 holds regardless of how many cores the host has, which is
  # the property this setting is actually for.
  home.sessionVariables.CARGO_BUILD_JOBS = "2";
  # Builds started from user services (jcode-server and friends) do not
  # inherit a login shell, so declare the same bound there.
  systemd.user.sessionVariables.CARGO_BUILD_JOBS = "2";

  home.packages = [
    (pkgs.writeShellApplication {
      name = "capped";
      text = ''
        if [ "$#" -eq 0 ]; then
          echo "usage: capped <command> [args...]  (CAPPED_MEMORY_MAX=''${CAPPED_MEMORY_MAX:-24G})" >&2
          exit 64
        fi
        exec systemd-run --user --scope --quiet --collect \
          -p MemoryMax="''${CAPPED_MEMORY_MAX:-24G}" \
          -p MemorySwapMax=0 \
          -- "$@"
      '';
    })
  ];
}
