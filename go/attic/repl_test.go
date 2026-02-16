// =============================================================================
// repl_test.go - Tests for REPL Loop and Mode System (repl.go)
// =============================================================================
//
// Tests for the REPL mode type, prompt rendering, and integration tests
// using the mock server defined in mockserver_test.go.
//
// The integration tests verify the full CLI protocol exchange: the REPL
// reads user input, sends it to the (mock) server over a Unix socket,
// receives the response, and writes it to stdout.
//
// =============================================================================

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/attic/atticprotocol"
)

// =============================================================================
// REPLMode Tests
// =============================================================================

// TestREPLModeValues verifies the iota-generated constants have expected values.
func TestREPLModeValues(t *testing.T) {
	// GO CONCEPT: Testing iota Values
	// --------------------------------
	// While iota values are implementation details, testing them ensures
	// we don't accidentally reorder the constants (which would break
	// any serialized state that depends on the numeric values).
	//
	// Compare with Python: Python's `IntEnum` values can be tested the same
	// way: `assert REPLMode.MONITOR == 0`. Since Python enum values are
	// explicit (or use `auto()`), accidental reordering is less of a concern.
	tests := []struct {
		mode     REPLMode
		expected int
	}{
		{ModeMonitor, 0},
		{ModeBasic, 1},
		{ModeDOS, 2},
	}

	for _, tc := range tests {
		if int(tc.mode) != tc.expected {
			t.Errorf("REPLMode(%d) should be %d", tc.mode, tc.expected)
		}
	}
}

// TestREPLModePrompts verifies each mode returns the correct prompt string.
func TestREPLModePrompts(t *testing.T) {
	tests := []struct {
		name   string
		mode   REPLMode
		prompt string
	}{
		{"monitor", ModeMonitor, "[monitor] > "},
		{"basic", ModeBasic, "[basic] > "},
		{"dos", ModeDOS, "[dos] D1:> "},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.mode.prompt()
			if got != tc.prompt {
				t.Errorf("REPLMode(%d).prompt() = %q, want %q", tc.mode, got, tc.prompt)
			}
		})
	}
}

// TestREPLModePromptDefault verifies that an unknown mode returns a fallback prompt.
func TestREPLModePromptDefault(t *testing.T) {
	unknownMode := REPLMode(99)
	got := unknownMode.prompt()
	if got != "> " {
		t.Errorf("unknown mode prompt = %q, want %q", got, "> ")
	}
}

// TestREPLModePromptsEndWithSpace verifies all prompts end with a space
// (so user input doesn't run into the prompt text).
func TestREPLModePromptsEndWithSpace(t *testing.T) {
	modes := []REPLMode{ModeMonitor, ModeBasic, ModeDOS}
	for _, mode := range modes {
		p := mode.prompt()
		if !strings.HasSuffix(p, " ") {
			t.Errorf("prompt %q for mode %d should end with a space", p, mode)
		}
	}
}

// TestREPLModePromptsContainModeName ensures each prompt identifies its mode.
func TestREPLModePromptsContainModeName(t *testing.T) {
	tests := []struct {
		mode REPLMode
		name string
	}{
		{ModeMonitor, "monitor"},
		{ModeBasic, "basic"},
		{ModeDOS, "dos"},
	}

	for _, tc := range tests {
		p := tc.mode.prompt()
		if !strings.Contains(p, tc.name) {
			t.Errorf("prompt %q should contain mode name %q", p, tc.name)
		}
	}
}

// =============================================================================
// REPL Integration Tests (with Mock Server)
// =============================================================================

// GO CONCEPT: Integration Testing with Pipes
// --------------------------------------------
// To test functions that read from os.Stdin and write to os.Stdout, we
// use os.Pipe() to create connected file descriptors. One end feeds
// input to the function under test, the other captures its output.
//
//   reader, writer, _ := os.Pipe()
//   os.Stdin = reader     // Function reads from this end
//   writer.Write(...)     // We write test input into this end
//
// This technique is also called "pipe redirection" and is common in
// Unix-style programs. It's similar to Swift's Pipe class but at the
// OS file descriptor level.
//
// Compare with Python: Python uses `io.StringIO` for in-memory streams:
// `sys.stdin = io.StringIO("input\n")`. For real pipes, use
// `subprocess.Popen(stdin=PIPE, stdout=PIPE)` or `os.pipe()`.
// `unittest.mock.patch` can redirect `sys.stdin`/`sys.stdout` cleanly.

