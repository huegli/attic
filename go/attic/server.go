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

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/attic/atticprotocol"
)

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

// launchServer launches a new AtticServer subprocess and waits for its socket
// to become available. Returns the socket path, the server's PID, and any error.
//
// The server is launched with stdout/stderr redirected to /dev/null to avoid
// cluttering the CLI output. The --silent flag suppresses audio if requested.
func launchServer(silent bool) (socketPath string, pid int, err error) {
	// Find the AtticServer executable
	exePath, err := findServerExecutable()
	if err != nil {
		return "", 0, fmt.Errorf("could not find %s executable: %w", serverExecutableName, err)
	}

	// Build command arguments
	cmdArgs := []string{}
	if silent {
		cmdArgs = append(cmdArgs, "--silent")
	}

	// Launch the server as a subprocess
	cmd := exec.Command(exePath, cmdArgs...)

	// Redirect server output to /dev/null to keep CLI output clean
	cmd.Stdout = nil
	cmd.Stderr = nil

	// Start the server process
	if err := cmd.Start(); err != nil {
		return "", 0, fmt.Errorf("failed to launch %s: %w", serverExecutableName, err)
	}

	pid = cmd.Process.Pid

	// Wait for the server socket to appear
	socketPath, err = waitForSocket(pid)
	if err != nil {
		return "", pid, fmt.Errorf("%s started (PID: %d) but socket not found: %w", serverExecutableName, pid, err)
	}

	return socketPath, pid, nil
}

// findServerExecutable searches for the AtticServer binary in standard
// locations. Returns the full path to the executable.
func findServerExecutable() (string, error) {
	// 1. Check the same directory as the CLI binary
	if selfPath, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(selfPath), serverExecutableName)
		if isExecutable(candidate) {
			return candidate, nil
		}
	}

	// 2. Check PATH
	if path, err := exec.LookPath(serverExecutableName); err == nil {
		return path, nil
	}

	// 3. Check common locations
	commonPaths := []string{
		"/usr/local/bin",
		"/opt/homebrew/bin",
		filepath.Join(homeDir(), ".local", "bin"),
	}
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
	expectedPath := atticprotocol.SocketPath(pid)
	deadline := time.Now().Add(serverSocketTimeout)

	for time.Now().Before(deadline) {
		if _, err := os.Stat(expectedPath); err == nil {
			return expectedPath, nil
		}
		time.Sleep(serverSocketPollInterval)
	}

	return "", fmt.Errorf("timeout waiting for socket %s", expectedPath)
}

// isExecutable checks if a file exists and is executable.
func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	// Check that it's a regular file with at least one execute bit set
	return !info.IsDir() && info.Mode().Perm()&0111 != 0
}

// homeDir returns the current user's home directory.
func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return home
}
