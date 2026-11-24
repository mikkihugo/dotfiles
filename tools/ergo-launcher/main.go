// Command ergo is the host entry point for the repository command surface.
//
// The operator is ONE Rust binary per checkout: pinned by that checkout's
// flake and exported by its direnv (REPOSITORY_OPERATOR_BIN, or
// REPOSITORY_MANAGER_BIN until the rename lands everywhere). This launcher
// resolves that binary for the CALLER's repository and execs it.
//
// It never evaluates a Nix attribute listing and never builds on --help.
// The previous Bash shim ran `nix eval --raw path:$root#packages.<system>`
// and then `nix build path:$root#<attr>` on EVERY call; under store
// contention the evaluation lock turned those into multi-hour hangs, and
// every agent that called the host entry point spawned a fresh Nix client.
//
// Resolution order:
//
//  1. the operator exported by the caller's own checkout;
//  2. the store path cached for (repository root, flake.lock digest), reused
//     while it still exists and GC-rooted so it survives collection;
//  3. the checkout's own launcher, when it ships one;
//  4. one Nix build of the caller's own operator output, cached for reuse.
//
// Outside an enrolled repository it refuses: running the wrong repository's
// surface is worse than running none.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const launcherVersion = "0.1.0"

// buildTimeoutSeconds bounds the one realization of the caller's operator.
// A saturated evaluation lock otherwise hangs the caller for hours, which is
// the failure this launcher exists to end.
const buildTimeoutSeconds = 7200

// realizationTimeout bounds the Nix client the launcher starts. It is
// generous enough for a full operator build and short enough that a
// saturated evaluation lock fails instead of hanging the caller.
const realizationTimeout = 2 * time.Hour

// repositoryMarker is the declaration every enrolled repository carries; the
// operator reads the same file to admit its target. A checkout without it is
// not enrolled, whatever else it declares.
const repositoryMarker = ".purpose/repository-operator-target.v1.json"

// exportedOperatorVars are the environment variables a checkout's direnv
// exports for its pinned operator: the current name first, the pre-rename
// spelling second.
var exportedOperatorVars = []string{"REPOSITORY_OPERATOR_BIN", "REPOSITORY_MANAGER_BIN"}

// operatorAttrs are the flake attribute names a repository may publish its
// operator under. The list is fixed on purpose: listing the published
// attribute SET is the evaluation that hung for hours, so the launcher asks
// for names it knows instead of asking Nix what exists.
var operatorAttrs = []string{"ergo", "repo"}

func main() {
	wd, err := os.Getwd()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ergo: cannot determine the working directory:", err)
		os.Exit(2)
	}
	h := &host{
		getenv: os.Getenv,
		wd:     wd,
		self:   selfPath(),
		stdout: os.Stdout,
		stderr: os.Stderr,
		exec:   execCommand,
	}
	os.Exit(h.run(os.Args[1:]))
}

// host carries everything the launcher touches outside itself, so the
// resolution rules can be exercised without a real repository or Nix.
type host struct {
	getenv func(string) string
	wd     string
	self   string
	stdout io.Writer
	stderr io.Writer
	// exec runs a command and returns its standard output. It is the ONLY
	// place a Nix client is ever started.
	exec func(name string, args ...string) (string, error)
}

func (h *host) run(args []string) int {
	root, ok := findRepositoryRoot(h.wd)
	if !ok {
		fmt.Fprintf(h.stderr, "ergo: no enrolled repository at or above %s\n", h.wd)
		fmt.Fprintf(h.stderr, "  An enrolled repository declares %s.\n", repositoryMarker)
		fmt.Fprintln(h.stderr, "  cd into one, or run its operator by path.")
		return 2
	}

	// The help requests and a bare invocation belong to the launcher: they
	// must answer without a Nix client, so they never reach the build step.
	if len(args) == 0 || launcherOwns(args[0]) {
		if bin, _, err := h.resolve(root, false); err == nil {
			return h.execOperator(bin, args)
		}
		h.printUsage()
		fmt.Fprintln(h.stdout, "\nNo operator is exported or cached for this repository, so the launcher\nanswers --help itself. Load the checkout's direnv to reach the operator surface.")
		return 0
	}

	// --version belongs to the launcher for the same reason: a version
	// query must never realize an operator.
	if len(args) > 0 && (args[0] == "--version" || args[0] == "-V") {
		if bin, _, err := h.resolve(root, false); err == nil {
			return h.execOperator(bin, args)
		}
		fmt.Fprintf(h.stdout, "ergo %s (host launcher)\n", launcherVersion)
		return 0
	}

	bin, _, err := h.resolve(root, true)
	if err != nil {
		fmt.Fprintf(h.stderr, "ergo: no operator for %s\n", root)
		fmt.Fprintf(h.stderr, "  %v\n", err)
		fmt.Fprintln(h.stderr, "  Load the checkout's direnv, or run its operator by path.")
		return 2
	}
	return h.execOperator(bin, args)
}