// captureREPL runs the REPL with simulated stdin input and a mock server,
// returning everything written to stdout.
//
// GO CONCEPT: Goroutines for Concurrent Test Phases
// ---------------------------------------------------
// We need to run the REPL (which blocks reading stdin) while also feeding
// it input. Solution: run the REPL in a goroutine and feed input from the
// test goroutine. A sync.WaitGroup coordinates completion.
//
// Compare with Python: Python uses `threading.Thread` for concurrent
// test phases: `t = Thread(target=run_repl); t.start(); t.join()`.
// `concurrent.futures.ThreadPoolExecutor` is a higher-level alternative.
func captureREPL(t *testing.T, input string, handler func(cmd string) string) string {
	t.Helper()

	// Start mock server.
	ms := startMockServer(t, handler)

	// Connect a real client to the mock server.
	client := atticprotocol.NewClient()
	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("failed to connect to mock server: %v", err)
	}
	t.Cleanup(func() { client.Disconnect() })

	// Redirect stdin: create a pipe and feed the test input.
	oldStdin := os.Stdin
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdin pipe: %v", err)
	}
	os.Stdin = stdinReader
	t.Cleanup(func() { os.Stdin = oldStdin })

	// Redirect stdout: create a pipe to capture output.
	oldStdout := os.Stdout
	stdoutReader, stdoutWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdout pipe: %v", err)
	}
	os.Stdout = stdoutWriter
	t.Cleanup(func() { os.Stdout = oldStdout })

	// GO CONCEPT: sync.WaitGroup
	// ---------------------------
	// WaitGroup waits for a collection of goroutines to finish. You:
	//   1. Call wg.Add(n) before launching n goroutines
	//   2. Call wg.Done() at the end of each goroutine
	//   3. Call wg.Wait() to block until all goroutines finish
	//
	// This is the Go equivalent of Swift's DispatchGroup.
	//
	// Compare with Python: Python uses `Thread.join()` to wait for threads,
	// or `concurrent.futures.wait()` for a group. There's no direct WaitGroup
	// equivalent, but joining all threads in a loop achieves the same effect.
	var wg sync.WaitGroup
	var output string

	// Goroutine 1: Read captured stdout output.
	wg.Add(1)
	go func() {
		defer wg.Done()
		var buf strings.Builder
		scanner := bufio.NewScanner(stdoutReader)
		for scanner.Scan() {
			buf.WriteString(scanner.Text())
			buf.WriteString("\n")
		}
		output = buf.String()
	}()

	// GO CONCEPT: Creating Test Instances After Environment Setup
	// -----------------------------------------------------------
	// We create the LineEditor AFTER redirecting os.Stdin so that its
	// internal bufio.Scanner reads from the test pipe, not the real stdin.
	// The NewLineEditor constructor checks os.Stdin at creation time, so
	// order matters here.
	//
	// We force non-interactive mode by creating a LineEditor that reads
	// from piped input (the redirected os.Stdin is a pipe, not a TTY).
	// This is equivalent to how the CLI behaves when run under Emacs comint
	// or with "echo 'cmd' | attic-go".
	//
	// Compare with Swift: The Swift tests similarly configure input
	// before creating the LineEditor, since libedit checks isatty() once.
	//
	// Compare with Python: pytest fixtures handle ordering naturally:
	//   @pytest.fixture
	//   def editor(monkeypatch):
	//       monkeypatch.setattr("sys.stdin", io.StringIO("input"))
	//       return LineEditor()  # Created after stdin redirect
	editor := NewLineEditor()

	// Goroutine 2: Run the REPL (blocks until stdin EOF).
	wg.Add(1)
	go func() {
		defer wg.Done()
		runREPL(client, editor, false)
		editor.Close()
		// Close stdout writer so the reader goroutine gets EOF.
		stdoutWriter.Close()
	}()

	// Feed input and close to signal EOF.
	fmt.Fprint(stdinWriter, input)
	stdinWriter.Close()

	// Wait for REPL and output capture to complete.
	wg.Wait()
	stdoutReader.Close()

	return output
}

