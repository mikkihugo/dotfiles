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
    # Supervisor-only package: ~20MB static musl binary, no llama-cpp / candle
    # in its dep graph (worker.nix skips inference features when
    # workerBinaryName == "remote-supervisor"). The supervisor connects to
    # llm-gateway over WSS and fetches the full worker bundle at runtime via
    # the self-update protocol — Nix only seeds the tiny loader.
    package = ace-pkgs.worker-supervisor-linux-x86_64-bundle;
    gpuName = "NVIDIA GeForce RTX 4080";
    managedWorkerKind = "combined";
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };

  # Slow down full supervisor restarts so a crash loop does not thrash WSL2.
  systemd.user.services.remote-gpu-worker.Service.RestartSec = lib.mkForce SUPERVISOR_RESTART_DELAY_SECONDS;
}