// resolve returns the operator binary for root, the source it came from and
// an error when none is available. allowBuild gates the single Nix build:
// the help path resolves without one.
func (h *host) resolve(root string, allowBuild bool) (string, string, error) {
	for _, name := range exportedOperatorVars {
		candidate := h.getenv(name)
		if candidate == "" || !isExecutable(candidate) {
			continue
		}
		if h.isSelf(candidate) {
			// The host-wide export points at THIS launcher. It is not an
			// operator. The previous shim's `command -v` self-match handed
			// callers the wrong surface; refuse to repeat it.
			continue
		}
		return candidate, name, nil
	}

	// The cached path is one this launcher built for THIS repository. It
	// must still exist and must not be this launcher: a cache entry naming
	// the launcher would exec it, and exec it again, forever.
	if cached, ok := h.cached(root); ok && !h.isSelf(cached) {
		return cached, "cache", nil
	}

	// A checkout that publishes no operator output at all is remembered, so
	// later calls go straight to its own launcher instead of paying the
	// realization attempt again.
	if h.hasNoOperator(root) {
		if launcher := repositoryLauncher(root); launcher != "" && !h.isSelf(launcher) {
			return launcher, "repository launcher", nil
		}
		return "", "", errors.New("this repository publishes no operator output")
	}

	if !allowBuild {
		return "", "", errors.New("no operator is exported or cached for this repository")
	}

	bin, err := h.build(root)
	if err == nil {
		h.cache(root, bin)
		return bin, "build", nil
	}

	// A checkout that ships its own launcher drives the surface that way. It
	// is the LAST resort: the launcher in some of those checkouts is a Bash
	// dispatcher whose own verbs start a Nix client, so it must never stand
	// in front of the operator.
	if launcher := repositoryLauncher(root); launcher != "" && !h.isSelf(launcher) {
		if missingAttribute(err) {
			h.markNoOperator(root)
		}
		return launcher, "repository launcher", nil
	}
	return "", "", err
}

// missingAttribute reports whether a realization failed because the
// repository publishes no such attribute — as opposed to a transient
// failure, which must not be remembered.
func missingAttribute(err error) bool {
	return err != nil && strings.Contains(err.Error(), "does not provide attribute")
}

// noOperatorPath is the marker that records a repository with no operator
// output.
func (h *host) noOperatorPath(root string) string {
	return h.cacheFile(root) + ".no-operator"
}

func (h *host) hasNoOperator(root string) bool {
	_, err := os.Stat(h.noOperatorPath(root))
	return err == nil
}

func (h *host) markNoOperator(root string) {
	file := h.noOperatorPath(root)
	tmp := fmt.Sprintf("%s.%d.tmp", file, os.Getpid())
	if err := os.WriteFile(tmp, []byte("no operator output\n"), 0o644); err != nil {
		return
	}
	if err := os.Rename(tmp, file); err != nil {
		os.Remove(tmp)
	}
}

// repositoryLauncher returns the checkout's own launcher, when it ships one.
// The canonical name is `ergo`; `repo` is the name older checkouts still
// use, and the file name belongs to the checkout, not to this launcher.
func repositoryLauncher(root string) string {
	for _, name := range []string{"ergo", "repo"} {
		candidate := filepath.Join(root, "bin", name)
		if isExecutable(candidate) {
			return candidate
		}
	}
	return ""
}

// build realizes the caller's own operator output. One Nix client, one
// attribute at a time, no attribute listing.
func (h *host) build(root string) (string, error) {
	physical := physicalRoot(root)
	var failures []string
	for _, attr := range operatorAttrs {
		installable := fmt.Sprintf("path:%s#%s", physical, attr)
		out, err := h.exec("nix", "build",
			"--no-link",
			"--no-write-lock-file",
			"--print-out-paths",
			"--option", "build-timeout", strconv.Itoa(buildTimeoutSeconds),
			installable)
		if err != nil {
			failures = append(failures, fmt.Sprintf("%s: %v", installable, err))
			continue
		}
		storePath := strings.TrimSpace(out)
		if storePath == "" {
			failures = append(failures, fmt.Sprintf("%s: nix build printed no store path", installable))
			continue
		}
		for _, name := range operatorAttrs {
			bin := filepath.Join(storePath, "bin", name)
			if isExecutable(bin) {
				return bin, nil
			}
		}
		failures = append(failures, fmt.Sprintf("%s: %s carries no operator binary", installable, storePath))
	}
	return "", errors.New(strings.Join(failures, "; "))
}

