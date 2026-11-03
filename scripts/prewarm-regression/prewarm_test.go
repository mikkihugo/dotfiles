package prewarm

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

func safeRemovalTarget(path string) bool {
	key := sha256.Sum256([]byte("/home/mhugo/code/jcode"))
	base := "/private-home/.cache/agent-direnv/" + hex.EncodeToString(key[:])
	if path == base {
		return true
	}
	return regexp.MustCompile(`^` + regexp.QuoteMeta(base) + `\.new\.[0-9]+$`).MatchString(path)
}
func TestRMHelper(t *testing.T) {
	if os.Getenv("PREWARM_RM_HELPER") != "1" {
		return
	}
	args := os.Args
	i := 0
	for i < len(args) && args[i] != "--" {
		i++
	}
	if i == len(args) || len(args[i+1:]) != 2 || (args[i+1] != "-rf" && args[i+1] != "-f") || !safeRemovalTarget(args[i+2]) {
		fmt.Fprintln(os.Stderr, "unsafe rm request")
		os.Exit(94)
	}
	target := args[i+2]
	if _, err := os.Lstat(target); os.IsNotExist(err) {
		os.Exit(0)
	} else if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(95)
	}
	dest, err := os.MkdirTemp("/private-home/.fixture-quarantine", "removed-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(96)
	}
	if err = os.Rename(target, filepath.Join(dest, "item")); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(97)
	}
	os.Exit(0)
}
func TestRemovalTargetGuard(t *testing.T) {
	key := sha256.Sum256([]byte("/home/mhugo/code/jcode"))
	base := "/private-home/.cache/agent-direnv/" + hex.EncodeToString(key[:])
	for _, x := range []string{"/", base + "/../other", base + ".new.x", base + "/env", "/tmp/other"} {
		if safeRemovalTarget(x) {
			t.Fatalf("accepted %q", x)
		}
	}
	if !safeRemovalTarget(base) || !safeRemovalTarget(base+".new.123") {
		t.Fatal("expected fixture paths refused")
	}
}
func write(t *testing.T, p, s string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), mode); err != nil {
		t.Fatal(err)
	}
}
func TestProducer(t *testing.T) {
	src := os.Getenv("PREWARM_SOURCE")
	if src == "" {
		src = filepath.Join("..", "..", "home", "modules", "scripts", "agent-direnv-prewarm.sh")
	}
	var err error
	src, err = filepath.Abs(src)
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(src)
	if err != nil || !info.Mode().IsRegular() {
		t.Fatalf("producer unavailable: %s (%v)", src, err)
	}
	bwrap, err := exec.LookPath("bwrap")
	if err != nil {
		t.Fatalf("bwrap required: %v", err)
	}
	tools := os.Getenv("PREWARM_TOOLS")
	if tools == "" {
		tools = "/run/current-system/sw"
	}
	if st, err := os.Stat(filepath.Join(tools, "bin", "bash")); err != nil || !st.Mode().IsRegular() {
		t.Fatalf("tools/bash unavailable: %s", tools)
	}
	for _, mode := range []string{"stable", "drift", "missing", "datefail", "openfail", "writefail"} {
		t.Run(mode, func(t *testing.T) {
			d, err := os.MkdirTemp("", "prewarm-")
			if err != nil {
				t.Fatal(err)
			}
			root := filepath.Join(d, "root")
			home := filepath.Join(d, "home")
			bin := filepath.Join(d, "bin")
			quarantine := filepath.Join(home, ".fixture-quarantine")
			if err := os.MkdirAll(quarantine, 0700); err != nil {
				t.Fatal(err)
			}
			testbin, err := os.Executable()
			if err != nil {
				t.Fatal(err)
			}
			os.MkdirAll(root, 0700)
			os.MkdirAll(bin, 0700)
			if mode != "missing" {
				write(t, filepath.Join(root, ".envrc"), "fixture\n", 0600)
			}
			key := sha256.Sum256([]byte("/home/mhugo/code/jcode"))
			snap := filepath.Join(home, ".cache/agent-direnv", hex.EncodeToString(key[:]))
			write(t, filepath.Join(snap, "env"), "old-env\n", 0600)
			write(t, filepath.Join(snap, "fingerprint"), "old-fingerprint\n", 0600)
			helper := `agent_direnv_fleet_v2_write_snapshot() {
 mkdir -p "$2"; printf 'new-env\n' > "$2/env"
 case "$TEST_MODE" in drift) printf 'changed\n' >> "$1/.envrc";; openfail) mkdir "$2/fingerprint";; writefail) ln -s /dev/full "$2/fingerprint";; esac
}
`
			write(t, filepath.Join(home, ".dotfiles/shell/bash/agent-direnv-fleet-v2-apply.sh"), helper, 0600)
			date := `#!/tools/bin/bash
if [ "${1:-}" = -u ] && [ "${2:-}" = +%FT%TZ ]; then
 if [ "$TEST_MODE" = datefail ]; then exit 7; fi
 printf "2026-11-03T12:34:56Z\n"; exit 0
fi
exec /tools/bin/date "$@"
`
			write(t, filepath.Join(bin, "date"), date, 0700)
			write(t, filepath.Join(bin, "rm"), "#!/tools/bin/bash\nPREWARM_RM_HELPER=1 exec /test-helper -test.run=TestRMHelper -- \"$@\"\n", 0700)
			for _, n := range []string{"direnv", "nix", "flock", "systemctl", "setsid"} {
				write(t, filepath.Join(bin, n), "#!/tools/bin/bash\necho forbidden-"+n+" >&2\nexit 91\n", 0700)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			a := []string{"--unshare-all", "--die-with-parent", "--new-session", "--cap-drop", "ALL", "--clearenv", "--ro-bind", "/nix/store", "/nix/store", "--ro-bind", tools, "/tools", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/home", "--dir", "/home/mhugo", "--dir", "/home/mhugo/code", "--bind", root, "/home/mhugo/code/jcode", "--bind", home, "/private-home", "--ro-bind", bin, "/fixture-bin", "--ro-bind", src, "/producer.sh", "--ro-bind", testbin, "/test-helper", "--setenv", "HOME", "/private-home", "--setenv", "PATH", "/fixture-bin:/tools/bin", "--setenv", "TEST_MODE", mode, "--setenv", "AGENT_DIRENV_EXPORT_BUDGET_S", "0", "--setenv", "AGENT_DIRENV_EXPORT_TIMEOUT_S", "1", "/tools/bin/bash", "/producer.sh"}
			cmd := exec.CommandContext(ctx, bwrap, a...)
			out, err := cmd.CombinedOutput()
			if ctx.Err() != nil {
				t.Fatal(ctx.Err())
			}
			if err != nil {
				t.Fatalf("producer exit %v: %s", err, out)
			}
			if strings.Contains(string(out), "forbidden-") {
				t.Fatalf("cold call: %s", out)
			}
			expected := map[string]string{"stable": "hydrated", "drift": "inputs changed during fleet hydration", "missing": "inputs changed during fleet hydration", "datefail": "could not timestamp fleet fingerprint", "openfail": "could not write fleet fingerprint", "writefail": "could not write fleet fingerprint"}
			if !strings.Contains(string(out), expected[mode]) {
				t.Fatalf("wrong branch for %s: %s", mode, out)
			}
			e, err := os.ReadFile(filepath.Join(snap, "env"))
			if err != nil {
				t.Fatal(err)
			}
			f, err := os.ReadFile(filepath.Join(snap, "fingerprint"))
			if err != nil {
				t.Fatal(err)
			}
			if mode == "stable" {
				entries, err := os.ReadDir(quarantine)
				if err != nil || len(entries) == 0 {
					t.Fatalf("quarantine missing: %v", err)
				}
				fmt.Printf("quarantine_entries=%d real_bwrap=%s helper=/test-helper\n", len(entries), bwrap)
				info, err := os.Stat(filepath.Join(root, ".envrc"))
				if err != nil {
					t.Fatal(err)
				}
				expectedFP := fmt.Sprintf("/home/mhugo/code/jcode\n.envrc %d %d \n2026-11-03T12:34:56Z\n", info.ModTime().Unix(), info.Size())
				if string(e) != "new-env\n" || string(f) != expectedFP {
					t.Fatalf("stable unpublished env=%q fingerprint=%q", e, f)
				}
			} else if string(e) != "old-env\n" || string(f) != "old-fingerprint\n" {
				t.Fatalf("%s published after refusal env=%q fingerprint=%q; output=%s", mode, e, f, out)
			}
			fmt.Printf("case=%s producer_exit=0 preserved=%t\n", mode, mode != "stable")
		})
	}
}
