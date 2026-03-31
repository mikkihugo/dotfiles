# Mikki-Bunker ACE GPU worker — single loader service.
#
# Uses the remote-gpu-worker Home Manager module from ace-coder.
# One binary, one WSS connection. Model config comes from the DB.
{ace-coder, pkgs, ...}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [
    ace-coder.homeManagerModules.remote-gpu-worker
    ace-coder.homeManagerModules.remote-embedding-worker
  ];

  services.remote-gpu-worker = {
    enable = true;
    package = ace-pkgs.remote-worker-linux-x86_64-cpu-static;
    gpuName = "NVIDIA GeForce RTX 4080";
    managedWorkerKind = "inference";
    # The worker bundle ships cudart + cublas but not nvrtc or curand.
    # The loader appends the parent LD_LIBRARY_PATH, so we inject cudatoolkit
    # here to cover the missing libs on WSL2 (libnvrtc.so.12, libcurand.so.10).
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };

  services.remote-embedding-worker = {
    enable = true;
    package = ace-pkgs.remote-worker-linux-x86_64-cpu-static;
    gpuName = "NVIDIA GeForce RTX 4080";
    # rerankModel is director-assigned — not a worker config option.
    # The director pushes the rerank model to the worker via DB config.
  };
}
