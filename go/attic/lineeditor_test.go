// =============================================================================
// lineeditor_test.go - Tests for Line Editor (lineeditor.go)
// =============================================================================
//
// Tests for the LineEditor dual-mode input system. Since the interactive mode
// (ergochat/readline) requires a real TTY, most tests exercise the non-
// interactive path using piped stdin. The interactive path is tested
// indirectly through the readline library's own test suite, and through
// manual testing with a real terminal.
//
// GO CONCEPT: Testing I/O-Dependent Code
// ----------------------------------------
// Functions that depend on os.Stdin, os.Stdout, or terminal state are hard
// to test directly. Common strategies:
//   1. Redirect os.Stdin/os.Stdout to pipes (used here and in repl_test.go)
//   2. Accept io.Reader/io.Writer parameters (more testable but more complex)
//   3. Use dependency injection with interfaces (most flexible)
//
// We use strategy #1 because it's closest to how the code actually runs in
// production and exercises the real NewLineEditor() constructor.
//
// Compare with Swift: XCTest uses similar pipe-based testing for CLI tools.
// Swift's Process class can redirect stdin/stdout for subprocess testing.
//
// Compare with Python: pytest provides capsys/capfd fixtures for capturing
// output, and monkeypatch.setattr for redirecting sys.stdin. Python also
// has `io.StringIO` for in-memory streams that bypass the OS entirely:
//   `sys.stdin = io.StringIO("line1\nline2\n")`
// This is simpler than Go's os.Pipe approach but doesn't exercise the
// real file descriptor path.
//
// =============================================================================

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// =============================================================================
// LineEditor Construction Tests
// =============================================================================

// TestNewLineEditorNonInteractive verifies that NewLineEditor creates a
// non-interactive editor when stdin is piped (not a TTY).
//
// GO CONCEPT: Testing with Piped stdin
// --------------------------------------
// When we redirect os.Stdin to a pipe, term.IsTerminal() returns false,
// forcing NewLineEditor into non-interactive mode. This simulates the
// behavior when the CLI is invoked as "echo 'cmd' | attic-go" or from
// within Emacs comint.
//
// Compare with Swift: Swift tests check isatty(STDIN_FILENO) after
// redirecting FileHandle.standardInput. The redirect is manual and
// requires careful cleanup.
//
// Compare with Python: pytest's monkeypatch fixture makes this cleaner:
//   def test_non_interactive(monkeypatch):
//       monkeypatch.setattr("sys.stdin", io.StringIO(""))
//       editor = LineEditor()
//       assert not editor.is_interactive
func TestNewLineEditorNonInteractive(t *testing.T) {
	// Redirect stdin to a pipe (non-TTY) for the test.
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	if editor.IsInteractive() {
		t.Error("editor should be non-interactive when stdin is a pipe")
	}
}

// TestNewLineEditorWithEmacsEnv verifies that setting INSIDE_EMACS forces
// non-interactive mode even if stdin were a TTY.
//
// GO CONCEPT: Environment Variable Manipulation in Tests
// -------------------------------------------------------
// os.Setenv/os.Unsetenv modify the process environment. Like os.Args
// manipulation, this isn't thread-safe, so these tests can't use
// t.Parallel(). We restore the original value in a defer.
//
// t.Setenv() is a newer Go testing helper (Go 1.17+) that automatically
// restores the environment variable when the test completes. We use the
// manual approach here for educational clarity.
//
// Compare with Swift: ProcessInfo.processInfo.environment is read-only
// in Swift. To test environment-dependent code, you'd use dependency
// injection or setenv() from C.
//
// Compare with Python: pytest's monkeypatch fixture handles this cleanly:
//   monkeypatch.setenv("INSIDE_EMACS", "29.1")
// It automatically restores the variable. Python's os.environ dict
// can also be modified directly: `os.environ["INSIDE_EMACS"] = "29.1"`.
func TestNewLineEditorWithEmacsEnv(t *testing.T) {
	// Redirect stdin to a pipe for consistent behavior.
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	// Set INSIDE_EMACS environment variable.
	oldEmacs := os.Getenv("INSIDE_EMACS")
	os.Setenv("INSIDE_EMACS", "29.1,comint")
	defer func() {
		if oldEmacs != "" {
			os.Setenv("INSIDE_EMACS", oldEmacs)
		} else {
			os.Unsetenv("INSIDE_EMACS")
		}
	}()

	editor := NewLineEditor()
	defer editor.Close()

	if editor.IsInteractive() {
		t.Error("editor should be non-interactive when INSIDE_EMACS is set")
	}
}

