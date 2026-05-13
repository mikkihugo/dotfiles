# home/modules/ops-tools.nix — infrastructure ops CLI tools
#
# Installs ops CLIs from nixpkgs:
#   - kustomize (k8s manifest tooling)
#   - flarectl  (Cloudflare CLI for DNS records etc.)
#
# Identity gating uses Authentik (cluster app under ns `identity`,
# Traefik middleware `identity-forward-auth`). There is no standalone
# Authentik CLI in nixpkgs; admin tasks go through the web UI or
# `kubectl -n identity exec deploy/identity-server -- ak ...`.
#
# bao auth: `bao login -method=oidc` (WebAuthn via Authentik OIDC) or
# approle for automation. BAO_ADDR is set in home.nix.
#
# flarectl reads the API token from CF_API_TOKEN env var. Pull from
# OpenBao at runtime: `export CF_API_TOKEN=$(bao kv get -field=api_token kv/cloudflare)`.
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = [
    pkgs.kustomize
    pkgs.flarectl
  ];
}
