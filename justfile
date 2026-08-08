set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    bash scripts/repo-check.sh

# Report Home Manager units shadowing NixOS units, daemons running outside
# systemd, and who owns contested loopback ports. Non-zero when any is found.
unit-doctor:
    bash scripts/unit-doctor.sh

# Prune Codex subagent rollouts (dry run; pass --apply to delete). Codex has no
# retention of its own for ~/.codex/sessions, which grows without bound.
codex-rollout-gc *ARGS:
    bash scripts/codex-rollout-gc.sh {{ARGS}}

mise-upgrade:
    mise install --yes
    mise upgrade --yes
