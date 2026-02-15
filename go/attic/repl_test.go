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

	// Goroutine 2: Run the REPL (blocks until stdin EOF).
	wg.Add(1)
	go func() {
		defer wg.Done()
		runREPL(client, false)
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