// =============================================================================
// Non-Interactive GetLine Tests
// =============================================================================

// TestGetLineReadsFromPipe verifies that GetLine returns lines from piped input.
//
// GO CONCEPT: Writing to Pipes for Test Input
// ---------------------------------------------
// os.Pipe() creates a connected pair of file descriptors. We write test
// input to the writer end and read it back through the LineEditor, which
// reads from the reader end (via os.Stdin redirect).
//
// The pattern is:
//   1. Create pipe: reader, writer := os.Pipe()
//   2. Redirect stdin: os.Stdin = reader
//   3. Write input: fmt.Fprint(writer, "test\n")
//   4. Close writer: writer.Close() (signals EOF to reader)
//   5. Read through LineEditor: editor.GetLine(prompt)
//
// Compare with Swift: Swift uses FileHandle/Pipe for similar testing:
//   let pipe = Pipe()
//   pipe.fileHandleForWriting.write("test\n".data(using: .utf8)!)
//
// Compare with Python: Python makes this simpler with io.StringIO:
//   sys.stdin = io.StringIO("test\n")
//   line = editor.get_line("> ")
// No pipe management needed — io.StringIO is a pure in-memory stream.
func TestGetLineReadsFromPipe(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// Write a line to the pipe.
	fmt.Fprint(writer, "hello world\n")
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != "hello world" {
		t.Errorf("GetLine() = %q, want %q", line, "hello world")
	}
}

// TestGetLineReturnsEOFOnEmptyPipe verifies that GetLine returns io.EOF
// when piped input is exhausted (no more data to read).
func TestGetLineReturnsEOFOnEmptyPipe(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// Close the pipe immediately — no input available.
	writer.Close()

	_, err = editor.GetLine("> ")
	if err != io.EOF {
		t.Errorf("GetLine() error = %v, want io.EOF", err)
	}
}

// TestGetLineMultipleLines verifies that GetLine reads successive lines
// from piped input, one at a time.
func TestGetLineMultipleLines(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// Write multiple lines to the pipe.
	fmt.Fprint(writer, "first\nsecond\nthird\n")
	writer.Close()

	// Read them one at a time.
	expectedLines := []string{"first", "second", "third"}
	for _, expected := range expectedLines {
		line, err := editor.GetLine("> ")
		if err != nil {
			t.Fatalf("GetLine() returned error on %q: %v", expected, err)
		}
		if line != expected {
			t.Errorf("GetLine() = %q, want %q", line, expected)
		}
	}

	// Next read should return EOF.
	_, err = editor.GetLine("> ")
	if err != io.EOF {
		t.Errorf("GetLine() after exhaustion: error = %v, want io.EOF", err)
	}
}

// TestGetLineNonInteractivePromptsToStdout verifies that in non-interactive
// mode, the prompt is printed to stdout before reading input.
//
// GO CONCEPT: Capturing stdout in Tests
// ---------------------------------------
// We redirect os.Stdout to a pipe to capture what the LineEditor prints.
// This verifies that prompts are visible in piped/comint mode, which is
// essential for Emacs comint's prompt-matching regex.
//
// Compare with Swift: Swift testing captures stdout by redirecting
// FileHandle.standardOutput to a pipe.
//
// Compare with Python: pytest's capsys fixture captures stdout/stderr
// automatically: `captured = capsys.readouterr(); assert "> " in captured.out`
func TestGetLineNonInteractivePromptsToStdout(t *testing.T) {
	// Redirect stdin to a pipe with one line of input.
	oldStdin := os.Stdin
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdin pipe: %v", err)
	}
	os.Stdin = stdinReader
	defer func() {
		os.Stdin = oldStdin
		stdinReader.Close()
	}()

	// Redirect stdout to a pipe to capture prompt output.
	oldStdout := os.Stdout
	stdoutReader, stdoutWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdout pipe: %v", err)
	}
	os.Stdout = stdoutWriter
	defer func() { os.Stdout = oldStdout }()

	editor := NewLineEditor()
	defer editor.Close()

	// Write one line and close stdin.
	fmt.Fprint(stdinWriter, "test\n")
	stdinWriter.Close()

	// Read a line (this should print the prompt to stdout first).
	_, _ = editor.GetLine("[basic] > ")

	// Close stdout writer so we can read the captured output.
	stdoutWriter.Close()

	// Read what was printed to stdout.
	data, _ := io.ReadAll(stdoutReader)
	stdoutReader.Close()
	captured := string(data)

	if !strings.Contains(captured, "[basic] > ") {
		t.Errorf("expected prompt in stdout output, got: %q", captured)
	}
}

