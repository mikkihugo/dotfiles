set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    python3 scripts/test-codex-preferences.py
    node --test scripts/test-swarm-messages.mjs scripts/test-swarm-hook-config.mjs
    bash scripts/test-repo-vcs.sh
    nix build path:.#homeConfigurations.cc-se-sto-devbox-01.activationPackage --no-link

mise-upgrade:
    mise install --yes
    mise upgrade --yes
