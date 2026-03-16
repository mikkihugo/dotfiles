# Local Home Manager module for Mikki-Bunker ACE workers.
#
# Keep the service definitions in dotfiles so this machine's Home Manager
# target is self-contained. The worker package still comes from the pinned
# ace-coder flake input for reproducible binaries.
{
  config,
  lib,
  pkgs,
  ace-coder,
  ...
}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
  workerPackage = ace-pkgs.llm-gateway-worker-linux-x86_64-cpu-static;
  masterUrl = "wss://llm-gateway.centralcloud.com/worker";
  workerEnvFile = "/home/mhugo/.config/ace-coder/worker.env";
  gpuName = "NVIDIA GeForce RTX 4080";
  modelsDir = "${config.xdg.dataHome}/ace-llm-models";
  rerankModelPath = "${modelsDir}/bge-reranker-v2-m3/bge-reranker-v2-m3-Q8_0.gguf";
  gccLibDir = "${pkgs.stdenv.cc.cc.lib}/lib";

  embeddingStateDir = "${config.xdg.dataHome}/ace-embedding-worker";
  embeddingLoader = "${embeddingStateDir}/bin/llm-gateway-loader";

  inferenceName = "default";
  inferenceBackendBaseUrl = "http://127.0.0.1:18400";
  inferenceModelId = "qwen/Qwen3.5-9B";
  inferenceStateDir = "${config.xdg.dataHome}/ace-inference-worker-${inferenceName}";
  inferenceLoader = "${inferenceStateDir}/bin/llm-gateway-loader";

  loaderMasterUrl = builtins.replaceStrings ["/worker"] ["/loader"] masterUrl;
in {
  systemd.user.services.ace-model-manager = {
    Unit = {
      Description = "Download GGUF models for ACE workers";
      After = ["network-online.target"];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = workerEnvFile;
      ExecStart = toString (pkgs.writeShellScript "ace-model-download" ''
        set -euo pipefail

        mkdir -p ${lib.escapeShellArg modelsDir}

        auth_args=()
        if [ -n "''${LLM_MUX_API_KEY:-}" ]; then
          auth_args=(-H "Authorization: Bearer ''${LLM_MUX_API_KEY}")
        fi

        model_path="${rerankModelPath}"
        model_dir="$(dirname "$model_path")"
        mkdir -p "$model_dir"

        if [ -f "$model_path" ]; then
          echo "Model $(basename "$model_path") exists, skipping"
          exit 0
        fi

        download_url="https://llm-gateway.centralcloud.com/worker/models/$(basename "$model_path")"
        echo "Downloading $(basename "$model_path") from $download_url..."
        ${pkgs.curl}/bin/curl -fSL --progress-bar "''${auth_args[@]}" -o "$model_path.tmp" "$download_url"
        mv "$model_path.tmp" "$model_path"
      '');
    };

    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.ace-embedding-worker = {
    Unit = {
      Description = "ACE embedding worker";
      After = ["network-online.target"];
    };

    Service = {
      Type = "simple";
      EnvironmentFile = workerEnvFile;
      ExecStartPre =
        "${pkgs.bash}/bin/bash -c 'install -d -m755 ${embeddingStateDir}/bin && install -m755 ${workerPackage}/bin/llm-gateway-loader ${embeddingLoader}.new && mv -f ${embeddingLoader}.new ${embeddingLoader} || true'";
      ExecStart = embeddingLoader;
      Environment = [
        "ACE_LOADER_MASTER_URL=${loaderMasterUrl}"
        "ACE_LOADER_WORKER_DIR=${embeddingStateDir}/worker"
        "\"ACE_LOADER_GPU_NAME=${gpuName}\""
        "ACE_EMBEDDING_WORKER_MASTER_URL=${masterUrl}"
        "ACE_EMBEDDING_WORKER_MODELS_DIR=${modelsDir}"
        "ACE_EMBEDDING_WORKER_SEMANTIC_MODEL=gte-qwen2-1.5b/gte-Qwen2-1.5B-instruct-Q8_0.gguf"
        "ACE_EMBEDDING_WORKER_CODE_MODEL=jina-code-1.5b/jina-code-embeddings-1.5b-Q8_0.gguf"
        "ACE_EMBEDDING_WORKER_GPU_LAYERS=1000"
        "ACE_EMBEDDING_WORKER_CONCURRENCY=6"
        "ACE_EMBEDDING_WORKER_RECONNECT_DELAY=10"
        "RUST_LOG=info"
        "LD_LIBRARY_PATH=/usr/lib/wsl/lib:${gccLibDir}"
      ];
      Restart = "always";
      RestartSec = "10s";
    };

    Install.WantedBy = ["default.target"];
  };

  systemd.user.services."ace-inference-worker-${inferenceName}" = {
    Unit = {
      Description = "ACE inference worker (${inferenceName})";
      After = [
        "network-online.target"
        "ace-model-manager.service"
      ];
      Requires = ["ace-model-manager.service"];
    };

    Service = {
      Type = "simple";
      EnvironmentFile = workerEnvFile;
      ExecStartPre =
        "${pkgs.bash}/bin/bash -c 'install -d -m755 ${inferenceStateDir}/bin && install -m755 ${workerPackage}/bin/llm-gateway-loader ${inferenceLoader}.new && mv -f ${inferenceLoader}.new ${inferenceLoader} || true'";
      ExecStart = inferenceLoader;
      Environment = [
        "ACE_LOADER_MASTER_URL=${loaderMasterUrl}"
        "ACE_LOADER_WORKER_DIR=${inferenceStateDir}/worker"
        "\"ACE_LOADER_GPU_NAME=${gpuName}\""
        "ACE_INFERENCE_WORKER_MASTER_URL=${masterUrl}"
        "ACE_INFERENCE_WORKER_BASE_URL=${inferenceBackendBaseUrl}"
        "ACE_INFERENCE_WORKER_MODEL_ID=${inferenceModelId}"
        "ACE_INFERENCE_WORKER_CONCURRENCY=1"
        "ACE_INFERENCE_WORKER_RECONNECT_DELAY=10"
        "ACE_INFERENCE_WORKER_RERANK_MODEL_PATH=${rerankModelPath}"
        "RUST_LOG=info"
        "LD_LIBRARY_PATH=/usr/lib/wsl/lib:${gccLibDir}"
      ];
      Restart = "always";
      RestartSec = "10s";
    };

    Install.WantedBy = ["default.target"];
  };
}
