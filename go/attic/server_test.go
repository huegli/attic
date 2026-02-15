// =============================================================================
// server_test.go - Tests for Server Discovery and Launch (server.go)
// =============================================================================
//
// Tests for the utility functions in server.go: executable detection,
// home directory lookup, and socket wait/timeout behavior.
//
// Note: We don't test launchServer() or findServerExecutable() directly
// because they require an actual AtticServer binary. Instead we test
// the lower-level helpers they depend on.
//
// =============================================================================

package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// =============================================================================
// isExecutable Tests
// =============================================================================

// GO CONCEPT: Creating Temporary Files for Tests
// ------------------------------------------------
// Go's testing package provides t.TempDir() which creates a temporary
// directory that is automatically removed when the test finishes.
// For creating temp files, we use os.WriteFile which atomically creates
// a file with the given content and permissions.
//
// Unix file permissions in Go use octal literals:
//   0755 = rwxr-xr-x (user: read/write/execute, group/other: read/execute)
//   0644 = rw-r--r-- (user: read/write, group/other: read only)
//
// Compare with Python: pytest provides the `tmp_path` fixture:
//   `def test_exec(tmp_path): exe = tmp_path / "testbin"; exe.chmod(0o755)`
// Python's `tempfile.TemporaryDirectory()` is the manual equivalent.
// File permissions use the same octal notation: `os.chmod(path, 0o755)`.

// TestIsExecutableWithExecutableFile verifies that an executable file is detected.
func TestIsExecutableWithExecutableFile(t *testing.T) {
	tmpDir := t.TempDir()
	exePath := filepath.Join(tmpDir, "testbin")

	// Create a file with execute permissions (0755).
	if err := os.WriteFile(exePath, []byte("#!/bin/sh\n"), 0755); err != nil {
		t.Fatalf("failed to create test executable: %v", err)
	}

	if !isExecutable(exePath) {
		t.Error("isExecutable() should return true for an executable file")
	}
}

// TestIsExecutableWithNonExecutableFile verifies that a non-executable file
// is correctly identified.
func TestIsExecutableWithNonExecutableFile(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "readme.txt")

	// Create a file without execute permissions (0644).
	if err := os.WriteFile(filePath, []byte("hello"), 0644); err != nil {
		t.Fatalf("failed to create test file: %v", err)
	}

	if isExecutable(filePath) {
		t.Error("isExecutable() should return false for a non-executable file")
	}
}

// TestIsExecutableWithDirectory verifies that a directory is not reported
// as executable (even though directories have execute bits for traversal).
func TestIsExecutableWithDirectory(t *testing.T) {
	tmpDir := t.TempDir()

	if isExecutable(tmpDir) {
		t.Error("isExecutable() should return false for directories")
	}
}

// TestIsExecutableWithNonexistentPath verifies that a missing path returns false.
func TestIsExecutableWithNonexistentPath(t *testing.T) {
	if isExecutable("/nonexistent/path/to/binary") {
		t.Error("isExecutable() should return false for nonexistent paths")
	}
}

// TestIsExecutableWithEmptyPath verifies that an empty path returns false.
func TestIsExecutableWithEmptyPath(t *testing.T) {
	if isExecutable("") {
		t.Error("isExecutable() should return false for empty path")
	}
}

// =============================================================================
// homeDir Tests
// =============================================================================

// TestHomeDirReturnsNonEmpty verifies that homeDir returns a non-empty string.
// This test assumes the test environment has a valid HOME directory.
func TestHomeDirReturnsNonEmpty(t *testing.T) {
	home := homeDir()
	if home == "" {
		t.Error("homeDir() returned empty string")
	}
}

// TestHomeDirIsAbsolute verifies that homeDir returns an absolute path.
func TestHomeDirIsAbsolute(t *testing.T) {
	home := homeDir()
	if home == "" {
		t.Skip("homeDir() returned empty (no HOME set)")
	}

	// GO CONCEPT: t.Skip()
	// ---------------------
	// t.Skip() marks a test as skipped rather than failed. Use it when
	// a test can't run in the current environment (e.g., missing
	// dependencies, OS-specific features). Skipped tests appear in
	// verbose output but don't count as failures.
	//
	// Compare with Python: pytest uses `pytest.skip("reason")` or the
	// `@pytest.mark.skip` decorator. Conditional skipping:
	// `@pytest.mark.skipif(sys.platform != "linux", reason="Linux only")`.
	// unittest has `self.skipTest("reason")`.
	if !filepath.IsAbs(home) {
		t.Errorf("homeDir() = %q, expected absolute path", home)
	}
}

// =============================================================================
// waitForSocket Tests
// =============================================================================

