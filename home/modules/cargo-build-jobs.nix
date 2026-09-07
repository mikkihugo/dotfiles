# home/modules/cargo-build-jobs.nix — bound how many rustc ONE cargo may spawn.
# Devbox-only: this is tuned to a measured 16-core host, see WHY -8 below.
#
# WHY
# This box has 16 cores and runs many AI coding agents concurrently. Cargo
# defaults `-j` to nproc, so every agent's build claims 16 rustc regardless of
# how many other builds are already running. 47 concurrent cargo/rustc was
# measured on 2026-09-07 — roughly 3x oversubscription of the CPU.
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
# WHY -8, AND WHY DEVBOX-ONLY
# Negative values mean "nproc - N", so this tracks core count rather than
# pinning a number. On this 16-core host that yields 8: two concurrent builds
# then land at exactly nproc instead of 2x over, four at 2x instead of 4x.
# It is scoped to the devbox because -8 only makes sense against a measured
# core count — on a smaller laptop cargo clamps the negative result instead of
# erroring (verified: CARGO_BUILD_JOBS=-20 on this 16-core box still builds),
# so a shared value would silently serialize those hosts. Raise toward -4 if
# builds feel starved when the box is quiet; lower toward -12 if
# oversubscription still causes stalls.
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
{
  lib,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  # nproc - 8 (= 8 on this 16-core host).
  home.sessionVariables.CARGO_BUILD_JOBS = "-8";
  # Builds started from user services (jcode-server and friends) do not
  # inherit a login shell, so declare the same bound there.
  systemd.user.sessionVariables.CARGO_BUILD_JOBS = "-8";
}
