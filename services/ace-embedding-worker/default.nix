# Mikki-Bunker GPU worker — single loader service.
#
# Imports the remote-gpu-worker Home Manager module from ace-coder for the
# systemd plumbing (sd_notify watchdog, GC root, reseed-on-diff). The
# supervisor binary itself comes from inference-fabric — ace-coder no longer
# ships the worker bundle for embeddings.
{
  ace-coder,
  inference-fabric,
  lib,
  pkgs,
  ...
}: let
  fabric-pkgs = inference-fabric.packages.${pkgs.stdenv.hostPlatform.system};
  SUPERVISOR_RESTART_DELAY_SECONDS = 300;
  SUPERVISOR_STOP_TIMEOUT_SECONDS = 10;
in {
  imports = [
    ace-coder.homeManagerModules.remote-gpu-worker
  ];

  services.remote-gpu-worker = {
    enable = true;
    # remote-supervisor binary from inference-fabric. Director routes by
    # hostname via host_pool_assignment (SQL worker_kind filter was
    # decommissioned in ace-coder 519deb6c9/fc6e21e61). Supervisor downloads
    # the actual worker binary at runtime via LaunchWorker from llm-gateway's
    # release store, NOT from Nix — avoids fat-worker CUDA rebuilds.
    package = fabric-pkgs.remote-supervisor-linux-x86_64;
    gpuName = "NVIDIA GeForce RTX 4080";
    # managedWorkerKind removed 2026-04-24 — director now routes purely by
    # hostname → host_pool_assignment → pool.runtime (Alembic 005 + director
    # list_loader_desired_pools_from_db). Supervisor no longer self-declares.
    extraEnv = ["\"LD_LIBRARY_PATH=${pkgs.cudatoolkit}/lib\""];
  };

  systemd.user.services.remote-gpu-worker = {
    Unit.Description = lib.mkForce "Inference Fabric GPU worker";
    # Slow down full supervisor restarts so a crash loop does not thrash WSL2.
    Service = {
      RestartSec = lib.mkForce SUPERVISOR_RESTART_DELAY_SECONDS;
      TimeoutStopSec = lib.mkForce SUPERVISOR_STOP_TIMEOUT_SECONDS;
      SendSIGKILL = lib.mkForce true;
    };
  };
}
