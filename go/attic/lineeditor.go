// =============================================================================
// lineeditor.go - Line Editor with Dual-Mode Operation (Phase 2)
// =============================================================================
//
// This file implements a dual-mode line editor for the Attic CLI REPL.
// It detects whether the terminal is interactive (TTY) or non-interactive
// (piped input, e.g., from Emacs comint mode) and selects the appropriate
// input method:
//
//   - Interactive mode: Uses ergochat/readline for full line editing with
//     Emacs keybindings, persistent history, and history search.
//   - Non-interactive mode: Falls back to bufio.Scanner for simple line-by-
//     line reading, printing the prompt manually to stdout.
//
// The Swift CLI uses libedit (BSD editline) for line editing on macOS.
// In Go we use ergochat/readline, which is a pure-Go readline library
// forked from the popular chzyer/readline. It provides the same Emacs-
// style keybindings (Ctrl-A/E/K/W/Y, arrow keys, Ctrl-R for history
// search) without requiring CGo or system libraries.
//
// History is stored at ~/.attic_history (same as the Swift CLI) with a
// 500-entry limit and duplicate suppression, so users can switch between
// the Go and Swift CLIs and keep their history.
//
// =============================================================================

package main

// GO CONCEPT: Conditional Imports and Build Tags
// -----------------------------------------------
// Go imports are always unconditional — every imported package must be used.
// If you need platform-specific behavior, use separate files with build tags
// (e.g., //go:build linux) rather than conditional imports. Here we import
// both readline and term unconditionally because our dual-mode logic runs
// on all platforms; we just call different code paths at runtime.
//
// Compare with Swift: Swift uses #if os(macOS) / #if canImport(UIKit) for
// conditional compilation. The preprocessor includes/excludes entire code
// blocks at compile time. Go has no preprocessor — it uses file-level
// build constraints instead.
//
// Compare with Python: Python uses runtime checks: `import platform;
// if platform.system() == "Darwin": import readline`. Python's import
// system is fully dynamic — you can import modules conditionally at
// runtime. Go's imports are always resolved at compile time.
import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/ergochat/readline"
	"golang.org/x/term"
)

// GO CONCEPT: Package-Level Constants for Configuration
// -----------------------------------------------------
// Configuration values that don't change at runtime should be constants.
// Go constants are evaluated at compile time and have zero runtime cost.
// For file paths that depend on the user's home directory, we can't use
// constants (since ~ must be resolved at runtime), so we use a function.
//
// Compare with Swift: Swift uses static let on a struct/class for the same
// purpose: `static let historyFile = "~/.attic_history"`. Swift's lazy
// initialization can defer expensive computations.
//
// Compare with Python: Python uses module-level UPPER_CASE constants:
// `HISTORY_FILE = "~/.attic_history"`, `HISTORY_SIZE = 500`. These are
// evaluated when the module is first imported.
const (
	// historyFileName is the name of the history file in the user's home
	// directory. Both the Swift and Go CLIs use the same file, so history
	// is shared between them.
	historyFileName = ".attic_history"

	// historySize is the maximum number of history entries to retain.
	// Matches the Swift CLI's 500-entry limit.
	historySize = 500
)

// GO CONCEPT: Interfaces and Structural Typing
// ---------------------------------------------
// Go interfaces are satisfied implicitly — a type implements an interface
// if it has the right methods, with no "implements" keyword needed. This
// is called "structural typing" (as opposed to Swift's "nominal typing"
// where you must explicitly declare conformance).
//
// Both readline.Instance and bufio.Scanner provide ways to read input,
// but they have different APIs. Our LineEditor struct wraps both behind
// a unified GetLine()/Close() interface.
//
// Compare with Swift: Swift requires explicit protocol conformance:
//   struct LineEditor: LineEditorProtocol { ... }
// You can't accidentally satisfy a protocol — you must declare it.
//
// Compare with Python: Python uses duck typing ("if it quacks like a duck").
// No interface declaration is needed. Abstract base classes (ABCs) provide
// optional formal interfaces: `class LineEditor(ABC): @abstractmethod
// def get_line(self, prompt: str) -> str: ...`.

