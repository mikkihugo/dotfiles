package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// fakeOperator writes an executable that stands in for the operator binary.
func fakeOperator(t *testing.T, dir, name string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	body := "#!/bin/sh\necho \"fake-operator $*\"\n"
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatalf("write fake operator: %v", err)
	}
	return path
}

// fakeRepository writes an enrolled repository skeleton and returns its root.
func fakeRepository(t *testing.T) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), "checkout")
	if err := os.MkdirAll(filepath.Join(root, ".purpose"), 0o755); err != nil {
		t.Fatalf("create repository: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, repositoryMarker), []byte("{}\n"), 0o644); err != nil {
		t.Fatalf("write repository marker: %v", err)
	}
	return root
}

func newHost(t *testing.T, wd string, env map[string]string) (*host, *bytes.Buffer, *[]string) {
	t.Helper()
	var out bytes.Buffer
	calls := &[]string{}
	h := &host{
		getenv: func(name string) string {
			if value, ok := env[name]; ok {
				return value
			}
			return os.Getenv(name)
		},
		wd:     wd,
		self:   filepath.Join(t.TempDir(), "ergo-launcher"),
		stdout: &out,
		stderr: &out,
		exec: func(name string, args ...string) (string, error) {
			*calls = append(*calls, name+" "+strings.Join(args, " "))
			return "", nil
		},
	}
	return h, &out, calls
}

func TestRefusesOutsideAnEnrolledRepository(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	outside := t.TempDir()
	h, out, calls := newHost(t, outside, map[string]string{})

	if code := h.run([]string{"vcs", "status"}); code != 2 {
		t.Fatalf("exit code = %d, want 2 (output: %s)", code, out.String())
	}
	if !strings.Contains(out.String(), "no enrolled repository") {
		t.Fatalf("refusal is not explicit: %s", out.String())
	}
	if len(*calls) != 0 {
		t.Fatalf("a Nix client was started outside a repository: %v", *calls)
	}
}

func TestExportedOperatorRunsWithoutNix(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)
	operator := fakeOperator(t, t.TempDir(), "ergo")

	h, out, calls := newHost(t, root, map[string]string{"REPOSITORY_OPERATOR_BIN": operator})

	if code := h.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out.String())
	}
	if !strings.Contains(out.String(), "fake-operator vcs status") {
		t.Fatalf("the exported operator did not run: %s", out.String())
	}
	if len(*calls) != 0 {
		t.Fatalf("a Nix client was started: %v", *calls)
	}
}

func TestTheRenamedExportIsAccepted(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)
	operator := fakeOperator(t, t.TempDir(), "ergo")

	h, out, calls := newHost(t, root, map[string]string{"REPOSITORY_MANAGER_BIN": operator})

	if code := h.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out.String())
	}
	if len(*calls) != 0 {
		t.Fatalf("a Nix client was started: %v", *calls)
	}
}

func TestHostWideExportOfTheLauncherItselfIsIgnored(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)
	h, out, calls := newHost(t, root, map[string]string{})
	// The host-wide export points at the launcher itself: it is not an
	// operator, and exec'ing it would loop forever.
	self := filepath.Join(t.TempDir(), "ergo")
	if err := os.WriteFile(self, []byte("#!/bin/sh\necho LAUNCHER-SELF\n"), 0o755); err != nil {
		t.Fatalf("write launcher stand-in: %v", err)
	}
	h.self = self
	h.getenv = func(name string) string {
		if name == "REPOSITORY_OPERATOR_BIN" {
			return self
		}
		return ""
	}
	// No operator output is available, so the build fallback must fail.
	h.exec = func(name string, args ...string) (string, error) {
		*calls = append(*calls, name+" "+strings.Join(args, " "))
		return "", os.ErrNotExist
	}

	if code := h.run([]string{"vcs", "status"}); code != 2 {
		t.Fatalf("exit code = %d, want 2 (output: %s)", code, out.String())
	}
	if strings.Contains(out.String(), "LAUNCHER-SELF") {
		t.Fatalf("the launcher exec'd itself: %s", out.String())
	}
}

