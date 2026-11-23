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
//  3. one Nix build of the caller's own operator output, cached for reuse.
//
// Outside an enrolled repository it refuses: running the wrong repository's
// surface is worse than running none.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const launcherVersion = "0.1.0"

// repositoryMarker is the declaration every enrolled repository carries; the
// operator reads the same file to admit its target. The legacy command
// contract is accepted as a fallback for checkouts that predate the target
// declaration.
const repositoryMarker = ".purpose/repository-operator-target.v1.json"

const legacyRepositoryMarker = ".purpose/commands.json"

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

	// --help and help belong to the launcher: they must answer without a
	// Nix client, so they never reach the build step.
	if len(args) > 0 && launcherOwns(args[0]) {
		if bin, _, err := h.resolve(root, false); err == nil {
			return h.execOperator(bin, args)
		}
		h.printUsage()
		fmt.Fprintln(h.stdout, "\nNo operator is exported or cached for this repository, so the launcher\nanswers --help itself. Load the checkout's direnv to reach the operator surface.")
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

	if cached, ok := h.cached(root); ok {
		return cached, "cache", nil
	}

	if !allowBuild {
		return "", "", errors.New("no operator is exported or cached for this repository")
	}

	bin, err := h.build(root)
	if err != nil {
		return "", "", err
	}
	h.cache(root, bin)
	return bin, "build", nil
}

// build realizes the caller's own operator output. One Nix client, one
// attribute at a time, no attribute listing.
func (h *host) build(root string) (string, error) {
	physical := physicalRoot(root)
	system := nixSystem()
	var failure error
	for _, attr := range operatorAttrs {
		installables := []string{
			fmt.Sprintf("path:%s#%s", physical, attr),
			fmt.Sprintf("path:%s#%s.%s", physical, attr, system),
		}
		for _, installable := range installables {
			out, err := h.exec("nix", "build", "--no-link", "--print-out-paths", installable)
			if err != nil {
				failure = fmt.Errorf("%s: %w", installable, err)
				continue
			}
			storePath := strings.TrimSpace(out)
			if storePath == "" {
				failure = fmt.Errorf("%s: nix build printed no store path", installable)
				continue
			}
			for _, name := range operatorAttrs {
				bin := filepath.Join(storePath, "bin", name)
				if isExecutable(bin) {
					return bin, nil
				}
			}
			failure = fmt.Errorf("%s: %s carries no operator binary", installable, storePath)
		}
	}
	return "", failure
}

// cacheKey binds a cached store path to one repository AND one lock: the
// root plus the digest of its flake.lock. A moved lock is a different key,
// so a stale binary is never served for a new pin.
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
	return hex.EncodeToString(sum.Sum(nil))[:32]
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
	gcRoot(packagePath(bin), cacheKey(root))
}

func (h *host) cacheFile(root string) string {
	dir := cacheDir()
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

// gcRoot keeps a cached store path alive across garbage collection. Nix
// reads the per-user auto roots directory, so one symlink is enough and no
// Nix client is needed.
func gcRoot(pkg, key string) {
	if pkg == "" || !strings.HasPrefix(pkg, "/nix/store/") {
		return
	}
	dir := filepath.Join(dataHome(), "nix", "gcroots", "auto")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	link := filepath.Join(dir, "ergo-launcher-"+key)
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
			return exit.ExitCode()
		}
		fmt.Fprintf(h.stderr, "ergo: cannot run %s: %v\n", bin, err)
		return 2
	}
	return 0
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
		for _, marker := range []string{repositoryMarker, legacyRepositoryMarker} {
			if _, err := os.Stat(filepath.Join(dir, marker)); err == nil {
				return dir, true
			}
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

func execCommand(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
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

// nixSystem maps the running system to Nix's spelling, so the launcher can
// address a `pkg.<system>` output without asking Nix.
func nixSystem() string {
	arch := map[string]string{"amd64": "x86_64", "arm64": "aarch64"}[runtime.GOARCH]
	if arch == "" {
		arch = runtime.GOARCH
	}
	return arch + "-" + runtime.GOOS
}

func cacheDir() string {
	if dir, err := os.UserCacheDir(); err == nil && dir != "" {
		return filepath.Join(dir, "ergo-launcher")
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".cache", "ergo-launcher")
	}
	return filepath.Join(os.TempDir(), "ergo-launcher")
}

func dataHome() string {
	if dir := os.Getenv("XDG_DATA_HOME"); dir != "" {
		return dir
	}
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".local", "share")
	}
	return filepath.Join(os.TempDir(), ".local", "share")
}
