#!/usr/bin/env bash
# Exercise the actual step-3 shell fragment with a fake sudo. Step 3 must hand
# collection to the system nix-gc.service (the devbox's only collector, which
# holds the cold-eval lock) and never collect itself (infra#2340).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
module="$root/home/modules/nix-gc-sweep.nix"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export fixture

if grep -nE 'nix-collect-garbage|nix store gc|nix-store --gc' "$module" | grep -v '^[0-9]*:#'; then
	echo "FAIL module: nix-gc-sweep must not run a Nix collector itself"
	exit 1
fi

python3 - "$module" "$fixture" <<'PY'
import pathlib,sys
text=pathlib.Path(sys.argv[1]).read_text()
step=text.split('    # Step 3:',1)[1].split('    # Step 4:',1)[0]
step=step[step.index('\n')+1:]
step=step.replace('/run/wrappers/bin/sudo','sudo').replace('/run/current-system/sw/bin/systemctl','systemctl')
step=step.replace("''${","${")
pathlib.Path(sys.argv[2],'step.sh').write_text('set -euo pipefail\nLOG_PREFIX=test\nrun() { "$@"; }\n'+step+'\necho reprovision > "$fixture/reprovision"\n')
PY
mkdir "$fixture/bin"
export PATH="$fixture/bin:$PATH"
cat >"$fixture/bin/sudo" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$fixture/sudo-calls"
[[ "$scenario" != fail ]]
SH
chmod +x "$fixture/bin/"*

for scenario in run dry fail; do
	export scenario
	rm -f "$fixture/sudo-calls" "$fixture/reprovision"
	DRY_RUN=0
	[[ "$scenario" == dry ]] && DRY_RUN=1
	export DRY_RUN
	status=0
	bash "$fixture/step.sh" >"$fixture/output" 2>&1 || status=$?
	case "$scenario" in
	run)
		[[ "$status" == 0 && -f "$fixture/reprovision" ]]
		[[ "$(cat "$fixture/sudo-calls")" == "-n systemctl start --no-block nix-gc.service" ]] || {
			echo "FAIL run: unexpected sudo call: $(cat "$fixture/sudo-calls")"
			exit 1
		}
		;;
	dry)
		[[ "$status" == 0 && ! -e "$fixture/sudo-calls" ]]
		grep -q 'would run: sudo -n systemctl start --no-block nix-gc.service' "$fixture/output"
		;;
	fail)
		[[ "$status" != 0 && ! -f "$fixture/reprovision" ]] || {
			echo "FAIL fail: status=$status (a failed nix-gc start must stop the sweep)"
			cat "$fixture/output"
			exit 1
		}
		;;
	esac
	echo "PASS $scenario: status=$status"
done
