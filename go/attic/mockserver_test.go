// =============================================================================
// mockserver_test.go - Mock AtticServer for Testing
// =============================================================================
//
// GO CONCEPT: Test Helpers (Shared Test Infrastructure)
// -----------------------------------------------------
// Go test files (*_test.go) are ONLY compiled during testing. They can
// define helper types and functions used across multiple test files in the
// same package. This file provides a mock AtticServer that listens on a
// Unix socket and speaks the CLI text protocol, so we can test the CLI
// without a real emulator.
//
// This file uses "_test.go" suffix, so it's only available during tests.
// All files in the same package's test suite share the same test binary,
// so types defined here are visible to main_test.go, server_test.go, etc.
//
// Compare with Python: pytest uses `conftest.py` files for shared test
// infrastructure. Fixtures defined there are automatically available to
// all test files in the directory. This is analogous to Go's shared
// `_test.go` helpers but with automatic dependency injection.
//
// =============================================================================

package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/attic/atticprotocol"
)

// mockServer is a lightweight mock of AtticServer for testing.
//
// It listens on a Unix domain socket and responds to CLI protocol commands
// using a configurable handler function. This lets each test define exactly
// how the "server" should respond to specific commands.
//
// GO CONCEPT: struct with sync.Mutex
// -----------------------------------
// Embedding sync.Mutex in a struct gives it Lock()/Unlock() methods
// directly. We use it to protect concurrent access from multiple test
// goroutines and the server's accept loop.
//
// Compare with Python: Python uses `threading.Lock()` with context
// managers: `self.lock = threading.Lock()` and `with self.lock:` blocks.
// The `with` statement ensures the lock is released even on exception —
// similar to Go's `defer mu.Unlock()` pattern.
type mockServer struct {
	// listener is the Unix socket listener accepting client connections.
	listener net.Listener

	// socketPath is the filesystem path of the Unix socket.
	socketPath string

	// handler is called for each received command and returns the response
	// line to send back (including OK:/ERR: prefix and trailing newline).
	// If nil, the default handler responds with OK:pong to ping commands
	// and OK: to everything else.
	handler func(cmd string) string

	// mu protects concurrent access to the connections slice.
	mu sync.Mutex

	// connections tracks all active client connections for cleanup.
	connections []net.Conn

	// wg tracks all goroutines spawned by the server for clean shutdown.
	wg sync.WaitGroup
}

// GO CONCEPT: Test Helper Functions with *testing.T
// -------------------------------------------------
// Functions that accept *testing.T can call t.Helper() to mark themselves
// as test helpers. When a helper calls t.Fatal or t.Error, the error
// message points to the CALLER of the helper, not the helper itself.
// This makes test output much more readable.
//
// t.Cleanup(func) registers a function to run when the test finishes,
// whether it passed or failed. This is Go's way of doing test teardown —
// similar to Swift's addTeardownBlock() in XCTest.
//
// Compare with Python: pytest fixtures with `yield` provide setup and
// teardown: `@pytest.fixture def mock_server(): srv = start(); yield srv;
// srv.stop()`. The `request.addfinalizer()` method is equivalent to
// `t.Cleanup()`. Unlike Go, pytest fixtures are injected by name.

// startMockServer creates and starts a mock AtticServer on a temporary
// Unix socket. The server is automatically cleaned up when the test
// finishes.
//
// The handler function receives the raw command string (without CMD: prefix)
// and returns the full response line (e.g., "OK:pong\n"). If handler is nil,
// a default handler is used that responds to "ping" with "OK:pong\n" and
// everything else with "OK:\n".
func startMockServer(t *testing.T, handler func(cmd string) string) *mockServer {
	t.Helper()

	// Create a temporary directory for the socket file.
	// We use os.MkdirTemp under /tmp instead of t.TempDir() because macOS
	// has a 104-byte limit on Unix socket paths, and t.TempDir() routes
	// through /var/folders/... which, combined with long test names, can
	// exceed that limit.
	tmpDir, err := os.MkdirTemp("/tmp", "attic-test-")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	t.Cleanup(func() { os.RemoveAll(tmpDir) })
	socketPath := filepath.Join(tmpDir, "s.sock")

	// Create a Unix domain socket listener.
	// "unix" means Unix domain socket (local IPC, no network).
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("failed to create mock server socket: %v", err)
	}

	if handler == nil {
		handler = defaultMockHandler
	}

	ms := &mockServer{
		listener:   listener,
		socketPath: socketPath,
		handler:    handler,
	}

	// Start accepting connections in a background goroutine.
	ms.wg.Add(1)
	go ms.acceptLoop()

	// Register cleanup to stop the server when the test finishes.
	t.Cleanup(func() {
		ms.stop()
	})

	return ms
}

// acceptLoop runs in a goroutine, accepting and handling client connections.
func (ms *mockServer) acceptLoop() {
	defer ms.wg.Done()

	for {
		conn, err := ms.listener.Accept()
		if err != nil {
			// Listener was closed (normal shutdown) — exit the loop.
			return
		}

		ms.mu.Lock()
		ms.connections = append(ms.connections, conn)
		ms.mu.Unlock()

		// Handle each connection in its own goroutine.
		ms.wg.Add(1)
		go ms.handleConnection(conn)
	}
}

// handleConnection reads commands from a client and sends responses.
func (ms *mockServer) handleConnection(conn net.Conn) {
	defer ms.wg.Done()

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		line := scanner.Text()

		// Strip the CMD: prefix if present (protocol format: "CMD:command\n").
		cmd := strings.TrimPrefix(line, atticprotocol.CommandPrefix)

		// Call the handler to get the response.
		response := ms.handler(cmd)

		// Send the response back to the client.
		fmt.Fprint(conn, response)
	}
}

// stop gracefully shuts down the mock server.
func (ms *mockServer) stop() {
	// Close the listener first so acceptLoop exits.
	ms.listener.Close()

	// Close all active connections so handleConnection goroutines exit.
	ms.mu.Lock()
	for _, conn := range ms.connections {
		conn.Close()
	}
	ms.connections = nil
	ms.mu.Unlock()

	// Wait for all goroutines to finish.
	ms.wg.Wait()

	// Clean up the socket file if it still exists.
	os.Remove(ms.socketPath)
}

// defaultMockHandler responds to commands with sensible defaults.
// Handles ping (required for Client.Connect verification) and returns
// an empty OK for everything else.
func defaultMockHandler(cmd string) string {
	switch {
	case cmd == "ping":
		return "OK:pong\n"
	case cmd == "version":
		return "OK:Attic v0.2.0 (Mock)\n"
	case cmd == "status":
		return "OK:running PC=$E477\n"
	case cmd == "pause":
		return "OK:paused\n"
	case cmd == "resume":
		return "OK:resumed\n"
	default:
		return "OK:\n"
	}
}
