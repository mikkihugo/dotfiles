# shellcheck shell=bash
# Purpose: Export Engine org NIX_CONFIG before dotfiles flake admission.
# Consumer: .envrc — remote builds default (max-jobs from builders-nix-config.json).
# Contract: Thin wrapper around nix/cache/org-nix-config.sh; data owner is Engine.

_se_org_nix_activate() {
  local root="${REPOSITORY_OPERATOR_ORG_NIX_CONFIG_ROOT:-${SINGULARITY_ENGINE_ROOT:-}}"
  if [[ -z "$root" || ! -f "$root/nix/cache/org-nix-config.sh" ]]; then
    for root in "${HOME}/code/singularity-engine" "/home/mhugo/code/singularity-engine"; do
      if [[ -f "$root/nix/cache/org-nix-config.sh" ]]; then
        break
      fi
      root=""
    done
  fi
  [[ -n "$root" && -f "$root/nix/cache/org-nix-config.sh" ]] || {
    echo "dotfiles org-direnv: missing Engine nix/cache/org-nix-config.sh (set REPOSITORY_OPERATOR_ORG_NIX_CONFIG_ROOT)" >&2
    return 1
  }
  # shellcheck source=/dev/null
  source "$root/nix/cache/org-nix-config.sh" || return $?
  # `command -v`, not `declare -F`: under zsh, `declare -F` succeeds for an
  # undefined function name, so it would take the operator branch and call a
  # function that does not exist (exit 127).
  if command -v repository_operator_org_nix_config_activate >/dev/null 2>&1; then
    REPOSITORY_OPERATOR_ORG_NIX_CONFIG_ROOT="$root" repository_operator_org_nix_config_activate || return $?
  else
    REPOSITORY_OPERATOR_ORG_NIX_CONFIG_ROOT="$root" REPOSITORY_MANAGER_ORG_NIX_CONFIG_ROOT="$root" repository_manager_org_nix_config_activate || return $?
  fi
}
_se_org_nix_activate
