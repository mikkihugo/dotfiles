# Home Manager module for the ACE embedding worker.
#
# Downloads models from master on first start, extracts the pre-built
# binary from the git-tracked gzip. Connects to the master WebSocket
# and processes embedding requests using local GGUF inference.
#
# Usage in home.nix:
#   imports = [ ../services/ace-embedding-worker ];
#   services.ace-embedding-worker.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ace-embedding-worker;
  baseUrl = "https://llm-gateway.centralcloud.com/embed-worker";
  dataDir = "${config.xdg.dataHome}/ace-embedding-worker";
  binDir = "${dataDir}/bin";
  modelsDir = "${dataDir}/models";
  arch = builtins.elemAt (builtins.split "-" pkgs.stdenv.hostPlatform.system) 0;
  gzBinary = ./bin/${arch}/llm-gateway-embedding-daemon.gz;
in {
  options.services.ace-embedding-worker = {
    enable = lib.mkEnableOption "ACE Coder embedding worker";

    masterUrl = lib.mkOption {
      type = lib.types.str;
      default = "wss://llm-gateway.centralcloud.com/embed-worker";
      description = "Master WebSocket URL to connect to.";
    };

    gpuLayers = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Number of model layers to offload to GPU (1000 = all).";
    };

    semanticModel = lib.mkOption {
      type = lib.types.str;
      default = "gte-Qwen2-1.5B-instruct-Q8_0.gguf";
      description = "Semantic model filename.";
    };

    codeModel = lib.mkOption {
      type = lib.types.str;
      default = "jina-code-embeddings-1.5b-Q8_0.gguf";
      description = "Code model filename.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.ace-embedding-worker = {
      Unit = {
        Description = "ACE Coder embedding worker";
        After = ["network-online.target"];
      };

      Service = {
        Type = "simple";
        Environment = [
          "ACE_EMBEDDING_WORKER_MASTER_URL=${cfg.masterUrl}"
          "ACE_EMBEDDING_WORKER_MODELS_DIR=${modelsDir}"
          "ACE_EMBEDDING_WORKER_SEMANTIC_MODEL=${cfg.semanticModel}"
          "ACE_EMBEDDING_WORKER_CODE_MODEL=${cfg.codeModel}"
          "ACE_EMBEDDING_WORKER_GPU_LAYERS=${toString cfg.gpuLayers}"
          "RUST_LOG=info"
        ];
        ExecStartPre = toString (pkgs.writeShellScript "bootstrap-worker" ''
          set -euo pipefail
          CURL="${pkgs.curl}/bin/curl"

          # Extract binary from git-tracked gzip
          mkdir -p ${binDir}
          echo "Extracting worker binary..."
          ${pkgs.gzip}/bin/gzip -dc ${gzBinary} > "${binDir}/llm-gateway-embedding-daemon.tmp"
          chmod +x "${binDir}/llm-gateway-embedding-daemon.tmp"
          mv "${binDir}/llm-gateway-embedding-daemon.tmp" \
             "${binDir}/llm-gateway-embedding-daemon"

          # Download models from master
          mkdir -p ${modelsDir}
          cd ${modelsDir}
          for model in ${cfg.semanticModel} ${cfg.codeModel}; do
            if [ ! -f "$model" ]; then
              echo "Downloading $model..."
              $CURL -fSL -o "$model.tmp" "${baseUrl}/models/$model"
              mv "$model.tmp" "$model"
            fi
          done
        '');
        ExecStart = "${binDir}/llm-gateway-embedding-daemon";
        Restart = "always";
        RestartSec = "10s";
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
