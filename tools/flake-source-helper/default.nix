# Bootstrap independently of the target flake. Engine's helper expression
# imports the nixpkgs revision and hash from this exact Engine source's lock.
let
  engine = builtins.fetchGit {
    url = "ssh://git@git.centralcloud.net:2222/singularity/singularity-engine.git";
    rev = "819490157dc015132d3fb19a1cb3703e44df541b";
  };
in
  import (engine + "/tools/repository-operator/flake-source/default.nix") {}
