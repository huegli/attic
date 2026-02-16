// =============================================================================
// repl.go - REPL Loop with Line Editor Integration
// =============================================================================
//
// This file implements the REPL (Read-Eval-Print Loop) for the Attic CLI.
// The REPL reads user input via the LineEditor (see lineeditor.go), processes
// local dot-commands (mode switching, help, quit), and sends protocol commands
// to the AtticServer via a Unix socket client.
//
// The REPL operates in three modes:
//   - Monitor: 6502 debugging (disassembly, breakpoints, memory inspection)
//   - BASIC:   BASIC program entry and execution
//   - DOS:     Disk image management
//
// Mode switching is handled locally (no server round-trip). Protocol commands
// are sent as raw text strings via the CLI text protocol.
//
// Phase 2 integration: The REPL now uses LineEditor for input, providing
// Emacs keybindings, persistent history, and Ctrl-R search in interactive
// mode, and clean line reading for piped/comint input.
//
// =============================================================================

package main

// GO CONCEPT: Buffered I/O (bufio package)
// -----------------------------------------
// Go's "bufio" package provides buffered readers and scanners for efficient
// I/O. Raw os.Stdin reads one byte at a time (expensive system calls);
// bufio wraps it with an internal buffer for better performance.
//
// Two common approaches:
//   bufio.NewReader(os.Stdin) — low-level, gives you ReadString('\n'), etc.
//   bufio.NewScanner(os.Stdin) — higher-level, iterates lines with Scan()
//
// Scanner is simpler for line-by-line reading (which is what a REPL needs),
// while Reader is better when you need more control.
//
// In this file, we no longer use bufio directly for REPL input — that's
// been moved to the LineEditor (lineeditor.go). But the concept is still
// relevant for understanding the non-interactive fallback path.
//
// Compare with Python: Python file objects are buffered by default.
// `sys.stdin` can be iterated line by line: `for line in sys.stdin:`.
// For explicit buffering, use `io.BufferedReader`. The `readline` module
// adds line editing (history, tab completion) on top of stdin.
//
// The "strings" package provides string manipulation functions. Go strings
// are immutable (like Swift), so operations return new strings rather than
// modifying in place.
import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/attic/atticprotocol"
)

// GO CONCEPT: Custom Types (Type Definitions)
// --------------------------------------------
// "type REPLMode int" creates a NEW named type based on int. This is NOT
// just a type alias — REPLMode and int are different types and can't be
// mixed without explicit conversion.
//
// This is Go's way of creating enums: define a named type, then use
// iota-based constants for the values. It's more manual than Swift enums
// (no associated values, no pattern matching) but gets the job done.
//
// Compare to Swift:
//   enum REPLMode: String { case monitor, basic, dos }
//
// Go's approach:
//   type REPLMode int
//   const ( ModeMonitor REPLMode = iota; ModeBasic; ModeDOS )
//
// Compare with Python: Python uses `enum.IntEnum` for integer enums:
//   `class REPLMode(IntEnum): MONITOR = 0; BASIC = 1; DOS = 2`
// Python enums are full classes with rich features: iteration, names,
// and pattern matching support.

// REPLMode represents the current operating mode of the REPL.
type REPLMode int

// GO CONCEPT: iota — Auto-Incrementing Constants
// ------------------------------------------------
// "iota" is Go's constant generator. Inside a const block, iota starts
// at 0 and increments by 1 for each constant. It resets to 0 in each
// new const block.
//
//   const (
//       ModeMonitor REPLMode = iota  // 0
//       ModeBasic                     // 1 (type and iota+1 carried forward)
//       ModeDOS                       // 2
//   )
//
// The type "REPLMode" and the expression "iota" carry forward to
// subsequent lines that omit them. This is a special Go shorthand for
// const blocks.
//
// You can also do arithmetic with iota:
//   const ( KB = 1 << (10 * (iota + 1)); MB; GB; TB )
//   // KB=1024, MB=1048576, GB=1073741824, TB=1099511627776
//
// Compare to Swift: Swift enums auto-assign raw values similarly:
//   enum Mode: Int { case monitor = 0, basic, dos }
//
// Compare with Python: Python's `enum.auto()` serves the same purpose:
//   `class REPLMode(IntEnum): MONITOR = auto(); BASIC = auto()`
// Values start at 1 by default (not 0), but you can override with a
// custom `_generate_next_value_` method.
const (
	// ModeMonitor is the 6502 debugging mode.
	ModeMonitor REPLMode = iota
	// ModeBasic is the BASIC programming mode.
	ModeBasic
	// ModeDOS is the disk management mode.
	ModeDOS
)

