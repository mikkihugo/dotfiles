# home/modules/ops-tools.nix — infrastructure ops CLI tools
#
# Installs ops CLIs from nixpkgs with pre-configured wrappers:
#   - bao       (openbao, vault-compatible CLI → vault.hugo.dk)
#   - authelia  (Authelia CLI → auth.hugo.dk)
#   - flarectl  (Cloudflare CLI for DNS records etc.)
#
# VAULT_ADDR is set by the wrapper so `bao login / bao kv get` just works.
# Token is not stored here — use `bao login` interactively (WebAuthn via
# Authelia OIDC, or approle for automation).
#
# flarectl reads the API token from CF_API_TOKEN env var. Pull from
# OpenBao at runtime: `export CF_API_TOKEN=$(bao kv get -field=api_token kv/cloudflare)`.
{
  config,
  pkgs,
  lib,
  ...
}: let
  autheliaWrapper = pkgs.writeShellScriptBin "authelia" ''
    export X_AUTHELIA_CONFIG_FILTERS="template"
    exec ${pkgs.authelia}/bin/authelia "$@"
  '';
in {
  home.packages = [
    autheliaWrapper
    pkgs.kustomize
    pkgs.flarectl
  ];
}