// TestGetLineEmptyLine verifies that GetLine returns empty strings for
// blank lines (just pressing Enter in piped mode).
func TestGetLineEmptyLine(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// Write an empty line (just a newline character).
	fmt.Fprint(writer, "\n")
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != "" {
		t.Errorf("GetLine() = %q, want empty string", line)
	}
}

// =============================================================================
// Close() Tests
// =============================================================================

// TestCloseIsIdempotent verifies that calling Close() multiple times doesn't
// panic or cause errors.
//
// GO CONCEPT: Idempotent Cleanup
// --------------------------------
// Functions that release resources should be safe to call multiple times.
// This is important because cleanup might be called from both a defer
// statement and a signal handler. If Close() panicked on the second call,
// the program would crash during shutdown.
//
// The pattern: check if the resource is nil before closing, then set it
// to nil after:
//   if le.rl != nil { le.rl.Close(); le.rl = nil }
//
// Compare with Swift: Swift's deinit is called exactly once by ARC, so
// idempotency isn't as critical. But shutdown() methods that might be
// called manually should still be idempotent.
//
// Compare with Python: Python's __del__() can be called multiple times
// (especially with reference cycles), so cleanup should be idempotent.
// Context managers (__exit__) are typically called once, but defensive
// code still checks: `if self._resource is not None: self._resource.close()`
func TestCloseIsIdempotent(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	editor := NewLineEditor()

	// Close multiple times — should not panic.
	editor.Close()
	editor.Close()
	editor.Close()
}

// TestCloseOnNonInteractive verifies that Close() works on a non-interactive
// editor (which has no readline instance to close).
func TestCloseOnNonInteractive(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	editor := NewLineEditor()
	if editor.IsInteractive() {
		t.Skip("test requires non-interactive mode (piped stdin)")
	}

	// Should not panic even though there's no readline instance.
	editor.Close()
}

// =============================================================================
// IsInteractive Tests
// =============================================================================

// TestIsInteractiveReturnsFalseForPipe verifies the mode detection for pipes.
func TestIsInteractiveReturnsFalseForPipe(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	if editor.IsInteractive() {
		t.Error("IsInteractive() should return false for piped stdin")
	}
}

// =============================================================================
// History Constants Tests
// =============================================================================

// TestHistoryConstants verifies the history configuration values are reasonable.
//
// GO CONCEPT: Testing Configuration Constants
// ---------------------------------------------
// Even though constants can't change at runtime, testing them serves as
// documentation and catches accidental modifications during refactoring.
// It also ensures the Go and Swift CLIs stay in sync.
//
// Compare with Swift: The Swift CLI uses the same values:
//   historyPath = "~/.attic_history"
//   historySize = 500
//
// Compare with Python: Python tests for configuration values use assertions:
//   assert HISTORY_FILE == ".attic_history"
//   assert HISTORY_SIZE == 500
func TestHistoryFileName(t *testing.T) {
	if historyFileName != ".attic_history" {
		t.Errorf("historyFileName = %q, want %q", historyFileName, ".attic_history")
	}
}

func TestHistorySize(t *testing.T) {
	if historySize != 500 {
		t.Errorf("historySize = %d, want %d", historySize, 500)
	}
}