// TestREPLQuitCommand verifies that .quit exits the REPL.
func TestREPLQuitCommand(t *testing.T) {
	output := captureREPL(t, ".quit\n", nil)
	// The REPL should exit without error. Output should contain the prompt.
	if !strings.Contains(output, "[basic]") {
		t.Errorf("expected basic mode prompt in output, got:\n%s", output)
	}
}

// TestREPLModeSwitch verifies that mode-switching dot-commands work.
func TestREPLModeSwitch(t *testing.T) {
	input := ".monitor\n.basic\n.dos\n.quit\n"
	output := captureREPL(t, input, nil)

	checks := []string{
		"Switched to Monitor mode",
		"Switched to BASIC mode",
		"Switched to DOS mode",
	}
	for _, check := range checks {
		if !strings.Contains(output, check) {
			t.Errorf("missing %q in output:\n%s", check, output)
		}
	}
}

// TestREPLMonitorPrompt verifies the prompt changes after switching to monitor mode.
func TestREPLMonitorPrompt(t *testing.T) {
	input := ".monitor\n.quit\n"
	output := captureREPL(t, input, nil)

	if !strings.Contains(output, "[monitor]") {
		t.Errorf("expected monitor prompt in output, got:\n%s", output)
	}
}

// TestREPLDOSPrompt verifies the DOS mode prompt includes D1:.
func TestREPLDOSPrompt(t *testing.T) {
	input := ".dos\n.quit\n"
	output := captureREPL(t, input, nil)

	if !strings.Contains(output, "[dos] D1:") {
		t.Errorf("expected DOS prompt with D1: in output, got:\n%s", output)
	}
}

// TestREPLHelp verifies the .help command outputs something useful.
func TestREPLHelp(t *testing.T) {
	input := ".help\n.quit\n"
	output := captureREPL(t, input, nil)

	if !strings.Contains(output, ".monitor") || !strings.Contains(output, ".quit") {
		t.Errorf("help output should list dot-commands, got:\n%s", output)
	}
}

// TestREPLEmptyLines verifies that empty input lines are silently skipped.
func TestREPLEmptyLines(t *testing.T) {
	input := "\n\n\n.quit\n"
	output := captureREPL(t, input, nil)

	// Should see multiple prompts but no errors.
	if strings.Contains(output, "Error") {
		t.Errorf("empty lines should not cause errors, got:\n%s", output)
	}
}

// TestREPLEOFExits verifies that EOF (Ctrl-D) cleanly exits the REPL.
func TestREPLEOFExits(t *testing.T) {
	// No .quit — just send EOF by closing stdin immediately.
	output := captureREPL(t, "", nil)

	// Should exit cleanly. Output should just be the initial prompt.
	if strings.Contains(output, "Error") {
		t.Errorf("EOF should not cause errors, got:\n%s", output)
	}
}

// TestREPLSendsCommandToServer verifies that non-dot-commands are sent
// to the mock server and the response is displayed.
func TestREPLSendsCommandToServer(t *testing.T) {
	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "status":
			return "OK:running PC=$E477\n"
		default:
			return fmt.Sprintf("OK:echo %s\n", cmd)
		}
	}

	input := "status\n.quit\n"
	output := captureREPL(t, input, handler)

	if !strings.Contains(output, "running PC=$E477") {
		t.Errorf("expected server response in output, got:\n%s", output)
	}
}

// TestREPLMultiLineResponse verifies that multi-line responses (using
// the Record Separator character) are properly expanded to separate lines.
func TestREPLMultiLineResponse(t *testing.T) {
	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "disassemble":
			// Simulate a multi-line disassembly response.
			return "OK:0600: A9 00  LDA #$00\x1E0602: 8D 00 D4  STA $D400\n"
		default:
			return "OK:\n"
		}
	}

	input := "disassemble\n.quit\n"
	output := captureREPL(t, input, handler)

	if !strings.Contains(output, "LDA #$00") {
		t.Errorf("expected disassembly output, got:\n%s", output)
	}
	if !strings.Contains(output, "STA $D400") {
		t.Errorf("expected second line of disassembly, got:\n%s", output)
	}
}

