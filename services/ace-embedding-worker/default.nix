# Thin activation shim — delegates worker configuration to the pinned
# ace-coder flake input so worker builds are cacheable and reproducible.
{pkgs, ace-coder, ...}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [
    ace-coder.homeManagerModules.ace-local-gpu-workers
  ];

  services.ace-local-gpu-workers = {
    enable = true;
    # CPU-static seed — tiny loader bootstraps CUDA binary from gateway on first start.
    package = ace-pkgs.llm-gateway-worker-linux-x86_64-cpu-static;
    # GPU hint so the static loader (no nvml) gets the cuda-sm89 artifact.
    gpuName = "NVIDIA GeForce RTX 4080";
    enableReranker = true;
    environmentFile = "/home/mhugo/.config/ace-coder/worker.env";
    inferenceWorkers = [
      {
        name = "default";
        modelId = "qwen/Qwen3.5-9B";
        backendBaseUrl = "http://127.0.0.1:18400";
      }
    ];
  };
}