func TestHistorySizeIsPositive(t *testing.T) {
	if historySize <= 0 {
		t.Errorf("historySize = %d, should be positive", historySize)
	}
}

// TestHistoryPathConstruction verifies that the history file path is
// correctly constructed from the home directory and filename.
func TestHistoryPathConstruction(t *testing.T) {
	home := homeDir()
	if home == "" {
		t.Skip("homeDir() returned empty (no HOME set)")
	}

	expected := filepath.Join(home, historyFileName)
	if !strings.HasSuffix(expected, ".attic_history") {
		t.Errorf("history path %q should end with .attic_history", expected)
	}
	if !filepath.IsAbs(expected) {
		t.Errorf("history path %q should be absolute", expected)
	}
}

// =============================================================================
// Non-Interactive Edge Cases
// =============================================================================

// TestGetLineWithWhitespaceOnly verifies that lines with only whitespace
// are returned as-is (the REPL handles trimming, not the LineEditor).
func TestGetLineWithWhitespaceOnly(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	fmt.Fprint(writer, "   \n")
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	// LineEditor returns the raw line; REPL is responsible for trimming.
	if line != "   " {
		t.Errorf("GetLine() = %q, want %q", line, "   ")
	}
}

// TestGetLineWithLongInput verifies that very long lines are handled correctly.
//
// GO CONCEPT: bufio.Scanner Limits
// ---------------------------------
// bufio.Scanner has a default max token size of 64KB (bufio.MaxScanTokenSize).
// Lines longer than this will cause Scan() to return false with an error.
// For a REPL, this limit is rarely hit since users don't type 64KB commands.
// But it's good to know the boundary exists.
//
// Compare with Swift: readLine() in Swift has no documented limit but
// is memory-bounded. For very long lines, you'd use a streaming reader.
//
// Compare with Python: input() reads until newline with no fixed limit
// (bounded only by available memory). sys.stdin.readline() also has
// no hardcoded limit.
func TestGetLineWithLongInput(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// Create a 1000-character line (well within bufio.Scanner limits).
	longLine := strings.Repeat("A", 1000)
	fmt.Fprintf(writer, "%s\n", longLine)
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != longLine {
		t.Errorf("GetLine() returned %d chars, want %d", len(line), len(longLine))
	}
}

// TestGetLinePreservesSpecialCharacters verifies that special characters
// (quotes, backslashes, dollar signs) pass through correctly.
func TestGetLinePreservesSpecialCharacters(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	// These characters are common in REPL commands (BASIC strings, hex addresses).
	specialInput := `10 PRINT "HELLO $WORLD"`
	fmt.Fprintf(writer, "%s\n", specialInput)
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != specialInput {
		t.Errorf("GetLine() = %q, want %q", line, specialInput)
	}
}

// =============================================================================
// NewLineEditor with Custom Scanner Tests
// =============================================================================

// TestNewLineEditorCreatesScanner verifies that a non-interactive editor
// has a scanner ready for reading.
//
// GO CONCEPT: Testing Internal State (White-Box Testing)
// -------------------------------------------------------
// Since the test is in the same package (package main), it can access
// unexported (private) struct fields like editor.scanner. This is called
// "white-box testing" — you test internal details, not just the public API.
//
// White-box tests are faster to write and more precise, but they're more
// brittle (changes to internal structure break the tests). Use them for
// testing edge cases that are hard to observe through the public API.
//
// Compare with Swift: XCTest in the same module has access to internal
// members but not private ones. @testable import removes the internal
// restriction for testing.
//
// Compare with Python: Python has no enforced access control, so all
// tests are effectively white-box. By convention, accessing _private
// members in tests is acceptable but accessing __mangled names is not.
func TestNewLineEditorCreatesScanner(t *testing.T) {
	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	defer func() {
		os.Stdin = oldStdin
		reader.Close()
		writer.Close()
	}()

	editor := NewLineEditor()
	defer editor.Close()

	if editor.scanner == nil {
		t.Error("non-interactive editor should have a scanner")
	}
	if editor.rl != nil {
		t.Error("non-interactive editor should not have a readline instance")
	}
}

