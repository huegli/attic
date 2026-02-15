// =============================================================================
// server.go - AtticServer Discovery and Launch
// =============================================================================
//
// Handles finding and launching the AtticServer process. The CLI can either
// connect to an already-running server (discovered via socket files in /tmp)
// or launch a new one as a subprocess.
//
// The server search order for the AtticServer executable:
//   1. Same directory as the CLI binary
//   2. PATH environment variable
//   3. Common locations: /usr/local/bin, /opt/homebrew/bin, ~/.local/bin
//
// When the CLI launches a server, it tracks the PID so it can send SIGTERM
// on exit. If the server was already running, the CLI just disconnects
// without stopping it.
//
// =============================================================================

package main

// GO CONCEPT: Multiple Packages from Standard Library
// ---------------------------------------------------
// Go's standard library is organized into packages by functionality.
// You can import multiple sub-packages from the same parent, like
// "os" and "os/exec" — these are separate packages, not submodules.
//
// Packages used here:
//   - "fmt"           — formatted I/O
//   - "os"            — file system operations, process info, environment
//   - "os/exec"       — running external commands (subprocess management)
//   - "path/filepath" — cross-platform file path manipulation
//   - "time"          — time operations (durations, timers, sleep)
//
// Compare with Python: Python's standard library is similarly organized:
// `import os`, `import subprocess`, `from pathlib import Path`,
// `import time`. Python sub-packages use dot notation for imports.
import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/attic/atticprotocol"
)

// GO CONCEPT: Typed Constants with time.Duration
// -----------------------------------------------
// Go's time package uses a Duration type (which is really an int64 counting
// nanoseconds). You create durations by multiplying a number with a time unit:
//   4 * time.Second       → 4 seconds (4,000,000,000 nanoseconds)
//   100 * time.Millisecond → 100 milliseconds
//
// This is type-safe: you can't accidentally mix seconds and milliseconds
// because the compiler enforces the Duration type.
//
// Compare to Swift:
//   Swift: TimeInterval is a Double (seconds), so 4.0 means 4 seconds
//   Go:    time.Duration is an int64 (nanoseconds), written as 4 * time.Second
//
// Compare with Python: Python uses `datetime.timedelta` for durations:
// `timedelta(seconds=4)`, `timedelta(milliseconds=100)`. These support
// arithmetic and comparisons. Unlike Go's nanosecond int64, Python's
// timedelta stores days, seconds, and microseconds internally.
const (
	// serverExecutableName is the name of the AtticServer binary.
	serverExecutableName = "AtticServer"

	// serverSocketTimeout is how long to wait for the server socket to appear
	// after launching the server process.
	serverSocketTimeout = 4 * time.Second

	// serverSocketPollInterval is how often to check for the server socket
	// during the startup wait.
	serverSocketPollInterval = 100 * time.Millisecond
)

// GO CONCEPT: Named Return Values
// --------------------------------
// Go allows you to name the return values in a function signature:
//   func launchServer(silent bool) (socketPath string, pid int, err error)
//
// Named returns serve as documentation — they tell callers what each
// returned value represents. They also create local variables with those
// names, pre-initialized to their zero values.
//
// You CAN use a bare "return" (no values) to return the current values of
// the named variables, but most Go developers prefer explicit returns for
// clarity. We use named returns here purely for documentation.
//
// Compare with Python: Python has no named return values. Functions
// return tuples, and callers unpack them. Type hints document the return:
//   `def launch_server(silent: bool) -> tuple[str, int, Exception | None]:`
//
// GO CONCEPT: The error Interface
// --------------------------------
// Go's error handling is based on a simple interface:
//   type error interface {
//       Error() string
//   }
//
// Any type that has an Error() string method satisfies the error interface.
// Functions return error as their last return value by convention. The
// caller checks "if err != nil" to detect failure.
//
// fmt.Errorf("message: %w", err) creates a new error that wraps another.
// The %w verb (not %v!) preserves the error chain so callers can unwrap it
// with errors.Is() or errors.As().
//
// Compare to Swift:
//   Swift: func launch() throws -> String  (uses throw/catch)
//   Go:    func launch() (string, error)    (returns error as a value)
//
// Compare with Python: Python uses an exception hierarchy:
//   `class LaunchError(Exception): pass`
// Errors are raised (`raise LaunchError("msg")`) and caught
// (`try: ... except LaunchError as e: ...`). Error chaining uses
// `raise ... from err`. Python's approach is more implicit — you don't
// check return values, but you can't see which exceptions a function
// might raise without reading its source or documentation.

