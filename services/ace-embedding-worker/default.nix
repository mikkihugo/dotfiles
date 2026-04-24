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
  SUPERVISOR_STOP_TIMEOUT_SECONDS = 10;
in {
  imports = [
    ace-coder.homeManagerModules.remote-gpu-worker
  ];

  services.remote-gpu-worker = {
    enable = true;
    # Tiny static-musl supervisor-only bundle (~20MB). Director now routes
    # by hostname via host_pool_assignment (SQL worker_kind filter was
    # decommissioned in ace-coder 519deb6c9/fc6e21e61), so the supervisor
    # doesn't need to advertise "cuda-sm89" to get assigned GPU pools.
    # The supervisor downloads the actual worker binary at runtime via
    # LaunchWorker — that binary is director-selected per pool.runtime
    # and fetched from llm-gateway's release store, NOT from Nix.
    # Avoids the fat-worker Nix build which OOMs on bunker (candle-flash-attn
    # CUDA compile) and on llm-gateway (production-python 711-drv rebuild).
    package = ace-pkgs.worker-supervisor-linux-x86_64-bundle;
    gpuName = "NVIDIA GeForce RTX 4080";
    # managedWorkerKind removed 2026-04-24 — director now routes purely by
    # hostname → host_pool_assignment → pool.runtime (Alembic 005 + director
    # list_loader_desired_pools_from_db). Supervisor no longer self-declares.
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };

  # Slow down full supervisor restarts so a crash loop does not thrash WSL2.
  systemd.user.services.remote-gpu-worker.Service = {
    RestartSec = lib.mkForce SUPERVISOR_RESTART_DELAY_SECONDS;
    TimeoutStopSec = lib.mkForce SUPERVISOR_STOP_TIMEOUT_SECONDS;
    SendSIGKILL = lib.mkForce true;
  };
}
