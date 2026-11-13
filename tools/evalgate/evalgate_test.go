package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"syscall"
	"testing"
	"time"
)

// build produces the evalgate binary under test once per package run.
func build(t *testing.T) string {
	t.Helper()
	bin := filepath.Join(t.TempDir(), "evalgate")
	cmd := exec.Command("go", "build", "-o", bin, ".")
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("go build: %v\n%s", err, out)
	}
	return bin
}

// Falsifier 1 (serialize): if two concurrent critical sections ever overlap,
// the marker file is corrupted / timestamps interleave.
func TestSerialize(t *testing.T) {
	bin := build(t)
	lock := filepath.Join(t.TempDir(), "gate.lock")
	marker := filepath.Join(t.TempDir(), "marker")

	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			cmd := exec.Command(bin, "-lock", lock, "run", "--",
				"sh", "-c", "echo in >> "+marker+"; sleep 1; echo out >> "+marker)
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Errorf("worker: %v\n%s", err, out)
			}
		}()
	}
	wg.Wait()

	b, _ := os.ReadFile(marker)
	var depth, max int
	for _, line := range splitLines(string(b)) {
		switch line {
		case "in":
			depth++
			if depth > max {
				max = depth
			}
		case "out":
			depth--
		}
	}
	if max != 1 || depth != 0 {
		t.Fatalf("critical sections overlapped or leaked: max_depth=%d final_depth=%d", max, depth)
	}
}

// Falsifier 2 (bound-kill): a stuck child must NOT outlive the hold budget.
// Bound + 5s is the contract ceiling.
func TestHoldBoundKillsStuckChild(t *testing.T) {
	bin := build(t)
	lock := filepath.Join(t.TempDir(), "gate.lock")
	start := time.Now()
	cmd := exec.Command(bin, "-lock", lock, "-hold", "2s", "run", "--", "sleep", "600")
	_ = cmd.Run() // any exit code is fine; the bound is the contract
	if d := time.Since(start); d > 7*time.Second {
		t.Fatalf("stuck child survived past hold budget: %s", d)
	}
	// The gate must be immediately re-acquirable (holder metadata cleaned).
	cmd2 := exec.Command(bin, "-lock", lock, "-wait", "2s", "run", "--", "true")
	if out, err := cmd2.CombinedOutput(); err != nil {
		t.Fatalf("gate not re-acquirable after bound-kill: %v\n%s", err, out)
	}
}

// Falsifier 3 (typed error + holder attribution): a second caller times out
// with exit 75 and names the holder.
func TestGateTimeoutAttributesHolder(t *testing.T) {
	bin := build(t)
	lock := filepath.Join(t.TempDir(), "gate.lock")
	first := exec.Command(bin, "-lock", lock, "run", "--", "sleep", "5")
	if err := first.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = syscall.Kill(-first.Process.Pid, syscall.SIGKILL); _ = first.Wait() }()
	time.Sleep(500 * time.Millisecond) // let the first acquire

	second := exec.Command(bin, "-lock", lock, "-wait", "1s", "run", "--", "true")
	out, err := second.CombinedOutput()
	ee, ok := err.(*exec.ExitError)
	if !ok || ee.ExitCode() != 75 {
		t.Fatalf("want exit 75 (gate-timeout), got err=%v out=%s", err, out)
	}
	if !contains(string(out), "holder_pid=") {
		t.Fatalf("gate-timeout lacks holder attribution: %s", out)
	}
}

// Falsifier 4 (kernel release): SIGKILL on the gate releases the flock (the
// kernel owns it) and leaves no holder metadata.
func TestSharedReadersOverlap(t *testing.T) {
	bin := build(t)
	lock := filepath.Join(t.TempDir(), "gate.lock")
	start := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			cmd := exec.Command(bin, "-lock", lock, "-shared", "run", "--", "sleep", "1")
			if out, err := cmd.CombinedOutput(); err != nil {
				t.Errorf("reader: %v\n%s", err, out)
			}
		}()
	}
	wg.Wait()
	if elapsed := time.Since(start); elapsed > 1800*time.Millisecond {
		t.Fatalf("shared readers did not overlap: %s", elapsed)
	}
}

func TestSigkillReleasesLock(t *testing.T) {
	bin := build(t)
	lock := filepath.Join(t.TempDir(), "gate.lock")
	gate := exec.Command(bin, "-lock", lock, "run", "--", "sleep", "60")
	if err := gate.Start(); err != nil {
		t.Fatal(err)
	}
	time.Sleep(500 * time.Millisecond)
	_ = syscall.Kill(gate.Process.Pid, syscall.SIGKILL)
	_, _ = gate.Process.Wait()

	cmd := exec.Command(bin, "-lock", lock, "-wait", "2s", "run", "--", "true")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("lock not released after SIGKILL: %v\n%s", err, out)
	}
}

func splitLines(s string) []string {
	var out []string
	cur := ""
	for _, r := range s {
		if r == '\n' {
			if cur != "" {
				out = append(out, cur)
			}
			cur = ""
			continue
		}
		cur += string(r)
	}
	if cur != "" {
		out = append(out, cur)
	}
	return out
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (func() bool {
		for i := 0; i+len(sub) <= len(s); i++ {
			if s[i:i+len(sub)] == sub {
				return true
			}
		}
		return false
	})()
}