// LineEditor wraps line editing with dual-mode operation.
//
// In interactive mode, it uses ergochat/readline for rich line editing
// with Emacs keybindings, history file persistence, and Ctrl-R history
// search. In non-interactive mode (piped input or Emacs comint), it
// falls back to bufio.Scanner for simple line reading.
//
// GO CONCEPT: Struct Fields with Mixed Visibility
// ------------------------------------------------
// All fields here are lowercase (unexported/private), which means only
// code in this package can access them. This is Go's encapsulation —
// similar to Swift's private access level. The exported (public) methods
// GetLine() and Close() provide the API.
//
// Compare with Swift:
//   class LineEditor {
//       private let isInteractive: Bool
//       private var rl: EditLine?
//       func getLine(prompt: String) -> String?
//       func shutdown()
//   }
//
// Compare with Python: Python uses a single leading underscore (_) for
// "private" fields by convention: `self._interactive = True`. Name mangling
// (double underscore: `self.__rl`) provides stronger hiding but is rarely
// used. There's no enforced visibility — it's all convention.
type LineEditor struct {
	// interactive is true when stdin is a TTY (terminal) and false when
	// stdin is piped (e.g., from Emacs comint or echo "cmd" | attic-go).
	interactive bool

	// rl is the ergochat/readline instance used in interactive mode.
	// It provides Emacs keybindings, history, and Ctrl-R search.
	// This is nil when running in non-interactive mode.
	rl *readline.Instance

	// scanner reads lines from stdin in non-interactive mode.
	// It's nil when running in interactive mode.
	scanner *bufio.Scanner
}

// GO CONCEPT: Factory Functions (Constructors)
// ---------------------------------------------
// Go has no constructors. Instead, you write a function conventionally
// named New<Type>() that creates and returns an instance. This is called
// a "factory function." It's the idiomatic way to initialize complex
// structs that need validation or setup logic.
//
//   client := atticprotocol.NewClient()      // Factory function
//   editor := NewLineEditor()                 // Factory function
//   args   := arguments{atascii: true}        // Direct struct literal (simple cases)
//
// Factory functions can return (*Type, error) if initialization can fail,
// or just *Type if it always succeeds. Returning a pointer (*LineEditor)
// is conventional for structs with internal state that shouldn't be copied.
//
// Compare with Swift: Swift uses init() methods (initializers):
//   let editor = LineEditor()  // Calls init()
// Swift initializers can be failable (init?), throwing (init() throws),
// or convenience (convenience init). Go has just one pattern: New*().
//
// Compare with Python: Python uses __init__() for initialization:
//   editor = LineEditor()  # Calls __init__(self)
// Python's __new__() controls object creation (rarely used), while
// __init__() handles initialization. Go combines both into one factory.

