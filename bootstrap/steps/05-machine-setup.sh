#!/bin/bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/dotfiles"
CONFIG_JSON="${CONFIG_DIR}/machine-role.json"
CONFIG_ENV="${CONFIG_DIR}/machine-role.env"
RECONFIGURE="${DOTFILES_BOOTSTRAP_RECONFIGURE:-0}"

mkdir -p "$CONFIG_DIR"

write_config() {
	local role="$1"
	local validate_sudo="$2"

	cat >"$CONFIG_JSON" <<EOF
{
	  "role": "${role}",
	  "validateSudoAccess": ${validate_sudo}
	}
EOF

	cat >"$CONFIG_ENV" <<EOF
DOTFILES_MACHINE_ROLE="${role}"
DOTFILES_VALIDATE_SUDO_ACCESS="${validate_sudo}"
EOF
}

print_existing() {
	if [[ -f "$CONFIG_ENV" ]]; then
		# shellcheck disable=SC1090
		source "$CONFIG_ENV"
		echo "==> Machine setup already present"
		echo "    role: ${DOTFILES_MACHINE_ROLE:-general}"
		echo "    sudo validation: ${DOTFILES_VALIDATE_SUDO_ACCESS:-true}"
	fi
}

validate_sudo() {
	local validate="$1"
	if [[ "$validate" != "true" ]]; then
		return 0
	fi

	if ! command -v sudo >/dev/null 2>&1; then
		echo "   ⚠️  sudo is not installed or not on PATH"
		return 0
	fi

	echo "==> Checking sudo access..."
	if sudo -v; then
		echo "   ✅ sudo access is available"
	else
		echo "   ⚠️  sudo validation failed"
		echo "      On Debian/Ubuntu/WSL, an admin can usually grant access with:"
		echo "      sudo usermod -aG sudo $(whoami)"
		echo "      Then log out and back in before rerunning install.sh"
	fi
}

if [[ -f "$CONFIG_JSON" && "$RECONFIGURE" != "1" ]]; then
	print_existing
	exit 0
fi

role="${DOTFILES_MACHINE_ROLE:-}"
validate_sudo_access="${DOTFILES_VALIDATE_SUDO_ACCESS:-}"

if [[ -z "$role" && -t 0 && -t 1 ]]; then
	echo "==> Machine purpose setup"
	echo "    Choose what this machine is mainly for."
	echo "    1) laptop"
	echo "    2) workstation"
	echo "    3) worker"
	echo "    4) server"
	echo "    5) general"
	read -r -p "Role [1-5, default 5]: " role_choice
	case "${role_choice:-5}" in
	1) role="laptop" ;;
	2) role="workstation" ;;
	3) role="worker" ;;
	4) role="server" ;;
	*) role="general" ;;
	esac
fi

if [[ -z "$role" ]]; then
	role="general"
fi

if [[ -z "$validate_sudo_access" && -t 0 && -t 1 ]]; then
	read -r -p "Validate sudo access during setup? [Y/n]: " sudo_choice
	case "${sudo_choice:-}" in
	n | N | no | NO)
		validate_sudo_access="false"
		;;
	*)
		validate_sudo_access="true"
		;;
	esac
fi

if [[ -z "$validate_sudo_access" ]]; then
	validate_sudo_access="true"
fi

write_config "$role" "$validate_sudo_access"
echo "==> Wrote machine setup to $CONFIG_JSON"
validate_sudo "$validate_sudo_access"
