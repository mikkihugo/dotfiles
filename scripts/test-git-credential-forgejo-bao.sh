#!/usr/bin/env bash
# Contract: scripts/git-credential-forgejo-bao is a git credential helper that
# answers `get` for https://git.centralcloud.net with username=mhugo and the
# Forgejo token read from OpenBao (kv/forgejo/cli-mhugo, field token) at call
# time. It answers nothing for any other host or action and never blocks git
# when OpenBao is unreachable.
#
# Why: a repo-local `credential.helper` once carried a literal Forgejo password
# and answered for EVERY host, so any HTTPS remote could have been handed it.
#
# Falsifier: the helper prints a password for github.com, calls bao for a
# `store`/`erase` action, leaks the token to stderr, or exits non-zero when bao
# fails.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
helper="$root/scripts/git-credential-forgejo-bao"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
failures=0

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	failures=$((failures + 1))
}

[[ -x "$helper" ]] || {
	printf 'FAIL: %s is missing or not executable\n' "$helper" >&2
	exit 1
}

# Stub bao: records argv, prints a canned token (or fails / prints nothing).
cat >"$tmp/bao" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "${STUB_MODE:-ok}" in
ok) printf '%s' 'tok-canned-123' ;;
empty) ;;
fail)
	echo 'permission denied' >&2
	exit 2
	;;
esac
STUB
chmod 0755 "$tmp/bao"

run() { # run <mode> <action> <stdin>
	: >"$tmp/log"
	STUB_LOG="$tmp/log" STUB_MODE="$1" BAO_BIN="$tmp/bao" "$helper" "$2" <<<"$3" >"$tmp/out" 2>"$tmp/err"
	echo $?
}

input_forgejo=$'protocol=https\nhost=git.centralcloud.net\n'
input_github=$'protocol=https\nhost=github.com\n'

rc="$(run ok get "$input_forgejo")"
[[ "$rc" == 0 ]] || fail "get/forgejo exit $rc, want 0"
[[ "$(cat "$tmp/out")" == $'username=mhugo\npassword=tok-canned-123' ]] || fail 'get/forgejo must print exactly username=mhugo and password=<token>'
grep -Fxq 'kv get -mount=kv -field=token forgejo/cli-mhugo' "$tmp/log" || fail 'bao must be asked for kv/forgejo/cli-mhugo field token'
grep -q 'tok-canned-123' "$tmp/err" && fail 'token leaked to stderr'

rc="$(run ok get "$input_github")"
[[ "$rc" == 0 && ! -s "$tmp/out" ]] || fail 'get/github.com must print nothing'
[[ ! -s "$tmp/log" ]] || fail 'bao must not be called for another host'

for action in store erase; do
	rc="$(run ok "$action" "$input_forgejo")"
	[[ "$rc" == 0 && ! -s "$tmp/out" ]] || fail "$action must print nothing"
	[[ ! -s "$tmp/log" ]] || fail "bao must not be called for $action"
done

rc="$(run fail get "$input_forgejo")"
[[ "$rc" == 0 ]] || fail "bao failure must not block git (exit $rc)"
[[ ! -s "$tmp/out" ]] || fail 'bao failure must print no credential'

rc="$(run empty get "$input_forgejo")"
[[ "$rc" == 0 && ! -s "$tmp/out" ]] || fail 'empty token must print no credential'

rc="$(run ok get $'protocol=http\nhost=git.centralcloud.net\n')"
[[ "$rc" == 0 && ! -s "$tmp/out" ]] || fail 'plain http must not receive the token'

if ((failures)); then
	printf '%d failure(s)\n' "$failures" >&2
	exit 1
fi
printf 'git-credential-forgejo-bao: ok\n'