// NewLineEditor creates a new LineEditor with automatic mode detection.
//
// If stdin is a TTY (terminal), it creates a readline instance with Emacs
// keybindings and persistent history. If stdin is piped (non-interactive),
// it creates a simple bufio.Scanner for line reading.
//
// The INSIDE_EMACS environment variable is also checked — when running
// under Emacs (e.g., via M-x shell or comint), we always use non-interactive
// mode because Emacs provides its own line editing.
func NewLineEditor() *LineEditor {
	// GO CONCEPT: TTY Detection
	// -------------------------
	// A TTY (teletypewriter) is an interactive terminal device. When stdin
	// is a TTY, the user is typing directly. When it's not, input is being
	// piped from another program or file.
	//
	// golang.org/x/term.IsTerminal() checks if a file descriptor is connected
	// to a terminal. We cast os.Stdin.Fd() (which returns uintptr) to int
	// because IsTerminal expects int.
	//
	// os.Getenv("INSIDE_EMACS") returns the value of the INSIDE_EMACS
	// environment variable, or "" if it's not set. Emacs sets this variable
	// in all subprocesses to indicate they're running inside Emacs.
	//
	// Compare with Swift: The Swift CLI uses isatty(STDIN_FILENO) from the
	// C library (imported via Darwin/Glibc). Go's x/term package wraps the
	// same system call in a cross-platform way.
	//
	// Compare with Python: Python uses `os.isatty(sys.stdin.fileno())` or
	// `sys.stdin.isatty()` for TTY detection. The `os.environ.get("INSIDE_EMACS")`
	// checks for the Emacs environment variable. Python's `readline` module
	// (which wraps GNU readline or libedit) also does this automatically.
	isInteractive := term.IsTerminal(int(os.Stdin.Fd())) &&
		os.Getenv("INSIDE_EMACS") == ""

	if !isInteractive {
		// Non-interactive mode: use bufio.Scanner for simple line reading.
		// The scanner reads from os.Stdin line by line. We print prompts
		// manually to stdout before each read.
		return &LineEditor{
			interactive: false,
			scanner:     bufio.NewScanner(os.Stdin),
		}
	}

	// Interactive mode: use ergochat/readline for rich line editing.
	//
	// GO CONCEPT: Struct Literals with Named Fields
	// -----------------------------------------------
	// readline.Config{...} is a struct literal. Named fields make the
	// initialization self-documenting. Fields not specified get their
	// zero values (false for bool, "" for string, 0 for int, nil for
	// pointers/slices).
	//
	// The & operator takes the address of the struct, creating a pointer.
	// This is required because readline.NewEx expects *readline.Config.
	//
	// Compare with Swift: Swift struct init with named parameters:
	//   Config(historyFile: path, historyLimit: 500)
	// Swift requires all non-defaulted parameters to be provided.
	//
	// Compare with Python: Python dataclasses and keyword arguments:
	//   Config(history_file=path, history_limit=500)
	// Python's **kwargs allows arbitrary keyword arguments; Go's struct
	// literals are strictly typed.
	historyPath := filepath.Join(homeDir(), historyFileName)

	rl, err := readline.NewFromConfig(&readline.Config{
		// HistoryFile specifies where to persist command history.
		// The file is loaded on startup and saved on shutdown.
		HistoryFile: historyPath,

		// HistoryLimit is the maximum number of history entries to keep.
		// When exceeded, the oldest entries are removed.
		HistoryLimit: historySize,

		// DisableAutoSaveHistory prevents readline from saving to the
		// history file after every line. We call SaveToHistory() manually
		// for non-empty lines and let readline persist the file on Close().
		// This gives us control over what goes into history (we skip
		// empty lines) and matches the Swift CLI's behavior.
		DisableAutoSaveHistory: true,

		// Prompt will be set dynamically before each read via SetPrompt().
		// We leave it empty here since it changes with REPL mode.
		Prompt: "",
	})

	if err != nil {
		// If readline initialization fails (rare — could happen if the
		// terminal doesn't support certain capabilities), fall back to
		// non-interactive mode. This is a graceful degradation strategy.
		fmt.Fprintf(os.Stderr, "Warning: readline init failed (%v), using basic input\n", err)
		return &LineEditor{
			interactive: false,
			scanner:     bufio.NewScanner(os.Stdin),
		}
	}

	return &LineEditor{
		interactive: true,
		rl:          rl,
	}
}

// GO CONCEPT: Methods with Pointer Receivers
// -------------------------------------------
// (le *LineEditor) is a "pointer receiver" — the method receives a pointer
// to the LineEditor, not a copy. This is important for two reasons:
//   1. It avoids copying the struct on each method call (performance).
//   2. It allows the method to modify the struct's fields if needed.
//
// Convention: if ANY method on a type uses a pointer receiver, ALL methods
// should use pointer receivers for consistency. Since Close() modifies state,
// all LineEditor methods use *LineEditor.
//
// Compare with Swift: Swift methods on classes always operate on the
// reference (class instances are reference types). For structs, you'd
// use "mutating func" to modify self.
//
// Compare with Python: Python methods always receive `self`, which is
// a reference to the instance. There's no value vs pointer distinction.

// GetLine reads a line of input from the user with the given prompt.
//
// In interactive mode, the prompt is displayed by readline with full
// line editing support. In non-interactive mode, the prompt is printed
// to stdout and input is read from stdin via bufio.Scanner.
//
// Returns the input line (without trailing newline) and nil error on
// success. Returns ("", io.EOF) when the user presses Ctrl-D (EOF)
// or when piped input is exhausted. Returns ("", err) on other errors.
//
// GO CONCEPT: Sentinel Errors
// ---------------------------
// io.EOF is a "sentinel error" — a predefined error value used as a
// signal rather than indicating a real failure. It means "end of input"
// and is used throughout Go's I/O libraries.
//
// Sentinel errors are compared with == (not errors.Is) because they are
// unique package-level variables:
//   if err == io.EOF { /* end of input */ }
//
// Common sentinel errors:
//   io.EOF           — end of file/stream
//   io.ErrClosedPipe — write to closed pipe
//   os.ErrNotExist   — file not found
//   sql.ErrNoRows    — query returned no rows
//
// Compare with Swift: Swift uses enum cases or nil returns for EOF:
//   readLine() returns String? (nil on EOF)
// Go uses explicit error returns, which makes error handling more visible.
//
// Compare with Python: Python raises EOFError for end-of-input:
//   try: line = input(prompt)
//   except EOFError: break
// Python's exception approach is implicit — you discover EOFError by
// reading docs or hitting it at runtime. Go's explicit error return
// makes the EOF case visible in the function signature.
func (le *LineEditor) GetLine(prompt string) (string, error) {
	if le.interactive {
		return le.getInteractiveLine(prompt)
	}
	return le.getNonInteractiveLine(prompt)
}

