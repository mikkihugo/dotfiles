set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    bash scripts/repo-check.sh

mise-upgrade:
    mise install --yes
    mise upgrade --yes
