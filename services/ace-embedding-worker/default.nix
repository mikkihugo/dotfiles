# Mikki-Bunker ACE GPU worker — single loader service.
#
# Uses the remote-gpu-worker Home Manager module from ace-coder.
# One binary, one WSS connection. Model config comes from the DB.
{
  ace-coder,
  pkgs,
  ...
}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [
    ace-coder.homeManagerModules.remote-gpu-worker
  ];

  services.remote-gpu-worker = {
    enable = true;
    package = ace-pkgs.remote-worker-linux-x86_64-cpu-static;
    gpuName = "NVIDIA GeForce RTX 4080";
    managedWorkerKind = "combined";
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };
}
