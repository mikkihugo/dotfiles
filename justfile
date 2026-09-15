set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    bash scripts/repo-check.sh

# Report Home Manager units shadowing NixOS units, daemons running outside
# systemd, and who owns contested loopback ports. Non-zero when any is found.
# Source-of-truth lives in /srv/infra/scripts/diagnose-systemd-user-units.sh
# (fleet operator GitOps). This justfile recipe is kept as a thin alias.
unit-doctor:
    bash /srv/infra/scripts/diagnose-systemd-user-units.sh

# Prune Codex subagent rollouts (dry run; pass --apply to delete). Codex has no
# retention of its own for ~/.codex/sessions, which grows without bound.
codex-rollout-gc *ARGS:
    bash scripts/codex-rollout-gc.sh {{ARGS}}

mise-upgrade:
    mise install --yes
    mise upgrade --yes