// =============================================================================
// Integration: LineEditor with Multiple Prompts
// =============================================================================

// TestGetLineWithDifferentPrompts verifies that the prompt changes correctly
// across multiple GetLine calls, simulating REPL mode switching.
func TestGetLineWithDifferentPrompts(t *testing.T) {
	// Redirect stdin.
	oldStdin := os.Stdin
	stdinReader, stdinWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdin pipe: %v", err)
	}
	os.Stdin = stdinReader
	defer func() {
		os.Stdin = oldStdin
		stdinReader.Close()
	}()

	// Redirect stdout to capture prompts.
	oldStdout := os.Stdout
	stdoutReader, stdoutWriter, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create stdout pipe: %v", err)
	}
	os.Stdout = stdoutWriter
	defer func() { os.Stdout = oldStdout }()

	editor := NewLineEditor()
	defer editor.Close()

	// Write input for two reads.
	fmt.Fprint(stdinWriter, "cmd1\ncmd2\n")
	stdinWriter.Close()

	// Read with different prompts (simulating mode switch).
	_, _ = editor.GetLine("[basic] > ")
	_, _ = editor.GetLine("[monitor] > ")

	// Close stdout and read captured output.
	stdoutWriter.Close()
	data, _ := io.ReadAll(stdoutReader)
	stdoutReader.Close()
	captured := string(data)

	if !strings.Contains(captured, "[basic] > ") {
		t.Errorf("expected basic prompt in output, got: %q", captured)
	}
	if !strings.Contains(captured, "[monitor] > ") {
		t.Errorf("expected monitor prompt in output, got: %q", captured)
	}
}

// =============================================================================
// NewLineEditorForTesting Helper
// =============================================================================

// TestNewLineEditorForTestingHelper demonstrates creating a LineEditor
// for testing with programmatic input. This pattern is used throughout
// the test suite.
//
// GO CONCEPT: Test Helper Patterns
// ---------------------------------
// Go test helpers typically:
//   1. Accept *testing.T for error reporting
//   2. Call t.Helper() so failures point to the caller
//   3. Use t.Cleanup() for teardown
//   4. Return the configured object
//
// This makes tests concise: one helper call sets up everything needed.
//
// Compare with Swift: XCTest uses setUp() and addTeardownBlock() for
// similar helper patterns. Swift's version is tied to the test class.
//
// Compare with Python: pytest fixtures are the equivalent:
//   @pytest.fixture
//   def piped_editor(tmp_path):
//       # setup...
//       yield editor
//       # teardown runs automatically
// Fixtures are discovered by name and injected into test parameters.
func TestNewLineEditorForTestingHelper(t *testing.T) {
	editor, writer := newTestEditor(t)

	// Write input and close.
	fmt.Fprint(writer, "test line\n")
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != "test line" {
		t.Errorf("GetLine() = %q, want %q", line, "test line")
	}
}

// newTestEditor creates a non-interactive LineEditor with piped stdin
// for testing. It returns the editor and the write end of the pipe.
// Callers write test input to the pipe and close it to signal EOF.
//
// The editor and pipe are automatically cleaned up when the test finishes.
func newTestEditor(t *testing.T) (*LineEditor, *os.File) {
	t.Helper()

	oldStdin := os.Stdin
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("failed to create pipe: %v", err)
	}
	os.Stdin = reader
	t.Cleanup(func() {
		os.Stdin = oldStdin
		reader.Close()
	})

	editor := NewLineEditor()
	t.Cleanup(func() { editor.Close() })

	return editor, writer
}

// =============================================================================
// LineEditor with bufio.Scanner Edge Cases
// =============================================================================