func TestHelpNeverStartsANixClient(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)

	for _, arg := range []string{"--help", "-h", "help"} {
		h, out, calls := newHost(t, root, map[string]string{})

		if code := h.run([]string{arg}); code != 0 {
			t.Fatalf("%s: exit code = %d, want 0 (output: %s)", arg, code, out.String())
		}
		if !strings.Contains(out.String(), "host entry point") {
			t.Fatalf("%s did not print the launcher usage: %s", arg, out.String())
		}
		if len(*calls) != 0 {
			t.Fatalf("%s started a Nix client: %v", arg, *calls)
		}
	}
}

func TestCachedOperatorIsReusedWithoutNix(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	root := fakeRepository(t)
	operator := fakeOperator(t, t.TempDir(), "ergo")

	h, out, calls := newHost(t, root, map[string]string{})
	entry := filepath.Join(cache, "ergo-launcher", cacheKey(root))
	if err := os.MkdirAll(filepath.Dir(entry), 0o755); err != nil {
		t.Fatalf("create cache directory: %v", err)
	}
	if err := os.WriteFile(entry, []byte(operator+"\n"), 0o644); err != nil {
		t.Fatalf("write cache entry: %v", err)
	}

	if code := h.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out.String())
	}
	if !strings.Contains(out.String(), "fake-operator vcs status") {
		t.Fatalf("the cached operator did not run: %s", out.String())
	}
	if len(*calls) != 0 {
		t.Fatalf("a Nix client was started: %v", *calls)
	}
}

func TestTheRepositorysOwnLauncherIsUsedWhenItShipsOne(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)
	if err := os.MkdirAll(filepath.Join(root, "bin"), 0o755); err != nil {
		t.Fatalf("create bin directory: %v", err)
	}
	launcher := fakeOperator(t, filepath.Join(root, "bin"), "repo")

	h, out, calls := newHost(t, root, map[string]string{})

	if code := h.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out.String())
	}
	if !strings.Contains(out.String(), "fake-operator vcs status") {
		t.Fatalf("the repository launcher did not run: %s", out.String())
	}
	if len(*calls) != 0 {
		t.Fatalf("a Nix client was started: %v", *calls)
	}
	_ = launcher
}

func TestACachedPathThatNamesTheLauncherIsRefused(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	root := fakeRepository(t)

	h, out, calls := newHost(t, root, map[string]string{})
	// A cache entry naming the launcher itself would exec it forever.
	entry := filepath.Join(cache, "ergo-launcher", cacheKey(root))
	if err := os.MkdirAll(filepath.Dir(entry), 0o755); err != nil {
		t.Fatalf("create cache directory: %v", err)
	}
	if err := os.WriteFile(entry, []byte(h.self+"\n"), 0o644); err != nil {
		t.Fatalf("write cache entry: %v", err)
	}
	h.exec = func(name string, args ...string) (string, error) {
		*calls = append(*calls, name+" "+strings.Join(args, " "))
		return "", os.ErrNotExist
	}

	if code := h.run([]string{"vcs", "status"}); code != 2 {
		t.Fatalf("exit code = %d, want 2 (output: %s)", code, out.String())
	}
	if len(*calls) != 2 {
		t.Fatalf("the cached launcher was not refused: %v", *calls)
	}
}

func TestTheCacheKeyMovesWithTheOperatorSource(t *testing.T) {
	root := fakeRepository(t)
	src := filepath.Join(root, "tools", "repository-operator", "src")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatalf("create operator source: %v", err)
	}
	source := filepath.Join(src, "main.rs")
	if err := os.WriteFile(source, []byte("fn main() {}\n"), 0o644); err != nil {
		t.Fatalf("write operator source: %v", err)
	}
	before := cacheKey(root)
	if err := os.WriteFile(source, []byte("fn main() { /* edited */ }\n"), 0o644); err != nil {
		t.Fatalf("edit operator source: %v", err)
	}
	if err := os.Chtimes(source, time.Now().Add(time.Minute), time.Now().Add(time.Minute)); err != nil {
		t.Fatalf("touch operator source: %v", err)
	}
	if after := cacheKey(root); after == before {
		t.Fatal("the cache key did not move with the operator source")
	}
}

