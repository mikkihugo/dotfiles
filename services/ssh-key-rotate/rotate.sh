#!/usr/bin/env bash
# Monthly ed25519 rotation for mhugo@hugo.dk — updates lldap, SOPS, ~/.ssh, pushes.
#
# Prereqs (all should be in place on your laptop):
#   ~/.config/sops/age/keys.txt      # age private key for SOPS decrypt
#   ~/.dotfiles                      # working tree with secrets/api-keys.yaml
#   lldap admin_password in SOPS
#   ssh-agent or deploy key for git push to github.com/mikkihugo/dotfiles
#
# Run: manually, or via systemd user timer (see rotate.timer).
set -euo pipefail
shopt -s inherit_errexit

DOTFILES=${DOTFILES:-$HOME/.dotfiles}
SOPS_FILE="$DOTFILES/secrets/api-keys.yaml"
LLDAP_URL=${LLDAP_URL:-https://auth.hugo.dk}
KEY_PATH=${KEY_PATH:-$HOME/.ssh/mhugo_hugodk_ed25519}
USERNAME=${USERNAME:-mhugo}

log() { printf '[%s] ssh-rotate: %s\n' "$(date -u +%FT%TZ)" "$*"; }

command -v sops >/dev/null || {
	echo "sops not in PATH" >&2
	exit 1
}
command -v ssh-keygen >/dev/null || {
	echo "ssh-keygen not in PATH" >&2
	exit 1
}
command -v jq >/dev/null || {
	echo "jq not in PATH" >&2
	exit 1
}

log "generating new ed25519 keypair"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ssh-keygen -t ed25519 -N '' -C "$USERNAME@hugo.dk (rotated $(date -u +%F))" -f "$tmp/key" >/dev/null
new_priv=$(cat "$tmp/key")
new_pub=$(cat "$tmp/key.pub")
log "new pubkey fingerprint: $(ssh-keygen -lf "$tmp/key.pub" | awk '{print $2}')"

log "fetching lldap admin token"
admin_pw=$(sops -d "$SOPS_FILE" | yq -r '.lldap.admin_password')
token=$(curl -sS --max-time 10 "$LLDAP_URL/auth/simple/login" \
	-H 'Content-Type: application/json' \
	--data "$(jq -n --arg u admin --arg p "$admin_pw" '{username:$u,password:$p}')" |
	jq -r .token)
[[ -n "$token" && "$token" != "null" ]] || {
	echo "lldap login failed" >&2
	exit 1
}

log "replacing sshPublicKey in lldap"
curl -sSf --max-time 10 "$LLDAP_URL/api/graphql" \
	-H "Authorization: Bearer $token" \
	-H 'Content-Type: application/json' \
	--data "$(jq -n --arg u "$USERNAME" --arg k "$new_pub" \
		'{query:"mutation UpdateUser($u: UpdateUserInput!) { updateUser(user: $u) { ok } }", variables:{u:{id:$u, insertAttributes:[{name:"sshPublicKey", value:[$k]}]}}}')" \
	>/dev/null

log "writing SOPS — $SOPS_FILE"
sops --set "[\"$USERNAME\"][\"ssh_private_key\"] $(jq -R -s '.' <<<"$new_priv")" "$SOPS_FILE"
sops --set "[\"$USERNAME\"][\"ssh_public_key\"] \"$new_pub\"" "$SOPS_FILE"

log "replacing local $KEY_PATH"
install -m 600 "$tmp/key" "$KEY_PATH"
install -m 644 "$tmp/key.pub" "$KEY_PATH.pub"

log "committing + pushing dotfiles"
git -C "$DOTFILES" add "$SOPS_FILE"
git -C "$DOTFILES" commit -m "secrets: rotate $USERNAME ssh key" -- "$SOPS_FILE"
git -C "$DOTFILES" push origin main

log "done — new key active on lldap + local"