// TestREPLServerErrorResponse verifies that error responses from the server
// are displayed as errors.
func TestREPLServerErrorResponse(t *testing.T) {
	// GO CONCEPT: Redirecting stderr in Tests
	// ----------------------------------------
	// Error responses are written to stderr. To capture them we redirect
	// os.Stderr the same way we redirect os.Stdout.
	//
	// Compare with Python: `contextlib.redirect_stderr(io.StringIO())` works
	// as a context manager. pytest provides `capsys` and `capfd` fixtures
	// that capture stdout/stderr automatically — no manual redirection needed.
	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "badcmd":
			return "ERR:unknown command\n"
		default:
			return "OK:\n"
		}
	}

	// Capture stderr too.
	oldStderr := os.Stderr
	stderrReader, stderrWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stderr pipe: %v", err)
	}
	os.Stderr = stderrWriter
	t.Cleanup(func() { os.Stderr = oldStderr })

	var wg sync.WaitGroup
	var stderrOutput string

	wg.Add(1)
	go func() {
		defer wg.Done()
		data, _ := io.ReadAll(stderrReader)
		stderrOutput = string(data)
	}()

	input := "badcmd\n.quit\n"
	_ = captureREPL(t, input, handler)

	stderrWriter.Close()
	wg.Wait()
	stderrReader.Close()

	if !strings.Contains(stderrOutput, "unknown command") {
		t.Errorf("expected error message on stderr, got:\n%s", stderrOutput)
	}
}

// TestREPLMultipleCommands verifies a sequence of commands are all handled.
func TestREPLMultipleCommands(t *testing.T) {
	callCount := 0
	var mu sync.Mutex

	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		default:
			mu.Lock()
			callCount++
			n := callCount
			mu.Unlock()
			return fmt.Sprintf("OK:response-%d\n", n)
		}
	}

	input := "cmd1\ncmd2\ncmd3\n.quit\n"
	output := captureREPL(t, input, handler)

	for _, expected := range []string{"response-1", "response-2", "response-3"} {
		if !strings.Contains(output, expected) {
			t.Errorf("expected %q in output, got:\n%s", expected, output)
		}
	}
}

// =============================================================================
// Client Connection with Mock Server Tests
// =============================================================================

// TestClientConnectsToMockServer verifies the atticprotocol.Client can
// connect to our mock server and exchange ping/pong.
func TestClientConnectsToMockServer(t *testing.T) {
	ms := startMockServer(t, nil)

	client := atticprotocol.NewClient()
	err := client.Connect(ms.socketPath)
	if err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}
	defer client.Disconnect()

	if !client.IsConnected() {
		t.Error("client should be connected after Connect()")
	}
}

// TestClientSendRawToMockServer verifies SendRaw works with the mock server.
func TestClientSendRawToMockServer(t *testing.T) {
	ms := startMockServer(t, func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "pause":
			return "OK:paused at $E477\n"
		default:
			return "OK:\n"
		}
	})

	client := atticprotocol.NewClient()
	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}
	defer client.Disconnect()

	resp, err := client.SendRaw("pause")
	if err != nil {
		t.Fatalf("SendRaw() failed: %v", err)
	}
	if !resp.IsOK() {
		t.Errorf("expected OK response, got error: %s", resp.Data)
	}
	if resp.Data != "paused at $E477" {
		t.Errorf("resp.Data = %q, want %q", resp.Data, "paused at $E477")
	}
}

// TestClientSendToMockServer verifies Send with typed commands.
func TestClientSendToMockServer(t *testing.T) {
	ms := startMockServer(t, func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "version":
			return "OK:Attic v0.2.0 (Mock)\n"
		default:
			return "OK:\n"
		}
	})

	client := atticprotocol.NewClient()
	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}
	defer client.Disconnect()

	resp, err := client.Send(atticprotocol.NewVersionCommand())
	if err != nil {
		t.Fatalf("Send() failed: %v", err)
	}
	if resp.Data != "Attic v0.2.0 (Mock)" {
		t.Errorf("resp.Data = %q, want %q", resp.Data, "Attic v0.2.0 (Mock)")
	}
}

