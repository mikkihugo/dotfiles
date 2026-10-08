#!/usr/bin/env bash
# Contract: scripts/forgejo-token-sync renders the Forgejo token from OpenBao
# (kv/forgejo/cli-mhugo, field token) into every static copy a tool needs, so a
# rotation is one `bao kv patch` plus one sync:
#   - $FORGEJO_TOKEN_FILE (runtime file, 0600)
#   - ~/.config/forgejo/token (0600, exact token, no newline)
#   - ~/.local/share/forgejo-cli/keys.json  .hosts["git.centralcloud.net"].token
#   - ~/.config/fj/config.toml  [hosts."https://git.centralcloud.net"] token
#   - ~/.config/jcode/budget-autofix.env  FORGEJO_TOKEN=
# Only the token value changes; every other field and line survives. A file that
# does not exist is skipped, never created. If bao fails or returns an empty
# token NOTHING is touched. The token never reaches stdout, stderr or argv.
#
# Falsifier: a copy still holds the old token after a sync, a copy loses a
# sibling field, a missing file is created, a failed/empty read changes a file,
# a file is group/world-readable, or the token appears in the script's output.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
sync="$root/scripts/forgejo-token-sync"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
failures=0
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

[[ -x "$sync" ]] || {
	printf 'FAIL: %s is missing or not executable\n' "$sync" >&2
	exit 1
}

cat >"$tmp/bao" <<'STUB'
#!/usr/bin/env bash
case "${STUB_MODE:-ok}" in
ok) printf '%s' "${STUB_TOKEN:-NEWTOKEN-0123456789abcdef0123456789abcdef}" ;;
empty) ;;
fail) exit 2 ;;
esac
STUB
chmod 0755 "$tmp/bao"

OLD='OLDTOKEN-0123456789abcdef0123456789abcdef'
NEW='NEWTOKEN-0123456789abcdef0123456789abcdef'

fixture() { # fixture <home>
	local h="$1"
	rm -rf "$h"
	mkdir -p "$h/.config/forgejo" "$h/.config/fj" "$h/.config/jcode" "$h/.local/share/forgejo-cli" "$h/run"
	printf '%s' "$OLD" >"$h/.config/forgejo/token"
	printf '%s' "$OLD" >"$h/run/forgejo-token"
	cat >"$h/.local/share/forgejo-cli/keys.json" <<JSON
{"hosts":{"git.centralcloud.net":{"type":"Application","token":"$OLD","name":"mhugo"}},"aliases":{"git.centralcloud.net:2222":"git.centralcloud.net"}}
JSON
	cat >"$h/.config/fj/config.toml" <<TOML
[hosts]
[hosts."https://git.centralcloud.net"]
name = "mhugo"
default = true
token = "$OLD"
TOML
	cat >"$h/.config/jcode/budget-autofix.env" <<ENV
# budget-autofix-watchdog environment (managed locally; contains a secret)
FORGEJO_TOKEN=$OLD
ENV
	chmod 0644 "$h/.config/fj/config.toml" "$h/.config/forgejo/token"
}

run() { # run <home> <mode>
	HOME="$1" STUB_MODE="$2" BAO_BIN="$tmp/bao" FORGEJO_TOKEN_FILE="$1/run/forgejo-token" "$sync" >"$tmp/out" 2>"$tmp/err"
	echo $?
}

mode() { stat -c '%a' "$1"; }

# --- happy path
h="$tmp/h1"
fixture "$h"
rc="$(run "$h" ok)"
[[ "$rc" == 0 ]] || fail "sync exit $rc, want 0"
[[ "$(cat "$h/run/forgejo-token")" == "$NEW" ]] || fail 'runtime file not updated'
[[ "$(cat "$h/.config/forgejo/token")" == "$NEW" ]] || fail 'forgejo/token copy not updated (must be exact, no newline)'
[[ "$(jq -r '.hosts["git.centralcloud.net"].token' "$h/.local/share/forgejo-cli/keys.json")" == "$NEW" ]] || fail 'keys.json token not updated'
[[ "$(jq -r '.hosts["git.centralcloud.net"].name' "$h/.local/share/forgejo-cli/keys.json")" == mhugo ]] || fail 'keys.json lost the name field'
[[ "$(jq -r '.hosts["git.centralcloud.net"].type' "$h/.local/share/forgejo-cli/keys.json")" == Application ]] || fail 'keys.json lost the type field'
[[ "$(jq -r '.aliases["git.centralcloud.net:2222"]' "$h/.local/share/forgejo-cli/keys.json")" == git.centralcloud.net ]] || fail 'keys.json lost the aliases'
grep -Fxq "token = \"$NEW\"" "$h/.config/fj/config.toml" || fail 'fj config.toml token not updated'
grep -Fxq 'name = "mhugo"' "$h/.config/fj/config.toml" || fail 'fj config.toml lost the name line'
grep -Fxq 'default = true' "$h/.config/fj/config.toml" || fail 'fj config.toml lost the default line'
grep -Fxq "FORGEJO_TOKEN=$NEW" "$h/.config/jcode/budget-autofix.env" || fail 'budget-autofix.env token not updated (must stay unquoted)'
grep -Fq '# budget-autofix-watchdog environment' "$h/.config/jcode/budget-autofix.env" || fail 'budget-autofix.env lost its comment'
for f in run/forgejo-token .config/forgejo/token .local/share/forgejo-cli/keys.json .config/fj/config.toml .config/jcode/budget-autofix.env; do
	[[ "$(mode "$h/$f")" == 600 ]] || fail "$f mode is $(mode "$h/$f"), want 600"
done
grep -rqF -e "$OLD" "$h" && fail 'old token still present in a copy'
grep -qF -e "$NEW" "$tmp/out" "$tmp/err" && fail 'token leaked to the script output'

# --- idempotent
rc="$(run "$h" ok)"
[[ "$rc" == 0 ]] || fail "second sync exit $rc, want 0"
[[ "$(jq -r '.hosts["git.centralcloud.net"].token' "$h/.local/share/forgejo-cli/keys.json")" == "$NEW" ]] || fail 'second sync changed keys.json'

# --- missing files are skipped, not created
h="$tmp/h2"
fixture "$h"
rm -f "$h/.config/jcode/budget-autofix.env" "$h/.local/share/forgejo-cli/keys.json"
rc="$(run "$h" ok)"
[[ "$rc" == 0 ]] || fail "sync with missing files exit $rc, want 0"
[[ ! -e "$h/.config/jcode/budget-autofix.env" ]] || fail 'sync created a missing budget-autofix.env'
[[ ! -e "$h/.local/share/forgejo-cli/keys.json" ]] || fail 'sync created a missing keys.json'
[[ "$(cat "$h/.config/forgejo/token")" == "$NEW" ]] || fail 'present files must still update when others are missing'

# --- bao failure and empty token change nothing
for m in fail empty; do
	h="$tmp/h3-$m"
	fixture "$h"
	before="$(find "$h" -type f -exec sha256sum {} + | sort)"
	rc="$(run "$h" "$m")"
	[[ "$rc" != 0 ]] || fail "$m: sync must exit non-zero"
	after="$(find "$h" -type f -exec sha256sum {} + | sort)"
	[[ "$before" == "$after" ]] || fail "$m: a file changed although no token was read"
done

if ((failures)); then
	printf '%d failure(s)\n' "$failures" >&2
	exit 1
fi
printf 'forgejo-token-sync: ok\n'
