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
# Every shell file in this repository is hand-written: the generated dispatcher
# and the Bash VCS facade are both retired, and the native operator (`ergo`)
# is the only VCS surface. The exemption split therefore has no members left —
# every file keeps full strictness.
if [ "$mode" = shellcheck ]; then
	exec shellcheck --external-sources "${files[@]}"
fi
exec shfmt -d "${files[@]}"