func TestVersionNeverStartsANixClient(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)

	for _, arg := range []string{"--version", "-V"} {
		h, out, calls := newHost(t, root, map[string]string{})
		if code := h.run([]string{arg}); code != 0 {
			t.Fatalf("%s: exit code = %d, want 0 (output: %s)", arg, code, out.String())
		}
		if !strings.Contains(out.String(), "host launcher") {
			t.Fatalf("%s did not print the launcher version: %s", arg, out.String())
		}
		if len(*calls) != 0 {
			t.Fatalf("%s started a Nix client: %v", arg, *calls)
		}
	}
}

func TestOneBuildIsCachedAndReused(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	root := fakeRepository(t)
	store := t.TempDir()
	if err := os.MkdirAll(filepath.Join(store, "bin"), 0o755); err != nil {
		t.Fatalf("create store path: %v", err)
	}
	fakeOperator(t, filepath.Join(store, "bin"), "ergo")

	h, out, calls := newHost(t, root, map[string]string{})
	h.exec = func(name string, args ...string) (string, error) {
		*calls = append(*calls, name+" "+strings.Join(args, " "))
		return store, nil
	}

	if code := h.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out.String())
	}
	if len(*calls) != 1 {
		t.Fatalf("Nix clients started = %d, want 1: %v", len(*calls), *calls)
	}
	if !strings.Contains((*calls)[0], "path:"+root+"#ergo") {
		t.Fatalf("unexpected installable: %s", (*calls)[0])
	}

	// The second call must come from the cache, with no Nix client.
	second, out2, calls2 := newHost(t, root, map[string]string{})
	if code := second.run([]string{"vcs", "status"}); code != 0 {
		t.Fatalf("exit code = %d, want 0 (output: %s)", code, out2.String())
	}
	if len(*calls2) != 0 {
		t.Fatalf("the cached operator was not reused: %v", *calls2)
	}
}

func TestTheBuildAsksForTwoAttributesAtMost(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root := fakeRepository(t)

	h, out, calls := newHost(t, root, map[string]string{})
	h.exec = func(name string, args ...string) (string, error) {
		*calls = append(*calls, name+" "+strings.Join(args, " "))
		return "", os.ErrNotExist
	}

	if code := h.run([]string{"vcs", "status"}); code != 2 {
		t.Fatalf("exit code = %d, want 2 (output: %s)", code, out.String())
	}
	if len(*calls) != 2 {
		t.Fatalf("Nix clients started = %d, want 2 (ergo, repo): %v", len(*calls), *calls)
	}
}

func TestTheCacheKeyMovesWithTheLock(t *testing.T) {
	root := fakeRepository(t)
	before := cacheKey(root)
	if err := os.WriteFile(filepath.Join(root, "flake.lock"), []byte("{\"a\":1}\n"), 0o644); err != nil {
		t.Fatalf("write flake.lock: %v", err)
	}
	if after := cacheKey(root); after == before {
		t.Fatal("the cache key did not move with flake.lock")
	}
}

func TestOneRepositoryHasOneCacheKey(t *testing.T) {
	root := fakeRepository(t)
	link := filepath.Join(t.TempDir(), "checkout-link")
	if err := os.Symlink(root, link); err != nil {
		t.Fatalf("symlink repository: %v", err)
	}
	if cacheKey(root) != cacheKey(link) {
		t.Fatal("two paths to the same repository produced two cache keys")
	}
}

func TestTheGcRootPointsAtThePackageNotTheBinary(t *testing.T) {
	data := t.TempDir()
	t.Setenv("XDG_DATA_HOME", data)

	// A binary inside a package is not itself a store path; the root must
	// point at the package or the collector ignores it.
	pkg := "/nix/store/00000000000000000000000000000000-ergo-0.1.0"
	if got := packagePath(pkg + "/bin/ergo"); got != pkg {
		t.Fatalf("packagePath = %q, want %q", got, pkg)
	}
	if got := packagePath("/tmp/not-a-store-path/bin/ergo"); got != "" {
		t.Fatalf("packagePath = %q, want an empty string for a path outside the store", got)
	}

	h := &host{getenv: os.Getenv}
	h.gcRoot(pkg, "ergo-launcher-testkey")
	link := filepath.Join(data, "nix", "gcroots", "auto", "ergo-launcher-testkey")
	target, err := os.Readlink(link)
	if err != nil {
		t.Fatalf("no GC root at %s: %v", link, err)
	}
	if target != pkg {
		t.Fatalf("GC root points at %q, want the package %q", target, pkg)
	}
}
