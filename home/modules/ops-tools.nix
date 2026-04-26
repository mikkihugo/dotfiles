# home/modules/ops-tools.nix — infrastructure ops CLI tools
#
# Installs ops CLIs from nixpkgs with pre-configured wrappers:
#   - bao      (openbao, vault-compatible CLI → vault.hugo.dk)
#   - authelia (Authelia CLI → auth.hugo.dk)
#
# VAULT_ADDR is set by the wrapper so `bao login / bao kv get` just works.
# Token is not stored here — use `bao login` interactively (WebAuthn via
# Authelia OIDC, or approle for automation).
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
  home.packages = [autheliaWrapper pkgs.kustomize];
}