// cacheKey binds a cached store path to one repository AND one lock: the
// root plus the digest of its flake.lock. A moved lock is a different key,
// so a stale binary is never served for a new pin.
//
// The key also folds in the state of a repository's own operator source.
// The one repository that BUILDS the operator from its own tree (Engine)
// changes the binary without moving its flake.lock, so a lock-only key
// would serve a pre-edit binary — and the cached path is GC-rooted, so it
// would never age out. The previous shim handled this the same way.
//
// The root is resolved physically: /home/mhugo/code/infra and /srv/infra are
// the same repository, and they must share one cache entry.
func cacheKey(root string) string {
	sum := sha256.New()
	sum.Write([]byte(physicalRoot(root)))
	sum.Write([]byte{0})
	if lock, err := os.ReadFile(filepath.Join(root, "flake.lock")); err == nil {
		sum.Write(lock)
	}
	sum.Write([]byte{0})
	sum.Write([]byte(operatorSourceDigest(root)))
	return hex.EncodeToString(sum.Sum(nil))[:32]
}

// operatorSourceDigest digests the operator source a repository builds
// from, when it has one. Repositories that consume a PINNED operator have
// no such tree, and their flake.lock already names the exact binary.
func operatorSourceDigest(root string) string {
	src := filepath.Join(root, "tools", "repository-operator", "src")
	info, err := os.Stat(src)
	if err != nil || !info.IsDir() {
		return ""
	}
	sum := sha256.New()
	for _, manifest := range []string{"Cargo.toml", "Cargo.lock"} {
		if data, err := os.ReadFile(filepath.Join(root, "tools", "repository-operator", manifest)); err == nil {
			fmt.Fprintf(sum, "%s %d\n", manifest, len(data))
			sum.Write(data)
		}
	}
	var walk func(string) error
	walk = func(dir string) error {
		entries, err := os.ReadDir(dir)
		if err != nil {
			return nil
		}
		for _, entry := range entries {
			path := filepath.Join(dir, entry.Name())
			if entry.IsDir() {
				if err := walk(path); err != nil {
					return err
				}
				continue
			}
			file, err := entry.Info()
			if err != nil {
				continue
			}
			fmt.Fprintf(sum, "%d %d %s\n", file.Size(), file.ModTime().UnixNano(), strings.TrimPrefix(path, root))
		}
		return nil
	}
	if err := walk(src); err != nil {
		return ""
	}
	return hex.EncodeToString(sum.Sum(nil))[:16]
}

// physicalRoot resolves a repository root through its symlinks.
func physicalRoot(root string) string {
	if resolved, err := filepath.EvalSymlinks(root); err == nil {
		return resolved
	}
	return root
}

// cached returns the cached store path for root while it still exists.
func (h *host) cached(root string) (string, bool) {
	file := h.cacheFile(root)
	if file == "" {
		return "", false
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return "", false
	}
	bin := strings.TrimSpace(string(data))
	if !isExecutable(bin) {
		return "", false
	}
	return bin, true
}

// cache records the realized operator path and roots it against garbage
// collection.
func (h *host) cache(root, bin string) {
	file := h.cacheFile(root)
	if file == "" {
		return
	}
	tmp := fmt.Sprintf("%s.%d.tmp", file, os.Getpid())
	if err := os.WriteFile(tmp, []byte(bin+"\n"), 0o644); err != nil {
		return
	}
	if err := os.Rename(tmp, file); err != nil {
		os.Remove(tmp)
		return
	}
	h.gcRoot(packagePath(bin), gcRootName(root))
}

func (h *host) cacheFile(root string) string {
	dir := h.cacheDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return ""
	}
	return filepath.Join(dir, cacheKey(root))
}

// packagePath returns the store path that carries a package's binary.
// Nix gives a binary the shape <store>/<name>/bin/<binary>, and the binary
// itself is NOT a store path — a GC root must point at the package, or the
// collector ignores it and the cached binary disappears.
func packagePath(bin string) string {
	dir := filepath.Dir(bin)
	if filepath.Base(dir) != "bin" {
		return ""
	}
	pkg := filepath.Dir(dir)
	if !strings.HasPrefix(pkg, "/nix/store/") {
		return ""
	}
	return pkg
}