// TestClientErrorResponseFromMockServer verifies error responses are parsed.
func TestClientErrorResponseFromMockServer(t *testing.T) {
	ms := startMockServer(t, func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		default:
			return "ERR:command not implemented\n"
		}
	})

	client := atticprotocol.NewClient()
	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}
	defer client.Disconnect()

	resp, err := client.SendRaw("somecmd")
	if err != nil {
		t.Fatalf("SendRaw() failed: %v", err)
	}
	if resp.IsOK() {
		t.Error("expected error response, got OK")
	}
	if resp.Data != "command not implemented" {
		t.Errorf("resp.Data = %q, want %q", resp.Data, "command not implemented")
	}
}

// TestClientDisconnect verifies clean disconnect from mock server.
func TestClientDisconnect(t *testing.T) {
	ms := startMockServer(t, nil)

	client := atticprotocol.NewClient()
	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}

	client.Disconnect()

	if client.IsConnected() {
		t.Error("client should not be connected after Disconnect()")
	}
}

// TestClientEventHandler verifies async events are delivered to the handler.
func TestClientEventHandler(t *testing.T) {
	// GO CONCEPT: Channels for Test Synchronization
	// -----------------------------------------------
	// When testing async behavior, channels are perfect for waiting
	// for an expected event without busy-polling. The test blocks on
	// channel receive until the event arrives or a timeout occurs.
	//
	// Compare with Python: `queue.Queue` is Python's channel equivalent:
	// `q.put(event)` / `event = q.get(timeout=2.0)`. For simple boolean
	// signals, `threading.Event` works: `evt.set()` / `evt.wait(timeout=2)`.
	eventReceived := make(chan atticprotocol.Event, 1)

	ms := startMockServer(t, func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "step":
			// After responding OK, send an async breakpoint event.
			return "OK:stepped\nEVENT:breakpoint $0600 A=$A9 X=$10 Y=$20 S=$FF P=$30\n"
		default:
			return "OK:\n"
		}
	})

	client := atticprotocol.NewClient()
	client.SetEventHandler(func(event atticprotocol.Event) {
		eventReceived <- event
	})

	if err := client.Connect(ms.socketPath); err != nil {
		t.Fatalf("Connect() failed: %v", err)
	}
	defer client.Disconnect()

	// Send a step command which triggers a breakpoint event.
	_, err := client.SendRaw("step")
	if err != nil {
		t.Fatalf("SendRaw() failed: %v", err)
	}

	// Wait for the event with a timeout.
	select {
	case event := <-eventReceived:
		if event.Type != atticprotocol.EventBreakpoint {
			t.Errorf("expected breakpoint event, got type %d", event.Type)
		}
		if event.Address != 0x0600 {
			t.Errorf("event.Address = $%04X, want $0600", event.Address)
		}
	case <-time.After(2 * time.Second):
		t.Error("timed out waiting for breakpoint event")
	}
}

// =============================================================================
// Phase 2/3 Integration Tests: REPL with LineEditor
// =============================================================================
//
// These tests verify the REPL's new behaviors added in Phases 2 and 3:
//   - Case-insensitive dot-command handling
//   - .shutdown command (sends shutdown to server, then exits)
//   - .help with arguments (topic-specific help)
//   - LineEditor-based input (GetLine/EOF handling)
//   - Multiple mode transitions in a single session
//

// TestREPLCaseInsensitiveDotCommands verifies that dot-commands work
// regardless of case (e.g., .QUIT, .Quit, .quit all exit).
//
// GO CONCEPT: Case-Insensitive String Matching
// -----------------------------------------------
// The REPL uses strings.ToLower() to normalize dot-commands before
// matching. This is a common pattern for user-facing CLIs where strict
// case sensitivity would be unfriendly.
//
// Compare with Swift: Swift's lowercased() method does the same:
//   if line.lowercased() == ".quit" { ... }
//
// Compare with Python: Python's lower() method:
//   if line.lower() == ".quit": ...
// Python also has casefold() for more aggressive Unicode folding
// (e.g., German "ß" → "ss"), but lower() is fine for ASCII commands.
func TestREPLCaseInsensitiveDotCommands(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		expects string
	}{
		{"uppercase quit", ".QUIT\n", "[basic]"},
		{"mixed case monitor", ".Monitor\n.quit\n", "Switched to Monitor mode"},
		{"uppercase basic", ".BASIC\n.quit\n", "Switched to BASIC mode"},
		{"mixed case dos", ".Dos\n.quit\n", "Switched to DOS mode"},
		{"uppercase help", ".HELP\n.quit\n", "Dot-commands"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			output := captureREPL(t, tc.input, nil)
			if !strings.Contains(output, tc.expects) {
				t.Errorf("expected %q in output, got:\n%s", tc.expects, output)
			}
		})
	}
}

