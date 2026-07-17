#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
mise-upgrade)
	mise install --yes
	mise upgrade --yes
	;;
*)
	printf 'dotfiles-maintenance: usage: repo-maintenance.sh mise-upgrade\n' >&2
	exit 1
	;;
esac
