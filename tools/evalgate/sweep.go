// sweep: kill nix processes that exceed a wall-clock budget.
//
// Purpose: no component in the build chain owns a deadline. A dead remote
// builder turns a 30 s derivation into a 1h52m hang that holds the fleet
// eval locks (observed 2026-11-13, three wedged builds). The sweep is the
// bounded-holder watchdog for processes that never went through `evalgate run`.
//
// Contract:
//   - dry-run by default; -apply performs TERM then KILL after -grace
//   - matches cmdline against -match (RE2); age read from /proc/<pid>/stat
//   - never signals PID 1, our own tree, or processes younger than -max-age
//   - one line per candidate (or action) on stdout; exit 0 always unless usage
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const defaultMatch = `^\S*/nix( |$).*(build|develop|print-dev-env)`

func sweep(args []string) int {
	fs := flag.NewFlagSet("evalgate sweep", flag.ContinueOnError)
	maxAge := fs.Duration("max-age", 45*time.Minute, "kill processes older than this")
	grace := fs.Duration("grace", 5*time.Second, "wait between TERM and KILL")
	pattern := fs.String("match", defaultMatch, "RE2 matched against /proc/<pid>/cmdline")
	apply := fs.Bool("apply", false, "actually signal candidates (default: dry run)")
	if err := fs.Parse(args); err != nil {
		return exitUsage
	}
	re, err := regexp.Compile(*pattern)
	if err != nil {
		fmt.Fprintf(os.Stderr, "evalgate sweep: bad -match: %v\n", err)
		return exitUsage
	}
	self := os.Getpid()
	cands, err := sweepCandidates(re, *maxAge, self)
	if err != nil {
		fmt.Fprintf(os.Stderr, "evalgate sweep: %v\n", err)
		return exitUsage
	}
	for _, c := range cands {
		if !*apply {
			fmt.Printf("would-kill pid=%d age=%s cmd=%q\n", c.pid, c.age.Round(time.Second), c.cmd)
			continue
		}
		fmt.Printf("kill pid=%d age=%s cmd=%q\n", c.pid, c.age.Round(time.Second), c.cmd)
		if err := syscall.Kill(c.pid, syscall.SIGTERM); err != nil {
			fmt.Fprintf(os.Stderr, "kill %d: %v\n", c.pid, err)
			continue
		}
		time.Sleep(*grace)
		if err := syscall.Kill(c.pid, 0); err == nil {
			_ = syscall.Kill(c.pid, syscall.SIGKILL)
		}
	}
	if !*apply && len(cands) > 0 {
		fmt.Println("dry run: rerun with -apply to signal")
	}
	return exitOK
}

type candidate struct {
	pid int
	age time.Duration
	cmd string
}

func sweepCandidates(re *regexp.Regexp, maxAge time.Duration, self int) ([]candidate, error) {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil, err
	}
	boot, _ := bootTime()
	now := time.Now()
	var out []candidate
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid == self || pid == 1 {
			continue
		}
		if pid == os.Getppid() {
			continue
		}
		raw, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil || len(raw) == 0 {
			continue
		}
		cmd := strings.TrimSpace(strings.ReplaceAll(string(raw), "\x00", " "))
		if !re.MatchString(cmd) {
			continue
		}
		start, err := procStart(pid)
		if err != nil {
			continue
		}
		age := now.Sub(boot.Add(start))
		if age < maxAge {
			continue
		}
		out = append(out, candidate{pid: pid, age: age, cmd: cmd})
	}
	return out, nil
}

func bootTime() (time.Time, error) {
	b, err := os.ReadFile("/proc/stat")
	if err != nil {
		return time.Time{}, err
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "btime ") {
			secs, err := strconv.ParseInt(strings.TrimSpace(strings.TrimPrefix(line, "btime ")), 10, 64)
			if err != nil {
				return time.Time{}, err
			}
			return time.Unix(secs, 0), nil
		}
	}
	return time.Time{}, fmt.Errorf("btime not found")
}

// procStart returns process start time relative to boot (field 22, clock ticks).
func procStart(pid int) (time.Duration, error) {
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "stat"))
	if err != nil {
		return 0, err
	}
	// comm can contain spaces/parens; start counting after the last ')'.
	s := string(b)
	i := strings.LastIndexByte(s, ')')
	if i < 0 || i+2 >= len(s) {
		return 0, fmt.Errorf("bad stat")
	}
	fields := strings.Fields(s[i+2:])
	if len(fields) < 20 {
		return 0, fmt.Errorf("short stat")
	}
	ticks, err := strconv.ParseInt(fields[19], 10, 64) // field 22 overall
	if err != nil {
		return 0, err
	}
	return time.Duration(ticks) * (time.Second / 100), nil // USER_HZ=100
}
