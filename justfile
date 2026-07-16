set dotenv-load := false

mod vcs 'just/vcs.just'

check:
    bash scripts/test-repo-vcs.sh
    nix build path:.#homeConfigurations.cc-se-sto-devbox-01.activationPackage --no-link

mise-upgrade:
    mise install --yes
    mise upgrade --yes