// launchServer launches a new AtticServer subprocess and waits for its socket
// to become available. Returns the socket path, the server's PID, and any error.
//
// The server is launched with stdout/stderr redirected to /dev/null to avoid
// cluttering the CLI output. The --silent flag suppresses audio if requested.
func launchServer(silent bool) (socketPath string, pid int, err error) {
	// Find the AtticServer executable
	exePath, err := findServerExecutable()
	if err != nil {
		// fmt.Errorf with %w wraps the original error, preserving the chain.
		// This is like Swift's error chaining with underlying errors.
		return "", 0, fmt.Errorf("could not find %s executable: %w", serverExecutableName, err)
	}

	// GO CONCEPT: Slice Literals and append()
	// ----------------------------------------
	// []string{} creates an empty string slice (dynamic array).
	// append(slice, elem) adds an element, growing the slice if needed.
	//
	// Slices in Go are like Swift Arrays but with explicit capacity management:
	//   - make([]string, 0, 10) — length 0, capacity 10 (pre-allocated)
	//   - []string{}            — length 0, capacity 0 (grows on append)
	//   - []string{"a", "b"}   — length 2, initialized with values
	//
	// append() returns a new slice header (possibly pointing to new memory
	// if the old capacity was exceeded), so you must assign the result back.
	//
	// Compare with Python: Python lists work similarly: `cmd_args = []`,
	// `cmd_args.append("--silent")`. Python lists grow automatically.
	// Unlike Go, `append()` is a method that modifies the list in place
	// (no need to reassign the result).
	cmdArgs := []string{}
	if silent {
		cmdArgs = append(cmdArgs, "--silent")
	}

	// GO CONCEPT: Running External Commands (os/exec)
	// ------------------------------------------------
	// exec.Command creates a command but doesn't run it yet. It's similar
	// to Swift's Process class (formerly NSTask).
	//
	//   exec.Command(name, arg1, arg2) — create the command
	//   cmd.Start()                    — start it asynchronously (non-blocking)
	//   cmd.Run()                      — start AND wait for completion (blocking)
	//   cmd.Wait()                     — wait for a started command to finish
	//   cmd.Process.Pid                — get the process ID after Start()
	//
	// cmd.Stdout and cmd.Stderr control where the subprocess output goes:
	//   - nil means output is discarded (like redirecting to /dev/null)
	//   - os.Stdout would forward to our own stdout
	//   - &bytes.Buffer would capture it in memory
	//
	// Compare with Python: `subprocess.Popen(["AtticServer", "--silent"])`
	// for async launch, `subprocess.run(["AtticServer"])` for blocking.
	// `proc.pid` gives the PID. Output control: `stdout=subprocess.DEVNULL`
	// to discard, `stdout=subprocess.PIPE` to capture in memory.

	// Launch the server as a subprocess
	cmd := exec.Command(exePath, cmdArgs...)

	// Discard server output to keep CLI output clean.
	// Setting Stdout/Stderr to nil means the subprocess output goes nowhere.
	cmd.Stdout = nil
	cmd.Stderr = nil

	// Start() launches the process without waiting for it to finish.
	// This is what we want — the server runs in the background while
	// the CLI continues to set up and connect.
	if err := cmd.Start(); err != nil {
		return "", 0, fmt.Errorf("failed to launch %s: %w", serverExecutableName, err)
	}

	// After Start(), cmd.Process is populated with the running process info.
	pid = cmd.Process.Pid

	// Wait for the server socket to appear (polls the filesystem)
	socketPath, err = waitForSocket(pid)
	if err != nil {
		return "", pid, fmt.Errorf("%s started (PID: %d) but socket not found: %w", serverExecutableName, pid, err)
	}

	return socketPath, pid, nil
}

// GO CONCEPT: Multiple Return with Early Returns
// ------------------------------------------------
// Go functions commonly have multiple "return" statements for early exits.
// Each return path must provide ALL return values. This pattern replaces
// Swift's guard statements:
//
//   Swift:
//     guard let path = findExecutable() else { return nil }
//
//   Go:
//     path, err := findExecutable()
//     if err != nil { return "", err }
//
// The pattern is verbose but explicit — you always know exactly what's
// being returned on every path.
//
// Compare with Python: Python uses the same early-return pattern, but
// often with exceptions instead of error returns:
//   `path = find_executable()`
//   `if path is None: raise FileNotFoundError(...)`

