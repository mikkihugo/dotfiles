#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
shift || true
case "$mode" in
shellcheck | shfmt) ;;
*)
	echo "usage: lint-staged-shell.sh {shellcheck|shfmt} FILE..." >&2
	exit 2
	;;
esac

files=()
for file in "$@"; do
	[ -f "$file" ] || continue
	if head -n 1 "$file" | grep -Eq '^#!.*(sh|bash|zsh)([[:space:]]|$)'; then
		files+=("$file")
	fi
done

((${#files[@]} > 0)) || exit 0
if [ "$mode" = shellcheck ]; then
	exec shellcheck --external-sources "${files[@]}"
fi
exec shfmt -d "${files[@]}"
