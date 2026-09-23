# J-Code provider credentials and mutable routing preferences. Secret values are
# rendered only by the ordered user service; neither Nix derivations nor tracked
# files contain provider keys.
{
  config,
  pkgs,
  ...
}: let
  homeDir = config.home.homeDirectory;
  providerDir = "${homeDir}/.config/jcode";
  purposeBackbone = builtins.readFile ../../config/agents/purpose-backbone.md;
  purposeOverlay =
    purposeBackbone
    + ''

      ## Operating mindset

      - Act, don't ask, on approved or mechanically specified work. Ask only for intent, destructive actions, or outward authorization.
      - Verify live state before claiming, and never relay an unverified status.
      - Before non-trivial code, research with 2-4 parallel subagents holding different views, plus one adversarial reviewer that tries to refute, using web search and DeepWiki where available.
      - State the model and effort on every spawn; use the least-cost capable model. Use strong models only for adversarial review or doubt >= 2.
      - Use facade-only VCS; a refusal means stop. Never read secrets from config files. Never invent identity.
      - Done means delivered to main with evidence, not "completed".
    '';
  configureJcodeProviders = pkgs.writeShellApplication {
    name = "configure-jcode-providers";
    runtimeInputs = [pkgs.coreutils pkgs.python3];
    text = ''
      provider_dir="${providerDir}"
      install -d -m 700 "$provider_dir"

      temporary=""
      cleanup() {
        if [ -n "$temporary" ]; then
          rm -f -- "$temporary"
        fi
      }
      trap cleanup EXIT

      render_provider_env() {
        target="$1"
        key="$2"
        secret_file="$3"
        if [ ! -s "$secret_file" ]; then
          echo "jcode provider secret is missing: $secret_file" >&2
          return 1
        fi
        secret="$(cat "$secret_file")"
        temporary="$target.tmp.$$"
        umask 077
        printf '%s=%s\n' "$key" "$secret" > "$temporary"
        chmod 600 "$temporary"
        mv -f "$temporary" "$target"
        temporary=""
        unset secret
      }

      render_provider_env \
        "$provider_dir/kimi.env" \
        "KIMI_API_KEY" \
        "${config.sops.secrets.kimi_api_key.path}"
      render_provider_env \
        "$provider_dir/minimax.env" \
        "MINIMAX_API_KEY" \
        "${config.sops.secrets.minimax_api_key.path}"
      render_provider_env \
        "$provider_dir/ollama-cloud.env" \
        "OLLAMA_API_KEY" \
        "${config.sops.secrets.ollama_api_key.path}"
      render_provider_env \
        "$provider_dir/provider-llm-gateway.env" \
        "JCODE_PROVIDER_LLM_GATEWAY_API_KEY" \
        "${config.sops.secrets.llm_gateway_api_key.path}"
      render_provider_env \
        "$provider_dir/byteplus-ark.env" \
        "BYTEPLUS_ARK_API_KEY" \
        "${config.sops.secrets.byteplus_ark_api_key.path}"

      # Home Manager creates config.toml as a read-only Nix store symlink
      # or with read-only permissions. Fix it so the merge script can write.
      if [ -L "${homeDir}/.jcode/config.toml" ]; then
        cp --remove-destination "${homeDir}/.jcode/config.toml" "${homeDir}/.jcode/config.toml.tmp.$$"
        mv -f "${homeDir}/.jcode/config.toml.tmp.$$" "${homeDir}/.jcode/config.toml"
      fi
      chmod u+w "${homeDir}/.jcode/config.toml" 2>/dev/null || true

      python3 ${../../scripts/jcode-preferences} apply \
        --source ${../../config/jcode/shared-preferences.toml} \
        --target "${homeDir}/.jcode/config.toml"
      chmod 600 "${homeDir}/.jcode/config.toml"
    '';
  };
in {
  sops.secrets.kimi_api_key = {
    key = "sf/env/KIMI_API_KEY";
    mode = "0600";
    sopsFile = ../../secrets/api-keys.yaml;
  };

  sops.secrets.byteplus_ark_api_key = {
    key = "sf/env/BYTEPLUS_ARK_API_KEY";
    mode = "0600";
    sopsFile = ../../secrets/api-keys.yaml;
  };

  home.file.".jcode/swarm-prompt.md" = {
    force = true;
    source = ../../config/jcode/swarm-prompt.md;
  };

  home.file.".jcode/prompt-overlay.md" = {
    force = true;
    text = purposeOverlay;
  };

  # J-Code keeps UI, keybinding, hook, and safety state in mutable config.toml.
  # Apply only the provider-owned keys and named profiles, preserving every
  # unrelated table. The oneshot is ordered after sops-nix materializes new
  # declarations and before the long-lived J-Code runtime starts.
  systemd.user.services.jcode-provider-config = {
    Unit = {
      Description = "Render J-Code provider credentials and routing preferences";
      Requires = ["sops-nix.service"];
      After = ["sops-nix.service"];
      Before = ["jcode-server.service"];
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${configureJcodeProviders}/bin/configure-jcode-providers";
      UMask = "0077";
    };

    Install.WantedBy = ["default.target"];
  };
}