// TestREPLShutdownCommand verifies that .shutdown sends a shutdown command
// to the server before exiting.
//
// GO CONCEPT: Verifying Side Effects in Tests
// ----------------------------------------------
// To verify that .shutdown sends a "shutdown" command to the server,
// we use a handler that records received commands. This is a common
// testing pattern: use a test double (mock) that captures interactions
// for later assertion.
//
// Compare with Swift: Swift uses XCTest expectations or mock objects
// to verify that methods were called.
//
// Compare with Python: Python uses `unittest.mock.MagicMock` to record
// calls: `mock.assert_called_with("shutdown")`. pytest-mock wraps
// this: `mocker.patch("client.send", return_value=...)`.
func TestREPLShutdownCommand(t *testing.T) {
	var mu sync.Mutex
	receivedCmds := []string{}

	handler := func(cmd string) string {
		mu.Lock()
		receivedCmds = append(receivedCmds, cmd)
		mu.Unlock()
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "shutdown":
			return "OK:shutting down\n"
		default:
			return "OK:\n"
		}
	}

	_ = captureREPL(t, ".shutdown\n", handler)

	mu.Lock()
	defer mu.Unlock()

	// Check that "shutdown" was sent to the server.
	found := false
	for _, cmd := range receivedCmds {
		if cmd == "shutdown" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected 'shutdown' command to be sent to server, got: %v", receivedCmds)
	}
}

// TestREPLHelpWithTopic verifies that .help with a topic argument produces
// topic-specific output.
func TestREPLHelpWithTopic(t *testing.T) {
	input := ".help monitor\n.quit\n"
	output := captureREPL(t, input, nil)

	if !strings.Contains(output, "monitor") {
		t.Errorf("expected topic 'monitor' in help output, got:\n%s", output)
	}
}

// TestREPLModeSwitchSequence verifies a complete sequence of mode transitions
// and that prompts change accordingly.
//
// GO CONCEPT: End-to-End Integration Testing
// --------------------------------------------
// This test exercises the full REPL lifecycle: mode switching, prompt
// rendering, command sending, and response display. It verifies that
// all components work together correctly.
//
// Compare with Swift: Swift integration tests use similar pipe-based
// approaches to feed input and capture output from the REPL.
//
// Compare with Python: pytest integration tests can use subprocess.Popen
// or mock servers to test full CLI behavior. The `click.testing.CliRunner`
// is popular for CLI integration testing.
func TestREPLModeSwitchSequence(t *testing.T) {
	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "status":
			return "OK:running PC=$E477\n"
		default:
			return "OK:\n"
		}
	}

	// Switch through all modes, send a command in each, then quit.
	input := strings.Join([]string{
		".monitor",       // Switch to monitor mode
		"status",         // Send a command in monitor mode
		".basic",         // Switch to basic mode
		".dos",           // Switch to dos mode
		".monitor",       // Back to monitor mode
		".quit",          // Exit
	}, "\n") + "\n"

	output := captureREPL(t, input, handler)

	// Verify all mode switches happened.
	expectedOutputs := []string{
		"Switched to Monitor mode",
		"running PC=$E477",
		"Switched to BASIC mode",
		"Switched to DOS mode",
	}
	for _, expected := range expectedOutputs {
		if !strings.Contains(output, expected) {
			t.Errorf("expected %q in output, got:\n%s", expected, output)
		}
	}

	// Verify prompts changed correctly.
	expectedPrompts := []string{
		"[monitor]",
		"[basic]",
		"[dos]",
	}
	for _, prompt := range expectedPrompts {
		if !strings.Contains(output, prompt) {
			t.Errorf("expected prompt %q in output, got:\n%s", prompt, output)
		}
	}
}

