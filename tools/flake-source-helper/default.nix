# Bootstrap independently of the target flake. Engine's helper expression
# imports the nixpkgs revision and hash from this exact Engine source's lock.
let
  engine = builtins.fetchGit {
    url = "ssh://git@git.centralcloud.net:2222/singularity/singularity-engine.git";
    rev = "89abff9f058a543aa9597f20007a9b0ee6673db6";
  };
in
  import (engine + "/tools/repository-operator/flake-source/default.nix") {}