// gcRootName keys the GC root by REPOSITORY, not by cache key: when the
// lock moves, the new root replaces the old one, so the superseded package
// stops being rooted and can be collected.
func gcRootName(root string) string {
	sum := sha256.New()
	sum.Write([]byte(physicalRoot(root)))
	return "ergo-launcher-" + hex.EncodeToString(sum.Sum(nil))[:16]
}

// gcRoot keeps a cached store path alive across garbage collection. Nix
// reads the per-user auto roots directory, so one symlink is enough and no
// Nix client is needed.
func (h *host) gcRoot(pkg, name string) {
	if pkg == "" || !strings.HasPrefix(pkg, "/nix/store/") {
		return
	}
	dir := filepath.Join(h.dataHome(), "nix", "gcroots", "auto")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	link := filepath.Join(dir, name)
	tmp := fmt.Sprintf("%s.%d.tmp", link, os.Getpid())
	os.Remove(tmp)
	if err := os.Symlink(pkg, tmp); err != nil {
		return
	}
	if err := os.Rename(tmp, link); err != nil {
		os.Remove(tmp)
	}
}

// execOperator runs the resolved operator with the caller's arguments.
func (h *host) execOperator(bin string, args []string) int {
	cmd := exec.Command(bin, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = h.stdout
	cmd.Stderr = h.stderr
	cmd.Env = os.Environ()
	if err := cmd.Run(); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			return exitStatus(exit)
		}
		fmt.Fprintf(h.stderr, "ergo: cannot run %s: %v\n", bin, err)
		return 2
	}
	return 0
}

// exitStatus reports the status a shell would report for the operator: the
// operator's own exit code, or 128+signal when it was killed by a signal.
func exitStatus(exit *exec.ExitError) int {
	if status, ok := exit.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		return 128 + int(status.Signal())
	}
	if code := exit.ExitCode(); code >= 0 {
		return code
	}
	return 1
}

func (h *host) isSelf(candidate string) bool {
	if candidate == "" || h.self == "" {
		return false
	}
	return resolvePath(candidate) == resolvePath(h.self)
}

func (h *host) printUsage() {
	fmt.Fprintf(h.stdout, `ergo %s — host entry point for the repository operator.

Usage:
  ergo <command> [args...]   run the operator for the current repository
  ergo --help                this text

Resolution:
  1. the operator exported by the checkout's direnv
     (%s);
  2. the store path cached for (repository root, flake.lock digest), reused
     while it still exists and GC-rooted against collection;
  3. one Nix build of the checkout's own operator output, cached for reuse.

The launcher never evaluates a Nix attribute listing and never builds on
--help. Outside an enrolled repository it refuses.
`, launcherVersion, strings.Join(exportedOperatorVars, " or "))
}

// launcherOwns reports whether an argument is the launcher's own help
// request rather than the operator's. The launcher answers those itself:
// they must never reach the build step, because the build is the one path
// that starts a Nix client.
func launcherOwns(arg string) bool {
	switch arg {
	case "--help", "-h", "help":
		return true
	}
	return false
}

// findRepositoryRoot walks up from start to the repository that owns the
// surface.
func findRepositoryRoot(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, repositoryMarker)); err == nil {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

// execCommand runs a command under a deadline. The realization of the
// operator is the one path that starts a Nix client, and a saturated
// evaluation lock makes that client wait for hours; the deadline turns that
// wait into a reported failure.
func execCommand(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), realizationTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return stdout.String(), fmt.Errorf("%w: %s", err, msg)
		}
		return stdout.String(), err
	}
	return stdout.String(), nil
}

func selfPath() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return resolvePath(exe)
}

func resolvePath(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	return filepath.Clean(path)
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir() && info.Mode()&0o111 != 0
}

// cacheDir is where the resolved operator paths are remembered.
func (h *host) cacheDir() string {
	if dir := h.getenv("XDG_CACHE_HOME"); dir != "" {
		return filepath.Join(dir, "ergo-launcher")
	}
	if home := h.getenv("HOME"); home != "" {
		return filepath.Join(home, ".cache", "ergo-launcher")
	}
	return filepath.Join(os.TempDir(), "ergo-launcher")
}

// dataHome is where Nix reads the per-user GC roots from.
func (h *host) dataHome() string {
	if dir := h.getenv("XDG_DATA_HOME"); dir != "" {
		return dir
	}
	if home := h.getenv("HOME"); home != "" {
		return filepath.Join(home, ".local", "share")
	}
	return filepath.Join(os.TempDir(), ".local", "share")
}