// TestREPLWhitespaceOnlyInput verifies that lines containing only
// whitespace are ignored (treated as empty).
func TestREPLWhitespaceOnlyInput(t *testing.T) {
	input := "   \n\t\n  \t  \n.quit\n"
	output := captureREPL(t, input, nil)

	// Should see prompts but no errors and no server commands sent.
	if strings.Contains(output, "Error") {
		t.Errorf("whitespace-only lines should not cause errors, got:\n%s", output)
	}
}

// TestREPLEOFMidSession verifies that EOF in the middle of a session
// (before .quit) cleanly exits the REPL.
//
// GO CONCEPT: EOF Handling in Line-Based Protocols
// -------------------------------------------------
// When the user presses Ctrl-D (sends EOF to stdin) or when piped input
// ends, the REPL should exit cleanly without errors. The LineEditor
// returns io.EOF, which the REPL treats as a normal exit signal.
//
// Compare with Swift: Swift's readLine() returns nil on EOF.
// Compare with Python: Python's input() raises EOFError on EOF.
func TestREPLEOFMidSession(t *testing.T) {
	// Switch modes, then EOF without .quit.
	input := ".monitor\nstatus\n"
	output := captureREPL(t, input, func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		case "status":
			return "OK:running\n"
		default:
			return "OK:\n"
		}
	})

	// Should have executed the commands before exiting on EOF.
	if !strings.Contains(output, "Switched to Monitor mode") {
		t.Errorf("expected mode switch output, got:\n%s", output)
	}
	if !strings.Contains(output, "running") {
		t.Errorf("expected status response, got:\n%s", output)
	}
	// Should not contain error messages.
	if strings.Contains(output, "Error") || strings.Contains(output, "error") {
		t.Errorf("EOF should not produce errors, got:\n%s", output)
	}
}

// TestREPLServerConnectionLoss verifies that the REPL handles server
// disconnection gracefully by showing an error and continuing.
//
// GO CONCEPT: Graceful Error Recovery in REPL Loops
// -------------------------------------------------
// When the server disconnects or a command fails, the REPL should
// display an error message and continue reading input, not crash.
// This is important for resilience — a temporary network issue
// shouldn't force the user to restart the entire CLI.
//
// Compare with Swift: Swift's REPL catches errors from sendRaw()
// and prints them, then continues the loop.
//
// Compare with Python: Python uses try/except inside the loop:
//   try: response = client.send(cmd)
//   except ConnectionError as e: print(f"Error: {e}")
func TestREPLServerConnectionLoss(t *testing.T) {
	callCount := 0

	handler := func(cmd string) string {
		switch cmd {
		case "ping":
			return "OK:pong\n"
		default:
			callCount++
			if callCount == 1 {
				return "OK:first response\n"
			}
			return "ERR:connection lost\n"
		}
	}

	input := "cmd1\ncmd2\n.quit\n"
	output := captureREPL(t, input, handler)

	// First command should succeed.
	if !strings.Contains(output, "first response") {
		t.Errorf("expected first response in output, got:\n%s", output)
	}
}

// TestREPLDotCommandsNotSentToServer verifies that dot-commands (.monitor,
// .basic, .dos, .help, .quit) are handled locally and NOT forwarded to
// the server.
func TestREPLDotCommandsNotSentToServer(t *testing.T) {
	var mu sync.Mutex
	nonPingCmds := []string{}

	handler := func(cmd string) string {
		mu.Lock()
		if cmd != "ping" {
			nonPingCmds = append(nonPingCmds, cmd)
		}
		mu.Unlock()
		return "OK:pong\n"
	}

	// All these should be handled locally.
	input := ".monitor\n.basic\n.dos\n.help\n.quit\n"
	_ = captureREPL(t, input, handler)

	mu.Lock()
	defer mu.Unlock()

	if len(nonPingCmds) > 0 {
		t.Errorf("dot-commands should not be sent to server, but got: %v", nonPingCmds)
	}
}
