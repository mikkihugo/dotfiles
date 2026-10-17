#!/usr/bin/env bash
# Exercise the actual step-3 shell fragment with fake GC, flock, and sleep.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export fixture
python3 - "$root" "$fixture" <<'PY'
import pathlib,sys
text=(pathlib.Path(sys.argv[1])/'home/modules/nix-gc-sweep.nix').read_text()
step=text.split('    # Step 3:',1)[1].split('    # Step 4:',1)[0]
step=step[step.index('\n')+1:]
step=step.replace('${pkgs.util-linux}/bin/flock','flock').replace('${pkgs.nix}/bin/nix-collect-garbage','nix-collect-garbage')
step=step.replace("''${","${")
pathlib.Path(sys.argv[2],'step.sh').write_text('set -euo pipefail\nLOG_PREFIX=test\nrun() { "$@"; }\n'+step+'\necho reprovision > "$fixture/reprovision"\n')
PY
mkdir "$fixture/bin"
export PATH="$fixture/bin:$PATH"
cat >"$fixture/bin/flock" <<'SH'
#!/usr/bin/env bash
shift 3
exec "$@"
SH
cat >"$fixture/bin/sleep" <<'SH'
#!/usr/bin/env bash
echo "$1" >> "$fixture/backoff"
SH
cat >"$fixture/bin/nix-collect-garbage" <<'SH'
#!/usr/bin/env bash
n=0
[[ ! -e "$fixture/count" ]] || read -r n < "$fixture/count"
echo "$((n+1))" > "$fixture/count"
case "$scenario" in
recover) [[ "$n" -ge 2 ]] && exit 0 ;;
success) exit 0 ;;
other) echo 'error: permission denied' >&2; exit 42 ;;
missing) echo 'error: opening directory "/nix/store/real-path": No such file or directory' >&2; exit 43 ;;
mixed) echo 'error: permission denied' >&2 ;;
esac
echo 'error:' >&2
echo '       … While deleting garbage in store directory "/nix/store/tmp-173965-3979955482"' >&2
echo '       error: opening directory "/nix/store/tmp-173965-3979955482/x/assert": No such file or directory' >&2
exit 44
SH
chmod +x "$fixture/bin/"*
for scenario in recover success other missing mixed exhausted; do
	export scenario
	rm -f "$fixture/count" "$fixture/backoff" "$fixture/reprovision"
	status=0
	bash "$fixture/step.sh" >"$fixture/output" 2>&1 || status=$?
	case "$scenario" in
	recover)
		expected=0
		attempts=3
		;;
	success)
		expected=0
		attempts=1
		;;
	other)
		expected=42
		attempts=1
		;;
	missing)
		expected=43
		attempts=1
		;;
	mixed)
		expected=44
		attempts=1
		;;
	exhausted)
		expected=44
		attempts=3
		;;
	esac
	[[ "$status" == "$expected" ]] || {
		echo "FAIL $scenario: status=$status expected=$expected"
		cat "$fixture/output"
		exit 1
	}
	[[ "$(cat "$fixture/count")" == "$attempts" ]]
	if [[ "$expected" == 0 ]]; then
		[[ -f "$fixture/reprovision" ]]
	else
		[[ ! -f "$fixture/reprovision" ]]
	fi
	if [[ "$attempts" == 3 ]]; then
		[[ "$(cat "$fixture/backoff")" == $'1\n2' ]]
	else
		[[ ! -f "$fixture/backoff" ]]
	fi
	echo "PASS $scenario: status=$status attempts=$attempts"
done
