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
    # RTX 4080 is Ada Lovelace = sm89. Using the CUDA worker variant so the
    # supervisor correctly advertises artifact_variant="cuda-sm89" on
    # LoaderHello and the director assigns it the GPU pool. The CPU-static
    # supervisor bundle advertises "cpu" and the director shelves it with
    # "no serving pools assigned" because no CPU pool is configured here.
    # Followup: ace-coder should expose a CUDA-aware supervisor-only bundle
    # (nvml-wrapper feature enabled) so we get tiny-loader + GPU detection
    # together. Until then, the full worker package is the right pick.
    package = ace-pkgs.remote-worker-linux-x86_64-cuda-sm89;
    gpuName = "NVIDIA GeForce RTX 4080";
    # managedWorkerKind removed 2026-04-24 — director now routes purely by
    # hostname → host_pool_assignment → pool.runtime (Alembic 005 + director
    # list_loader_desired_pools_from_db). Supervisor no longer self-declares.
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };

  # Slow down full supervisor restarts so a crash loop does not thrash WSL2.
  systemd.user.services.remote-gpu-worker.Service.RestartSec = lib.mkForce SUPERVISOR_RESTART_DELAY_SECONDS;
}
