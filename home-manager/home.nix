{
  config,
  pkgs,
  ...
}: let
  workerDir = "${config.xdg.dataHome}/ace-worker";
  workerCurrentLink = "${workerDir}/current";
  workerBin = "${workerCurrentLink}/bin/llm-gateway-worker";
  modelsDir = "${config.xdg.dataHome}/llm-worker-models";
  gatewayUrl = "https://llm-gateway.centralcloud.com";
  releaseName = "llm-gateway-worker-linux-x86_64-cuda-sm89.tar.gz";
  environmentFile = "${config.home.homeDirectory}/.config/ace-coder/worker.env";
in {
  home.username = "mhugo";
  home.homeDirectory = "/home/mhugo";
  home.stateVersion = "24.05";

  home.enableNixpkgsReleaseCheck = false;

  home.packages = [
    pkgs.bun
    pkgs.ollama
  ];

  home.file = {
    ".bashrc".source = config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/shell/bash/bashrc";
    ".bash_profile".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/shell/bash/profile";
    ".zshrc".source = config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/shell/zsh/zshrc";
    ".zprofile".source = config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/shell/zsh/profile";
    ".config/starship.toml".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/starship.toml";
    ".config/git/config".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/git/config";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/ripgreprc";
    ".config/zellij/config.kdl".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/zellij/config.kdl";
    ".config/zellij/layouts".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/zellij/layouts";
    ".config/zellij/themes".source =
      config.lib.file.mkOutOfStoreSymlink "/home/mhugo/.dotfiles/config/zellij/themes";
  };

  programs.home-manager.enable = true;

  # ── ACE GPU worker ────────────────────────────────────────────────────────
  # Downloads the sm89 bundle from the gateway on first activation.
  # Self-updates via the director's UpdateBinary mechanism on each restart.
  # Bundle layout: versions/<sha256>/bin/llm-gateway-worker + current -> versions/<sha256>
  # Binary is pre-patchelf'd to /lib64/ld-linux-x86-64.so.2 at build time.
  # CUDA runtime from /usr/lib/wsl/lib (Windows WDDM driver).
  systemd.user.services.ace-worker-seed = {
    Unit = {
      Description = "Seed llm-gateway-worker CUDA binary from gateway";
      Before = ["ace-worker.service"];
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = environmentFile;
      ExecStart = let
        script = pkgs.writeShellScript "ace-worker-seed" ''
          set -euo pipefail
          if [ -x "${workerBin}" ]; then
            echo "ace-worker: binary already seeded"
            exit 0
          fi
          mkdir -p "${workerDir}/versions"
          echo "ace-worker: downloading ${releaseName} from gateway"
          tmp="$(mktemp "${workerDir}/.worker-bundle.XXXXXX.tar.gz")"
          ${pkgs.curl}/bin/curl -fsSL \
            -H "Authorization: Bearer ''${LLM_MUX_API_KEY}" \
            "${gatewayUrl}/worker/releases/${releaseName}" \
            -o "$tmp"
          bundle_hash="$(${pkgs.coreutils}/bin/sha256sum "$tmp" | cut -d' ' -f1)"
          version_dir="${workerDir}/versions/$bundle_hash"
          bundle_dir="$(mktemp -d "${workerDir}/.worker-bundle.XXXXXX")"
          ${pkgs.gnutar}/bin/tar --use-compress-program=${pkgs.gzip}/bin/gzip -xf "$tmp" -C "$bundle_dir"
          ${pkgs.coreutils}/bin/install -d -m755 "$version_dir/bin" "$version_dir/lib"
          ${pkgs.coreutils}/bin/install -m755 "$bundle_dir/bin/llm-gateway-worker" "$version_dir/bin/llm-gateway-worker"
          if [ -f "$bundle_dir/manifest.json" ]; then
            ${pkgs.coreutils}/bin/install -m644 "$bundle_dir/manifest.json" "$version_dir/manifest.json"
          fi
          ${pkgs.findutils}/bin/find "$bundle_dir/lib" -not -type l -exec chmod u+w {} \;
          cp -a "$bundle_dir/lib/." "$version_dir/lib/"
          printf '{"bundle_sha256":"%s","artifact_name":"%s"}\n' \
            "$bundle_hash" "${releaseName}" > "$version_dir/.ace-bundle-state.json"
          ln -sfn "$version_dir" "${workerDir}/current.new"
          mv -f "${workerDir}/current.new" "${workerCurrentLink}"
          chmod -R u+w "$bundle_dir" && rm -rf "$tmp" "$bundle_dir"
          echo "ace-worker: binary seeded successfully (bundle $bundle_hash)"
        '';
      in "${script}";
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.ace-worker = {
    Unit = {
      Description = "ACE Coder GPU worker (llm-gateway-worker, sm89)";
      After = ["network-online.target" "ace-worker-seed.service"];
      Wants = ["network-online.target"];
      Requires = ["ace-worker-seed.service"];
    };
    Service = {
      Type = "simple";
      ExecStart = workerBin;
      Restart = "always";
      RestartSec = "10s";
      WorkingDirectory = workerDir;
      EnvironmentFile = environmentFile;
      Environment = [
        "ACE_WORKER_MASTER_URL=wss://llm-gateway.centralcloud.com/worker"
        "ACE_WORKER_MODELS_DIR=${modelsDir}"
        "ACE_WORKER_MODEL_ID=qwen/Qwen3.5-9B"
        "ACE_WORKER_QUANTIZATION=Q4_K_M"
        "ACE_WORKER_LLM_MODEL_PATH=${modelsDir}/Qwen3.5-9B-Q4_K_M.gguf"
        "ACE_WORKER_DRAFT_LLM_MODEL_PATH=${modelsDir}/Qwen3.5-0.8B-Q4_K_M.gguf"
        "ACE_WORKER_GPU_LAYERS=1000"
        "ACE_WORKER_CONTEXT_WINDOW=131072"
        "ACE_WORKER_INFERENCE_CONCURRENCY=3"
        "ACE_WORKER_INFERENCE_CAPABILITIES=responses,function_calling,thinking,tool_use,rerank"
        "ACE_WORKER_DRAFT_MODEL_ID=qwen/Qwen3.5-0.8B"
        "ACE_WORKER_DRAFT_QUANTIZATION=Q4_K_M"
        "ACE_WORKER_RERANK_MODEL_PATH=${modelsDir}/bge-reranker-v2-m3-Q8_0.gguf"
        "ACE_WORKER_SEMANTIC_MODEL=gte-Qwen2-1.5B-instruct-Q8_0.gguf"
        "ACE_WORKER_CODE_MODEL=jina-code-embeddings-1.5b-Q8_0.gguf"
        "ACE_WORKER_EMBED_CONCURRENCY=4"
        "LD_LIBRARY_PATH=/usr/lib/wsl/lib"
        "RUST_LOG=info"
      ];
      NoNewPrivileges = true;
    };
    Install.WantedBy = ["default.target"];
  };
}