// GO CONCEPT: Methods on Custom Types
// -------------------------------------
// Go doesn't have classes, but you can define methods on ANY named type
// (not just structs). The syntax uses a "receiver" before the function name:
//
//   func (m REPLMode) prompt() string { ... }
//         ^^^^^^^^^^^
//         This is the "receiver" — it's like "self" in Swift.
//
// The receiver binds the method to the type. You call it as:
//   mode := ModeBasic
//   mode.prompt()  // returns "[basic] > "
//
// Receivers can be value receivers (m REPLMode) or pointer receivers
// (m *REPLMode):
//   - Value receiver: gets a COPY of the value (can't modify the original)
//   - Pointer receiver: gets a reference (can modify the original)
//
// Use a value receiver when the method only reads the value (like here).
// Use a pointer receiver when the method needs to modify the value.
//
// Compare to Swift:
//   Swift methods are always implicitly called on "self":
//     func prompt() -> String { switch self { ... } }
//   Go requires you to name the receiver explicitly:
//     func (m REPLMode) prompt() string { switch m { ... } }
//
// Compare with Python: Python methods always take `self` as the first
// parameter (like Go's receiver, but always named `self`):
//   `def prompt(self) -> str: ...`
// Python allows adding methods to any class, including subclasses of
// built-in types.

// prompt returns the display prompt for the current REPL mode.
func (m REPLMode) prompt() string {
	switch m {
	case ModeMonitor:
		return "[monitor] > "
	case ModeBasic:
		return "[basic] > "
	case ModeDOS:
		return "[dos] D1:> "
	default:
		return "> "
	}
}

// GO CONCEPT: Dependency Injection
// ---------------------------------
// runREPL accepts a *LineEditor as a parameter rather than creating one
// internally. This is "dependency injection" — the caller (main.go) creates
// the LineEditor and passes it in. Benefits:
//
//   1. Testability: Tests can pass a mock or test-configured LineEditor.
//   2. Lifetime control: The caller manages creation and cleanup (Close).
//   3. Flexibility: The same REPL code works with different input sources.
//
// This is the same pattern used in the Swift CLI, where the LineEditor
// is created in the main entry point and passed to runSocketREPL().
//
// Compare with Swift: Swift uses initializer injection or property injection:
//   func runSocketREPL(lineEditor: LineEditor, client: CLISocketClient)
//
// Compare with Python: Python uses constructor injection:
//   def run_repl(editor: LineEditor, client: Client) -> None: ...
// Python also supports dependency injection frameworks like `inject` or
// `dependency-injector`, but simple parameter passing is most common.

