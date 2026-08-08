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
        "$provider_dir/minimax-direct.env" \
        "MINIMAX_API_KEY" \
        "${config.sops.secrets.minimax_api_key.path}"
      render_provider_env \
        "$provider_dir/provider-llm-gateway.env" \
        "JCODE_PROVIDER_LLM_GATEWAY_API_KEY" \
        "${config.sops.secrets.llm_gateway_api_key.path}"

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

  home.file.".jcode/swarm-prompt.md" = {
    force = true;
    source = ../../config/jcode/swarm-prompt.md;
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
