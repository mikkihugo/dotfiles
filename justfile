set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    bash scripts/repo-check.sh

# Report Home Manager units shadowing NixOS units, daemons running outside
# systemd, and who owns contested loopback ports. Non-zero when any is found.
unit-doctor:
    bash scripts/unit-doctor.sh

mise-upgrade:
    mise install --yes
    mise upgrade --yes