// runREPL runs the main REPL loop.
//
// It reads user input via the LineEditor, processes local dot-commands
// (mode switching, help, quit), and sends everything else to the server
// as raw protocol commands. Responses are displayed with multi-line
// expansion (replacing Record Separator characters with newlines).
//
// The REPL exits on:
//   - .quit command
//   - .shutdown command (also stops the server)
//   - EOF (Ctrl-D in interactive mode, end of piped input)
//   - LineEditor read error
func runREPL(client *atticprotocol.Client, editor *LineEditor, atasciiMode bool) {
	mode := ModeBasic

	// GO CONCEPT: Infinite Loops
	// ---------------------------
	// "for { ... }" is Go's infinite loop (equivalent to "while true").
	// We use break/return to exit the loop. Most REPLs use this pattern:
	// loop forever, reading input and processing it, until the user quits.
	//
	// Compare with Python: `while True:` is Python's infinite loop. `break`
	// and `return` exit it, just like in Go.
	for {
		// Read a line of input using the LineEditor.
		// In interactive mode, this provides Emacs keybindings, history
		// navigation (up/down arrows, Ctrl-R), and persistent history.
		// In non-interactive mode, it prints the prompt and reads from stdin.
		line, err := editor.GetLine(mode.prompt())
		if err != nil {
			// GO CONCEPT: Comparing Errors with ==
			// --------------------------------------
			// io.EOF is a sentinel error value. We compare with == because
			// it's a unique package-level variable, not a wrapped error.
			// For wrapped errors (created with fmt.Errorf %w), use
			// errors.Is(err, target) instead.
			//
			// Compare with Swift: Swift checks for EOF via nil return:
			//   guard let line = readLine() else { break }
			//
			// Compare with Python: Python catches EOFError:
			//   try: line = input(prompt)
			//   except EOFError: break
			if err == io.EOF {
				// Clean EOF — user pressed Ctrl-D or piped input ended.
				fmt.Println()
				return
			}
			// Unexpected error — log and exit.
			fmt.Fprintf(os.Stderr, "Input error: %v\n", err)
			return
		}

		// GO CONCEPT: String Functions
		// ----------------------------
		// Go's strings package provides functions (not methods) for string
		// manipulation. Unlike Swift's "string.trimmingCharacters(in:)",
		// Go uses "strings.TrimSpace(string)".
		//
		// Common string functions:
		//   strings.TrimSpace(s)         — remove leading/trailing whitespace
		//   strings.HasPrefix(s, prefix) — check if s starts with prefix
		//   strings.Split(s, sep)        — split into []string
		//   strings.Join(parts, sep)     — join []string into one string
		//   strings.ReplaceAll(s, old, new) — replace all occurrences
		//   strings.ToUpper(s)           — uppercase
		//   strings.Contains(s, substr)  — check if s contains substr
		//   strings.ToLower(s)           — lowercase
		//
		// These are standalone functions, not methods, because Go's string
		// type is a built-in primitive. You can't add methods to built-in types.
		//
		// Compare with Python: Python strings have methods directly (not
		// standalone functions): `line.strip()`, `line.startswith(".")`,
		// `line.split()`, `" ".join(parts)`, `line.upper()`, `"sub" in line`.
		// This is the opposite of Go — Python attaches methods to the str type.
		line = strings.TrimSpace(line)
		if line == "" {
			// GO CONCEPT: continue and break
			// --------------------------------
			// "continue" skips to the next iteration of the enclosing loop.
			// "break" exits the enclosing loop entirely.
			// "return" exits the entire function.
			//
			// Same semantics as Swift's continue/break/return.
			//
			// Compare with Python: Identical keywords and semantics: `continue`,
			// `break`, `return`. Python also has `else` clauses on loops
			// (`for...else`, `while...else`) that run when the loop completes
			// without `break` — a feature neither Go nor Swift has.
			continue
		}

		// GO CONCEPT: String Case Conversion for Commands
		// ------------------------------------------------
		// strings.ToLower() converts a string to lowercase. We use this
		// to handle dot-commands case-insensitively — ".Quit", ".QUIT",
		// and ".quit" all work the same way. This matches the user-friendly
		// behavior of the Swift CLI.
		//
		// Compare with Swift: Swift's lowercased() method:
		//   switch line.lowercased() { case ".quit": ... }
		//
		// Compare with Python: Python's lower() method:
		//   match line.lower(): case ".quit": ...
		// Python also has casefold() for more aggressive Unicode lowering.
		lowerLine := strings.ToLower(line)

		// Handle local dot-commands (processed by the CLI, not sent to server).
		//
		// GO CONCEPT: Switch on Computed Values
		// --------------------------------------
		// Go's switch can match on any comparable type — here we switch on
		// a lowercase string. Unlike C, Go switch cases don't fall through
		// by default (no break needed). The "continue" at the end of each
		// case skips the server-send logic below and returns to the top of
		// the REPL loop.
		//
		// Compare with Swift: Swift's switch with string patterns:
		//   switch line.lowercased() {
		//       case ".quit": return
		//       case ".monitor": mode = .monitor
		//   }
		//
		// Compare with Python: Python 3.10+ match statement:
		//   match line.lower():
		//       case ".quit": return
		//       case ".monitor": mode = Mode.MONITOR
		handled := true
		switch lowerLine {
		case ".quit":
			return
		case ".shutdown":
			// .shutdown tells the server to stop, then exits the CLI.
			_, _ = client.SendRaw("shutdown")
			return
		case ".monitor":
			mode = ModeMonitor
			fmt.Println("Switched to Monitor mode")
		case ".basic":
			mode = ModeBasic
			fmt.Println("Switched to BASIC mode")
		case ".dos":
			mode = ModeDOS
			fmt.Println("Switched to DOS mode")
		case ".help":
			fmt.Println("Help system will be implemented in Phase 6.")
			fmt.Println("Dot-commands: .monitor .basic .dos .quit .shutdown .help")
		default:
			handled = false
		}

		if handled {
			continue
		}

		// GO CONCEPT: strings.HasPrefix for Command Routing
		// -------------------------------------------------
		// HasPrefix checks if a string starts with a given prefix. It's
		// the Go equivalent of Swift's hasPrefix(_:) method. We use it
		// here to detect dot-commands that take arguments (like ".help topic"),
		// which can't be matched with a simple equality check.
		//
		// Compare with Swift: `line.hasPrefix(".help ")` — method on String.
		// Compare with Python: `line.startswith(".help ")` — method on str.
		if strings.HasPrefix(lowerLine, ".help ") {
			// Help with topic — extract the topic after ".help "
			topic := strings.TrimSpace(line[6:])
			fmt.Printf("Help for %q will be implemented in Phase 6.\n", topic)
			continue
		}

		// Send as raw protocol command (no translation yet — the full
		// command translator will be implemented in Phase 5).
		//
		// SendRaw wraps the input as "CMD:<input>\n" and waits for a
		// response from the server.
		resp, err := client.SendRaw(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}

		// Display response, expanding multi-line separators.
		//
		// GO CONCEPT: Protocol Separator Handling
		// ----------------------------------------
		// The CLI text protocol uses ASCII Record Separator (0x1E, \x1E)
		// to encode multiple lines in a single response. We replace them
		// with actual newlines for display. This avoids the complexity of
		// a streaming protocol while still supporting multi-line output
		// like disassembly listings and memory dumps.
		//
		// Compare with Swift: Swift uses the same approach:
		//   output.replacingOccurrences(of: "\u{1E}", with: "\n")
		//
		// Compare with Python: Python string replacement:
		//   output.replace("\x1e", "\n")
		if resp.IsOK() {
			if resp.Data != "" {
				output := strings.ReplaceAll(resp.Data, atticprotocol.MultiLineSeparator, "\n")
				fmt.Println(output)
			}
		} else {
			fmt.Fprintf(os.Stderr, "Error: %s\n", resp.Data)
		}
	}
}
