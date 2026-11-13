// Command evalgate is the fleet serialization gate for the nix cold-eval/GC
// critical section. It replaces raw `flock` usage in environment wrappers.
//
// Contract (enforced by evalgate_test.go):
//   - single-flight: concurrent `evalgate run` invocations never overlap
//   - bounded hold: the child is killed at --hold regardless of where it
//     sticks (RuntimeMaxSec via systemd-run --scope when available, process
//     group kill otherwise) — the 2026-11-13 1h51m stuck-holder outage is the
//     falsifier this exists to prevent
//   - bounded wait: acquisition gives up at --wait with a typed error that
//     attributes the current holder (pid, age, command)
//   - kernel release: the flock dies with the process; holder metadata is
//     removed on any exit path
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/gofrs/flock"
)

const (
	exitOK      = 0
	exitUsage   = 64
	exitTimeout = 75 // EX_TEMPFAIL: gate-timeout, retryable
)

type holder struct {
	PID       int       `json:"pid"`
	StartedAt time.Time `json:"started_at"`
	Command   string    `json:"command"`
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	fs := flag.NewFlagSet("evalgate", flag.ContinueOnError)
	lockPath := fs.String("lock", defaultLockPath(), "lock file path")
	wait := fs.Duration("wait", 15*time.Minute, "max time to acquire the gate")
	hold := fs.Duration("hold", 15*time.Minute, "max time the child may hold the gate")
	shared := fs.Bool("shared", false, "take a shared gate")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	rest := fs.Args()
	if len(rest) >= 1 && rest[0] == "sweep" {
		return sweep(rest[1:])
	}
	if len(rest) < 2 || rest[0] != "run" || rest[1] != "--" {
		fmt.Fprintln(os.Stderr, "usage: evalgate [-lock PATH] [-wait D] [-hold D] run -- CMD [ARGS...]")
		fmt.Fprintln(os.Stderr, "       evalgate sweep [-max-age D] [-grace D] [-match RE2] [-apply]")
		return exitUsage
	}
	child := rest[2:]

	if err := os.MkdirAll(filepath.Dir(*lockPath), 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "evalgate: %v\n", err)
		return exitUsage
	}
	fl := flock.New(*lockPath)

	if err := acquire(fl, *wait, *shared); err != nil {
		h := readHolder(*lockPath)
		age := ""
		if h != nil {
			age = fmt.Sprintf(" holder_pid=%d holder_age=%s holder_cmd=%q", h.PID, time.Since(h.StartedAt).Round(time.Second), h.Command)
		}
		fmt.Fprintf(os.Stderr, "evalgate: gate-timeout after %s:%s\n", *wait, age)
		return exitTimeout
	}
	defer release(fl, *lockPath)

	h := holder{PID: os.Getpid(), StartedAt: time.Now(), Command: fmt.Sprint(child)}
	writeHolder(*lockPath, h)

	sigc := make(chan os.Signal, 1)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigc)

	cmd := underSupervisor(child, *hold)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "evalgate: start child: %v\n", err)
		return exitUsage
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		if err == nil {
			return exitOK
		}
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		fmt.Fprintf(os.Stderr, "evalgate: %v\n", err)
		return exitUsage
	case sig := <-sigc:
		_ = cmd.Process.Signal(sig)
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return 128 + int(sig.(syscall.Signal))
	}
}

// acquire takes the exclusive flock via the maintained gofrs/flock library
// (LockWithContext honors the wait budget; no polling loop of our own).
func acquire(f *flock.Flock, wait time.Duration, shared bool) error {
	ctx, cancel := context.WithTimeout(context.Background(), wait)
	defer cancel()
	var ok bool
	var err error
	if shared {
		ok, err = f.TryRLockContext(ctx, 100*time.Millisecond)
	} else {
		ok, err = f.TryLockContext(ctx, 100*time.Millisecond)
	}
	if err != nil {
		return err
	}
	if !ok {
		return errors.New("wait budget exhausted")
	}
	return nil
}

// underSupervisor bounds the child's lifetime. Prefer a systemd scope so the
// kill at the bound is supervisor-enforced and journaled; fall back to the
// official Go 1.20+ command-bounding trio (CommandContext + Cmd.Cancel +
// Cmd.WaitDelay) with a process-group Cancel.
func underSupervisor(child []string, hold time.Duration) *exec.Cmd {
	secs := fmt.Sprintf("%ds", int(hold.Seconds()))
	if p, err := exec.LookPath("systemd-run"); err == nil {
		args := append([]string{"--user", "--scope", "-p", "RuntimeMaxSec=" + secs, "-p", "KillMode=control-group", "--collect", "--"}, child...)
		return exec.Command(p, args...)
	}
	ctx, cancel := context.WithTimeout(context.Background(), hold)
	_ = cancel // owned by Cmd.Cancel below; deadline drives the bound
	cmd := exec.CommandContext(ctx, child[0], child[1:]...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 5 * time.Second
	return cmd
}

func holderPath(lockPath string) string { return lockPath + ".holder.json" }

func writeHolder(lockPath string, h holder) {
	b, _ := json.Marshal(h)
	_ = os.WriteFile(holderPath(lockPath), b, 0o600)
}

func readHolder(lockPath string) *holder {
	b, err := os.ReadFile(holderPath(lockPath))
	if err != nil {
		return nil
	}
	var h holder
	if json.Unmarshal(b, &h) != nil {
		return nil
	}
	return &h
}

func release(fl *flock.Flock, lockPath string) {
	_ = os.Remove(holderPath(lockPath))
	_ = fl.Unlock()
}

func defaultLockPath() string {
	return filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "nix-cold-eval-gc.lock")
}