// findServerExecutable searches for the AtticServer binary in standard
// locations. Returns the full path to the executable.
func findServerExecutable() (string, error) {
	// 1. Check the same directory as the CLI binary.
	// os.Executable() returns the path of the currently running binary.
	// It may return an error if the path can't be determined (rare).
	if selfPath, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(selfPath), serverExecutableName)
		if isExecutable(candidate) {
			return candidate, nil
		}
	}

	// 2. Check PATH using exec.LookPath.
	// This searches the directories listed in the PATH environment variable,
	// just like running "which AtticServer" in a shell.
	if path, err := exec.LookPath(serverExecutableName); err == nil {
		return path, nil
	}

	// 3. Check common installation locations.
	// GO CONCEPT: Composite Literals (Inline Data Structures)
	// -------------------------------------------------------
	// []string{...} is a "composite literal" — it creates a slice and
	// initializes it with values in one expression. Go uses this pattern
	// extensively instead of builder patterns or constructor overloads.
	//
	// Compare to Swift: ["a", "b", "c"] (array literal)
	//
	// Compare with Python: Python list literals are identical in concept:
	//   `common_paths = ["/usr/local/bin", "/opt/homebrew/bin",
	//    os.path.join(home, ".local", "bin")]`
	// Python also has tuple `(a, b)`, set `{a, b}`, and dict `{"key": val}`.
	commonPaths := []string{
		"/usr/local/bin",
		"/opt/homebrew/bin",
		filepath.Join(homeDir(), ".local", "bin"),
	}

	// GO CONCEPT: range Loops
	// ------------------------
	// "for _, dir := range commonPaths" iterates over the slice.
	// range returns two values: (index, value). If you don't need
	// the index, use _ (blank identifier) to discard it.
	//
	//   for i, v := range slice    — both index and value
	//   for i := range slice       — index only
	//   for _, v := range slice    — value only (discard index)
	//
	// The blank identifier _ is Go's way of saying "I don't need this
	// value." The compiler requires you to use every declared variable,
	// so _ is the escape hatch for intentionally unused values.
	//
	// Compare to Swift:
	//   for dir in commonPaths { ... }           — value only (most common)
	//   for (i, dir) in commonPaths.enumerated() — both index and value
	//
	// Compare with Python: `for dir in common_paths:` gives values directly
	// (no index). For index+value: `for i, dir in enumerate(common_paths):`.
	// The `_` convention for unused variables is the same:
	// `for _, dir in enumerate(common_paths):`.
	for _, dir := range commonPaths {
		candidate := filepath.Join(dir, serverExecutableName)
		if isExecutable(candidate) {
			return candidate, nil
		}
	}

	return "", fmt.Errorf("%s not found in PATH or common locations", serverExecutableName)
}

// waitForSocket polls for the server's Unix socket to appear after launch.
// Returns the socket path once found, or an error if the timeout is reached.
func waitForSocket(pid int) (string, error) {
	// atticprotocol.SocketPath constructs the expected path: /tmp/attic-<PID>.sock
	expectedPath := atticprotocol.SocketPath(pid)

	// time.Now().Add(duration) computes a future time point.
	// We poll in a loop until we either find the socket or hit the deadline.
	deadline := time.Now().Add(serverSocketTimeout)

	// GO CONCEPT: Time Comparisons
	// -----------------------------
	// Go's time.Time has comparison methods:
	//   t.Before(other)  — is t earlier than other?
	//   t.After(other)   — is t later than other?
	//   t.Equal(other)   — are they the same instant?
	//
	// You can't use < or > with time.Time (Go doesn't have operator
	// overloading). This is different from Swift where Date conforms to
	// Comparable and you can write "date1 < date2".
	//
	// Compare with Python: Python's `datetime` objects support comparison
	// operators directly: `now < deadline`. This is more natural than Go's
	// method-based approach. `time.sleep(0.1)` takes seconds as a float.
	for time.Now().Before(deadline) {
		// os.Stat checks if a file exists and returns its metadata.
		// If the error is nil, the file exists.
		if _, err := os.Stat(expectedPath); err == nil {
			return expectedPath, nil
		}
		// time.Sleep pauses the current goroutine for the given duration.
		// Other goroutines continue to run during the sleep.
		time.Sleep(serverSocketPollInterval)
	}

	return "", fmt.Errorf("timeout waiting for socket %s", expectedPath)
}

// GO CONCEPT: Bitwise Operations
// --------------------------------
// Go supports the same bitwise operators as C:
//   &   — AND
//   |   — OR
//   ^   — XOR
//   &^  — AND NOT (bit clear) — unique to Go
//   <<  — left shift
//   >>  — right shift
//
// Here we use & (AND) to check file permission bits. The octal literal
// 0111 represents the execute bits for user, group, and other:
//   0100 = user execute
//   0010 = group execute
//   0001 = other execute
//   0111 = any of the above
//
// If (permissions & 0111) is non-zero, at least one execute bit is set.
//
// Go uses the 0-prefix for octal literals (same as C). Go 1.13+ also
// supports 0o111 for clarity, but 0111 is still common.
//
// Compare with Python: Python uses the same bitwise operators: `&`, `|`,
// `^`, `~` (NOT), `<<`, `>>`. Go's `&^` (AND NOT) is `& ~` in Python.
// Octal literals use `0o` prefix: `0o755`, `0o111`. Python also has
// `os.access(path, os.X_OK)` as a higher-level executable check.

// isExecutable checks if a file exists and is executable.
func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	// Check that it's a regular file with at least one execute bit set.
	// info.Mode().Perm() returns the Unix permission bits (e.g., 0755).
	return !info.IsDir() && info.Mode().Perm()&0111 != 0
}

// homeDir returns the current user's home directory.
func homeDir() string {
	// os.UserHomeDir() is the cross-platform way to get the home directory.
	// On macOS/Linux it returns $HOME; on Windows it returns %USERPROFILE%.
	home, err := os.UserHomeDir()
	if err != nil {
		// Return empty string if home can't be determined.
		// filepath.Join("", ".local", "bin") will produce ".local/bin"
		// which won't match anything, so this is a safe fallback.
		return ""
	}
	return home
}
