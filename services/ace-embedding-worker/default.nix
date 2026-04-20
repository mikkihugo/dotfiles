# Mikki-Bunker ACE GPU worker — single loader service.
#
# Uses the remote-gpu-worker Home Manager module from ace-coder.
# One binary, one WSS connection. Model config comes from the DB.
{
  ace-coder,
  lib,
  pkgs,
  ...
}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
  SUPERVISOR_RESTART_DELAY_SECONDS = 300;
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

  # Slow down full supervisor restarts so a crash loop does not thrash WSL2.
  systemd.user.services.remote-gpu-worker.Service.RestartSec = lib.mkForce SUPERVISOR_RESTART_DELAY_SECONDS;
}
