#!/usr/bin/env bash
# Detect duplicate and orphaned user-service state.
#
# Two failure modes this catches, both observed on cc-se-sto-devbox-01 on
# 2026-08-08:
#
#   dupes   - Home Manager writes ~/.config/systemd/user, which takes precedence
#             over /etc/systemd/user. Declaring a unit in both layers means the
#             Home Manager copy silently wins and the NixOS one never runs. That
#             is how jcode-webtty ended up running jcode-tui with no socket,
#             losing the port 7681 bind, and restarting 38 times in 5 minutes.
#
#   orphans - a long-lived daemon started outside systemd keeps holding sockets
#             and ports that a unit wants. Its cgroup has no .service, so systemd
#             will never stop or restart it.
#
# Exits non-zero when either is found, so it can gate a handoff.
set -euo pipefail

status=0

printf '== duplicate units (Home Manager shadowing NixOS) ==\n'
found_dupe=0
if [ -d "$HOME/.config/systemd/user" ]; then
	for hm in "$HOME"/.config/systemd/user/*; do
		[ -e "$hm" ] || continue
		# Only real unit files; *.wants/*.requires are directories, not units.
		[ -d "$hm" ] && continue
		case "$hm" in *.service | *.timer | *.socket | *.target | *.path | *.slice) ;; *) continue ;; esac
		base="$(basename "$hm")"
		sys="/etc/systemd/user/$base"
		[ -e "$sys" ] || continue
		# A symlink to /dev/null is `systemctl mask` - a deliberate override of
		# the NixOS unit, not an accidental duplicate definition.
		if [ "$(readlink -f "$hm" 2>/dev/null)" = "/dev/null" ]; then
			printf '  masked %s (deliberate override, not a dupe)\n' "$base"
			continue
		fi
		found_dupe=1
		status=1
		printf '  DUPE %s\n' "$base"
		printf '       systemd uses: %s\n' \
			"$(systemctl --user show "$base" -p FragmentPath --value 2>/dev/null || echo unknown)"
	done
fi
[ "$found_dupe" -eq 0 ] && printf '  none\n'

printf '\n== orphaned long-lived processes (no owning .service) ==\n'
patterns="${UNIT_DOCTOR_PATTERNS:-jcode ttyd}"
found_orphan=0
for pat in $patterns; do
	while IFS= read -r pid; do
		[ -n "$pid" ] || continue
		etime="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
		[ -n "$etime" ] || continue
		[ "$etime" -ge 300 ] || continue
		unit="$(grep -oE '[a-zA-Z0-9_.@-]+\.service' "/proc/$pid/cgroup" 2>/dev/null | tail -1 || true)"
		case "$unit" in
		"" | *[0-9].service)
			found_orphan=1
			status=1
			printf '  ORPHAN pid=%s up=%ss unit=%s\n' "$pid" "$etime" "${unit:-<none>}"
			printf '         %s\n' "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-130)"
			;;
		esac
	done < <(pgrep -u "$(id -u)" -f -- "$pat" 2>/dev/null || true)
done
[ "$found_orphan" -eq 0 ] && printf '  none\n'

printf '\n== contested loopback ports ==\n'
for port in ${UNIT_DOCTOR_PORTS:-7681}; do
	owners="$(ss -lntp 2>/dev/null | awk -v p=":$port" '$4 ~ p {print}' || true)"
	if [ -z "$owners" ]; then
		printf '  %s: unbound\n' "$port"
	else
		printf '  %s:\n%s\n' "$port" "$(printf '%s' "$owners" | sed 's/^/    /')"
	fi
done

printf '\n'
if [ "$status" -ne 0 ]; then
	printf 'unit-doctor: FAIL - resolve duplicates/orphans above before handoff.\n' >&2
else
	printf 'unit-doctor: OK - one owner per unit, no orphaned daemons.\n'
fi
exit "$status"
