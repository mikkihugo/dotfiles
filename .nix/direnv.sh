# shellcheck shell=bash
# Purpose: Export Engine org NIX_CONFIG before dotfiles flake admission.
# Consumer: .envrc — remote builds default (max-jobs from builders-nix-config.json).
# Contract: Thin wrapper around nix/cache/org-nix-config.sh; data owner is Engine.

_se_org_nix_activate() {
  local root="${SE_ORG_NIX_CONFIG_ROOT:-${SINGULARITY_ENGINE_ROOT:-}}"
  if [[ -z "$root" || ! -f "$root/nix/cache/org-nix-config.sh" ]]; then
    for root in "${HOME}/code/singularity-engine" "/home/mhugo/code/singularity-engine"; do
      if [[ -f "$root/nix/cache/org-nix-config.sh" ]]; then
        break
      fi
      root=""
    done
  fi
  [[ -n "$root" && -f "$root/nix/cache/org-nix-config.sh" ]] || {
    echo "dotfiles org-direnv: missing Engine nix/cache/org-nix-config.sh (set SE_ORG_NIX_CONFIG_ROOT)" >&2
    return 1
  }
  # shellcheck source=/dev/null
  source "$root/nix/cache/org-nix-config.sh" || return $?
  SE_ORG_NIX_CONFIG_ROOT="$root" se_org_nix_config_activate || return $?
}
_se_org_nix_activate
