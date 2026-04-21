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
  baoWrapper = pkgs.writeShellScriptBin "bao" ''
    # Use VAULT_ADDR if already set (e.g. by kubectl port-forward).
    # Fall back to CF Tunnel hostname — requires vault.hugo.dk CNAME + CF Access.
    export VAULT_ADDR="''${VAULT_ADDR:-https://vault.hugo.dk}"
    exec ${pkgs.openbao}/bin/bao "$@"
  '';

  autheliaWrapper = pkgs.writeShellScriptBin "authelia" ''
    export X_AUTHELIA_CONFIG_FILTERS="template"
    exec ${pkgs.authelia}/bin/authelia "$@"
  '';
in {
  home.packages = [baoWrapper autheliaWrapper];
}