// TestWaitForSocketFindsExistingSocket verifies that waitForSocket returns
// immediately when the socket file already exists.
func TestWaitForSocketFindsExistingSocket(t *testing.T) {
	// Create a temporary "socket" file (just a regular file is enough
	// since waitForSocket only checks for file existence with os.Stat).
	tmpDir := t.TempDir()

	// We need to match the expected socket path format.
	// waitForSocket uses atticprotocol.SocketPath(pid) which returns
	// /tmp/attic-<PID>.sock. Instead of fighting that, we'll test the
	// timeout behavior directly.

	// Create a file that looks like a socket at the expected path.
	fakePid := 99999
	socketPath := filepath.Join("/tmp", "attic-99999.sock")

	// Create the fake socket file.
	if err := os.WriteFile(socketPath, []byte{}, 0644); err != nil {
		t.Fatalf("failed to create fake socket: %v", err)
	}
	t.Cleanup(func() { os.Remove(socketPath) })

	// waitForSocket should find it quickly.
	start := time.Now()
	path, err := waitForSocket(fakePid)
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("waitForSocket() returned error: %v", err)
	}
	if path != socketPath {
		t.Errorf("waitForSocket() = %q, want %q", path, socketPath)
	}
	// Should be nearly instant — definitely less than 1 second.
	if elapsed > 1*time.Second {
		t.Errorf("waitForSocket() took %v, expected near-instant", elapsed)
	}

	_ = tmpDir // used for t.TempDir() lifecycle only
}

// TestWaitForSocketTimesOut verifies that waitForSocket returns an error
// when the socket doesn't appear within the timeout.
func TestWaitForSocketTimesOut(t *testing.T) {
	// Use a PID that definitely won't have a socket file.
	// PID 1 is init/systemd and won't have an Attic socket.
	_, err := waitForSocket(88888)
	if err == nil {
		// Clean up in case a file happened to exist.
		os.Remove("/tmp/attic-88888.sock")
		t.Fatal("waitForSocket() should return error for nonexistent socket")
	}

	// GO CONCEPT: strings.Contains for Error Checking
	// -------------------------------------------------
	// Go errors are just values with an Error() string method. For
	// simple checks, you can inspect the error message string. For
	// more robust checks, use errors.Is() or errors.As() with
	// sentinel errors or typed errors.
	//
	// Compare with Python: Python uses `"timeout" in str(err)` or, more
	// robustly, `isinstance(err, TimeoutError)`. pytest provides
	// `pytest.raises(TimeoutError, match="timeout")` which combines type
	// checking and message matching in one assertion.
	if got := err.Error(); !containsAny(got, "timeout", "Timeout") {
		t.Errorf("error should mention timeout, got: %v", err)
	}
}

// TestWaitForSocketTimesOutQuickly verifies the timeout happens in a
// reasonable time (close to serverSocketTimeout, not much longer).
func TestWaitForSocketTimesOutQuickly(t *testing.T) {
	start := time.Now()
	_, _ = waitForSocket(77777)
	elapsed := time.Since(start)

	// Should timeout in approximately serverSocketTimeout (4s).
	// Allow some margin for test environment variability.
	if elapsed < 3*time.Second {
		t.Errorf("waitForSocket() timed out too quickly: %v (expected ~%v)", elapsed, serverSocketTimeout)
	}
	if elapsed > 6*time.Second {
		t.Errorf("waitForSocket() took too long: %v (expected ~%v)", elapsed, serverSocketTimeout)
	}
}

// =============================================================================
// Server Constants Tests
// =============================================================================

// TestServerSocketTimeoutIsPositive ensures the timeout is a reasonable value.
func TestServerSocketTimeoutIsPositive(t *testing.T) {
	if serverSocketTimeout <= 0 {
		t.Errorf("serverSocketTimeout = %v, should be positive", serverSocketTimeout)
	}
}

// TestServerSocketPollIntervalIsPositive ensures the poll interval is set.
func TestServerSocketPollIntervalIsPositive(t *testing.T) {
	if serverSocketPollInterval <= 0 {
		t.Errorf("serverSocketPollInterval = %v, should be positive", serverSocketPollInterval)
	}
}

// TestPollIntervalLessThanTimeout ensures we poll multiple times before timeout.
func TestPollIntervalLessThanTimeout(t *testing.T) {
	if serverSocketPollInterval >= serverSocketTimeout {
		t.Errorf("poll interval (%v) should be less than timeout (%v)",
			serverSocketPollInterval, serverSocketTimeout)
	}
}

// =============================================================================
// Helpers
// =============================================================================

// containsAny checks if s contains any of the given substrings.
func containsAny(s string, substrings ...string) bool {
	for _, sub := range substrings {
		if len(s) >= len(sub) {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
		}
	}
	return false
}