// getInteractiveLine reads a line using ergochat/readline with full
// line editing, history navigation, and Ctrl-R search.
func (le *LineEditor) getInteractiveLine(prompt string) (string, error) {
	// SetPrompt updates the prompt displayed before the cursor.
	// This is called before every read because the prompt changes
	// based on REPL mode (monitor/basic/dos) and assembly state.
	le.rl.SetPrompt(prompt)

	// Readline() blocks until the user presses Enter (returns the line)
	// or Ctrl-D (returns io.EOF). It handles all line editing internally:
	// cursor movement, history recall, kill/yank ring, etc.
	line, err := le.rl.Readline()
	if err != nil {
		// readline returns io.EOF on Ctrl-D (end of input).
		// It can also return readline.ErrInterrupt on Ctrl-C.
		// We treat both as EOF to exit the REPL cleanly.
		//
		// GO CONCEPT: Type Assertion for Error Handling
		// -----------------------------------------------
		// We check err == io.EOF or err == readline.ErrInterrupt.
		// For more complex error hierarchies, you'd use errors.Is():
		//   if errors.Is(err, io.EOF) { ... }
		// errors.Is() unwraps wrapped errors (created with fmt.Errorf %w).
		// Direct == comparison works for sentinel errors like io.EOF.
		if err == readline.ErrInterrupt {
			return "", io.EOF
		}
		return "", err
	}

	// Save the line to history if it's non-empty.
	// Empty lines (just pressing Enter) aren't worth remembering.
	trimmed := strings.TrimSpace(line)
	if trimmed != "" {
		le.rl.SaveToHistory(trimmed)
	}

	return line, nil
}

// getNonInteractiveLine reads a line using bufio.Scanner for piped input.
// The prompt is printed manually to stdout since there's no readline to
// display it.
func (le *LineEditor) getNonInteractiveLine(prompt string) (string, error) {
	// Print the prompt to stdout. In non-interactive mode, the prompt is
	// still important for Emacs comint mode, which uses regex matching on
	// the prompt to determine where user input begins.
	fmt.Print(prompt)

	// Scanner.Scan() returns true if a line was read, false on EOF or error.
	if !le.scanner.Scan() {
		// Check for a read error (as opposed to clean EOF).
		if err := le.scanner.Err(); err != nil {
			return "", err
		}
		return "", io.EOF
	}

	return le.scanner.Text(), nil
}

// Close releases resources held by the LineEditor.
//
// In interactive mode, this saves the command history to disk and closes
// the readline instance. In non-interactive mode, this is a no-op.
//
// Close is safe to call multiple times (idempotent). After Close(), further
// calls to GetLine will fail.
//
// GO CONCEPT: Resource Cleanup and Idempotency
// ---------------------------------------------
// Go doesn't have destructors (like C++ ~ClassName()) or deinit (Swift).
// Resource cleanup must be done explicitly via Close() methods. The caller
// is responsible for calling Close() — typically using defer:
//
//   editor := NewLineEditor()
//   defer editor.Close()
//   // ... use editor ...
//
// "Idempotent" means calling Close() multiple times is safe. We achieve
// this by checking if the resource (le.rl) is nil before closing it,
// then setting it to nil after. This prevents panics from double-close.
//
// Compare with Swift: Swift uses deinit for automatic cleanup when the
// last reference is released (ARC — Automatic Reference Counting).
// Go uses garbage collection, which handles memory but NOT resources
// like files, sockets, or history files. Hence explicit Close().
//
// Compare with Python: Python uses __del__() (unreliable, called by GC)
// or context managers (`with` statement) for deterministic cleanup:
//   with LineEditor() as editor:
//       editor.get_line(prompt)
//   # __exit__() called automatically, even on exception
// Python's context manager protocol (__enter__/__exit__) is the closest
// equivalent to Go's defer+Close() pattern.
func (le *LineEditor) Close() {
	if le.rl != nil {
		le.rl.Close()
		le.rl = nil
	}
}

// IsInteractive returns whether the line editor is running in interactive
// (TTY) mode with full line editing, or non-interactive (piped) mode with
// basic line reading.
//
// This is useful for the REPL to decide whether to print extra formatting
// (like the welcome banner) that only makes sense in a terminal.
func (le *LineEditor) IsInteractive() bool {
	return le.interactive
}