// TestGetLineNoTrailingNewline verifies behavior when the pipe closes without
// a trailing newline on the last line.
//
// GO CONCEPT: bufio.Scanner and Incomplete Lines
// -----------------------------------------------
// bufio.Scanner splits on newlines by default. If the input ends without
// a trailing newline, Scanner still returns the last fragment as a token
// (Scan() returns true). This is important for piped input that might
// not end with \n.
//
// Compare with Swift: readLine() handles unterminated lines the same way,
// returning the partial line before EOF.
//
// Compare with Python: sys.stdin.readline() returns "" for EOF (not None).
// input() raises EOFError. Iteration with `for line in sys.stdin:` skips
// incomplete last lines in some contexts.
func TestGetLineNoTrailingNewline(t *testing.T) {
	editor, writer := newTestEditor(t)

	// Write without trailing newline.
	fmt.Fprint(writer, "no newline")
	writer.Close()

	line, err := editor.GetLine("> ")
	if err != nil {
		t.Fatalf("GetLine() returned error: %v", err)
	}
	if line != "no newline" {
		t.Errorf("GetLine() = %q, want %q", line, "no newline")
	}

	// Next call should return EOF.
	_, err = editor.GetLine("> ")
	if err != io.EOF {
		t.Errorf("second GetLine() error = %v, want io.EOF", err)
	}
}

// =============================================================================
// Struct Field Tests
// =============================================================================

// TestLineEditorStructFields verifies the initial state of a non-interactive
// LineEditor's fields.
func TestLineEditorStructFields(t *testing.T) {
	editor, _ := newTestEditor(t)

	// Non-interactive editor should have scanner but not readline.
	if editor.interactive {
		t.Error("piped editor should have interactive=false")
	}
	if editor.scanner == nil {
		t.Error("piped editor should have non-nil scanner")
	}
	if editor.rl != nil {
		t.Error("piped editor should have nil rl")
	}
}

// TestLineEditorScannerReadsBufio verifies the scanner is a proper
// bufio.Scanner instance wrapping stdin.
func TestLineEditorScannerReadsBufio(t *testing.T) {
	editor, writer := newTestEditor(t)

	// Verify the scanner works by reading directly from it.
	fmt.Fprint(writer, "direct read\n")
	writer.Close()

	// Use the scanner directly (white-box test).
	if !editor.scanner.Scan() {
		t.Fatal("scanner.Scan() returned false, expected line")
	}
	if got := editor.scanner.Text(); got != "direct read" {
		t.Errorf("scanner.Text() = %q, want %q", got, "direct read")
	}
}

// =============================================================================
// Prompt Format Tests (Complementing repl_test.go)
// =============================================================================

// TestAllModePromptsWorkWithGetLine verifies that each REPL mode's prompt
// is correctly passed through to GetLine in non-interactive mode.
func TestAllModePromptsWorkWithGetLine(t *testing.T) {
	modes := []struct {
		mode   REPLMode
		prompt string
	}{
		{ModeMonitor, "[monitor] > "},
		{ModeBasic, "[basic] > "},
		{ModeDOS, "[dos] D1:> "},
	}

	for _, tc := range modes {
		t.Run(tc.prompt, func(t *testing.T) {
			// Redirect stdin.
			oldStdin := os.Stdin
			stdinReader, stdinWriter, err := os.Pipe()
			if err != nil {
				t.Fatalf("failed to create pipe: %v", err)
			}
			os.Stdin = stdinReader
			defer func() {
				os.Stdin = oldStdin
				stdinReader.Close()
			}()

			// Redirect stdout to capture prompt.
			oldStdout := os.Stdout
			stdoutReader, stdoutWriter, err := os.Pipe()
			if err != nil {
				t.Fatalf("failed to create stdout pipe: %v", err)
			}
			os.Stdout = stdoutWriter
			defer func() { os.Stdout = oldStdout }()

			editor := NewLineEditor()
			defer editor.Close()

			// Write one line.
			fmt.Fprint(stdinWriter, "test\n")
			stdinWriter.Close()

			// GetLine with the mode's prompt.
			_, _ = editor.GetLine(tc.mode.prompt())

			// Read captured stdout.
			stdoutWriter.Close()
			data, _ := io.ReadAll(stdoutReader)
			stdoutReader.Close()

			if !strings.Contains(string(data), tc.prompt) {
				t.Errorf("prompt %q not found in stdout output: %q", tc.prompt, string(data))
			}
		})
	}
}

// Ensure bufio is used (it's imported in the test helpers even though
// some tests use the higher-level newTestEditor helper).
var _ = bufio.NewScanner
