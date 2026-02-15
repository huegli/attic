// =============================================================================
// repl.go - REPL Loop (Stub for Phase 1)
// =============================================================================
//
// This file will contain the full REPL implementation in Phase 4. For now it
// provides a minimal stub that reads lines from stdin and sends them as raw
// protocol commands, so the CLI can be tested end-to-end.
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
// Compare with Python: Python file objects are buffered by default.
// `sys.stdin` can be iterated line by line: `for line in sys.stdin:`.
// For explicit buffering, use `io.BufferedReader`. The `readline` module
// adds line editing (history, tab completion) on top of stdin.
//
// The "strings" package provides string manipulation functions. Go strings
// are immutable (like Swift), so operations return new strings rather than
// modifying in place.
import (
	"bufio"
	"fmt"
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

// GO CONCEPT: Unused Parameters
// ------------------------------
// Go requires you to use every declared variable, but function parameters
// are exempt — you can declare a parameter and not use it. This is useful
// for stub functions where you know the parameter will be needed later.
//
// Here "atasciiMode" is accepted but not yet used (full implementation
// comes in a later phase). In Swift you'd use "_ atasciiMode: Bool" to
// suppress the external label, but Go doesn't have external parameter names.
//
// Compare with Python: Python uses `_` for unused parameters by
// convention: `def run_repl(client, _atascii_mode):`. Unlike Go, Python
// never raises errors for unused variables — it's purely a linter
// concern (e.g., pylint W0613).

// runREPL runs the main REPL loop.
//
// This is a minimal stub for Phase 1. It reads lines from stdin and sends
// them as raw protocol commands. The full implementation with command
// translation, mode switching, help system, and line editing will be added
// in subsequent phases.
func runREPL(client *atticprotocol.Client, atasciiMode bool) {
	// GO CONCEPT: bufio.Scanner
	// -------------------------
	// Scanner provides a convenient interface for reading input line by line.
	//
	//   scanner := bufio.NewScanner(os.Stdin)  — create scanner from stdin
	//   scanner.Scan()                          — read next line (returns bool)
	//   scanner.Text()                          — get the line (without \n)
	//   scanner.Err()                           — check for errors after loop
	//
	// Scan() returns true if a line was read, false on EOF or error.
	// This makes it perfect for a "for scanner.Scan() { ... }" loop.
	//
	// Compare to Swift:
	//   Swift: readLine() returns String? (nil on EOF)
	//   Go:    scanner.Scan() returns bool + scanner.Text() for the string
	//
	// Compare with Python: `for line in sys.stdin:` iterates lines (keeping
	// `\n`). `input()` reads one line (stripping `\n`) and raises `EOFError`
	// on EOF. Python's `input()` is closest to Go's Scanner for REPL use.
	scanner := bufio.NewScanner(os.Stdin)
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
		// Print prompt (without newline — user types on the same line)
		fmt.Print(mode.prompt())

		// Read a line from stdin
		if !scanner.Scan() {
			// scanner.Scan() returned false, meaning EOF (Ctrl-D on Unix)
			// or an I/O error. Print a newline for clean terminal output
			// and exit the REPL.
			fmt.Println()
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
		//
		// These are standalone functions, not methods, because Go's string
		// type is a built-in primitive. You can't add methods to built-in types.
		//
		// Compare with Python: Python strings have methods directly (not
		// standalone functions): `line.strip()`, `line.startswith(".")`,
		// `line.split()`, `" ".join(parts)`, `line.upper()`, `"sub" in line`.
		// This is the opposite of Go — Python attaches methods to the str type.
		line := strings.TrimSpace(scanner.Text())
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

		// Handle local dot-commands (processed by the CLI, not sent to server)
		switch line {
		case ".quit":
			return
		case ".monitor":
			mode = ModeMonitor
			fmt.Println("Switched to Monitor mode")
			continue
		case ".basic":
			mode = ModeBasic
			fmt.Println("Switched to BASIC mode")
			continue
		case ".dos":
			mode = ModeDOS
			fmt.Println("Switched to DOS mode")
			continue
		case ".help":
			fmt.Println("Help system will be implemented in Phase 6.")
			fmt.Println("Dot-commands: .monitor .basic .dos .quit .help")
			continue
		}

		// Send as raw protocol command (no translation yet — the full
		// command translator will be implemented in Phase 3).
		//
		// SendRaw wraps the input as "CMD:<input>\n" and waits for a
		// response from the server.
		resp, err := client.SendRaw(line)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			continue
		}

		// Display response, expanding multi-line separators.
		// The protocol uses ASCII Record Separator (0x1E) to encode
		// multiple lines in a single response. We replace them with
		// actual newlines for display.
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
