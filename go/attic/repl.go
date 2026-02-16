// =============================================================================
// repl.go - REPL Loop with Line Editor, Command Translation, and Assembly Mode
// =============================================================================
//
// This file implements the REPL (Read-Eval-Print Loop) for the Attic CLI.
// The REPL reads user input via the LineEditor (see lineeditor.go), processes
// local dot-commands (mode switching, help, quit), translates mode-specific
// commands into protocol format (see translate.go), and sends them to
// AtticServer via a Unix socket client.
//
// The REPL operates in three modes:
//   - Monitor: 6502 debugging (disassembly, breakpoints, memory inspection)
//   - BASIC:   BASIC program entry and execution
//   - DOS:     Disk image management
//
// Additionally, the REPL supports an interactive assembly sub-mode that is
// entered when the server responds to an "assemble $XXXX" command with
// "ASM $XXXX". In this mode, the prompt changes to "$XXXX: " and each
// line is sent as "asm input <instruction>" until the user enters a blank
// line or "." to exit.
//
// Mode switching is handled locally (no server round-trip). Protocol commands
// are sent as raw text strings via the CLI text protocol.
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
// (mode switching, help, quit), translates mode-specific commands via
// translateToProtocol (see translate.go), and sends them to the server.
// Responses are displayed with multi-line expansion (replacing Record
// Separator characters with newlines).
//
// The REPL supports an interactive assembly sub-mode: when the server
// responds with "ASM $XXXX", the prompt changes to "$XXXX: " and each
// line is sent as "asm input <instruction>" until a blank line or ".".
//
// The REPL exits on:
//   - .quit command
//   - .shutdown command (also stops the server)
//   - EOF (Ctrl-D in interactive mode, end of piped input)
//   - LineEditor read error
func runREPL(client *atticprotocol.Client, editor *LineEditor, atasciiMode bool) {
	mode := ModeBasic

	// GO CONCEPT: State Machine for Assembly Sub-Mode
	// ------------------------------------------------
	// The assembly sub-mode is a state machine embedded in the REPL loop.
	// Two boolean/integer variables track the state:
	//   - inAssemblyMode: whether we're currently in assembly mode
	//   - assemblyAddress: the next address for assembly prompt display
	//
	// When inAssemblyMode is true, the REPL:
	//   - Shows "$XXXX: " prompts instead of mode prompts
	//   - Sends "asm input <instruction>" for each line
	//   - Sends "asm end" on blank line or "." to exit
	//   - Extracts the next address from the server response
	//
	// Compare with Swift: The Swift CLI uses the same approach with
	// `var inAssemblyMode = false` and `var assemblyAddress: UInt16 = 0`.
	//
	// Compare with Python: Python would use instance variables on a
	// REPL class: `self.in_assembly_mode = False`.
	inAssemblyMode := false
	var assemblyAddress uint16

	// GO CONCEPT: Infinite Loops
	// ---------------------------
	// "for { ... }" is Go's infinite loop (equivalent to "while true").
	// We use break/return to exit the loop. Most REPLs use this pattern:
	// loop forever, reading input and processing it, until the user quits.
	//
	// Compare with Python: `while True:` is Python's infinite loop. `break`
	// and `return` exit it, just like in Go.
	for {
		// Determine the prompt based on current state.
		// In assembly mode, show the next address; otherwise show the mode.
		var prompt string
		if inAssemblyMode {
			prompt = fmt.Sprintf("$%04X: ", assemblyAddress)
		} else {
			prompt = mode.prompt()
		}

		// Read a line of input using the LineEditor.
		// In interactive mode, this provides Emacs keybindings, history
		// navigation (up/down arrows, Ctrl-R), and persistent history.
		// In non-interactive mode, it prints the prompt and reads from stdin.
		line, err := editor.GetLine(prompt)
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
				// If in assembly mode, end the session cleanly.
				if inAssemblyMode {
					_, _ = client.SendRaw("asm end")
					inAssemblyMode = false
				}
				fmt.Println()
				return
			}
			// Unexpected error — log and exit.
			fmt.Fprintf(os.Stderr, "Input error: %v\n", err)
			return
		}

		// --- Interactive Assembly Sub-Mode ---
		// When active, user input is routed to "asm input" / "asm end"
		// instead of being interpreted as normal REPL commands.
		if inAssemblyMode {
			trimmed := strings.TrimSpace(line)

			// Empty line or "." exits assembly mode.
			if trimmed == "" || trimmed == "." {
				resp, err := client.SendRaw("asm end")
				if err != nil {
					fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				} else if resp.IsOK() {
					if resp.Data != "" {
						fmt.Println(resp.Data)
					}
				} else {
					fmt.Fprintf(os.Stderr, "Error: %s\n", resp.Data)
				}
				inAssemblyMode = false
				continue
			}

			// Feed instruction to the active assembly session.
			// Response format: "formatted line\x1E$XXXX"
			// The first part is the assembled output to display.
			// The second part (after separator) is the next address.
			resp, err := client.SendRaw("asm input " + trimmed)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				continue
			}

			if resp.IsOK() {
				// Split on Record Separator to get assembled line + next address.
				parts := strings.SplitN(resp.Data, atticprotocol.MultiLineSeparator, 2)
				// Print the assembled line.
				fmt.Println(parts[0])
				// Extract next address for the prompt.
				if len(parts) > 1 {
					if addr, ok := parseHexAddress(parts[1]); ok {
						assemblyAddress = addr
					}
				}
			} else {
				// Assembly error — session stays alive, user can retry.
				fmt.Fprintf(os.Stderr, "Error: %s\n", resp.Data)
			}
			continue
		}

		// --- Normal Mode ---
		// GO CONCEPT: String Functions
		// ----------------------------
		// Go's strings package provides functions (not methods) for string
		// manipulation. Unlike Swift's "string.trimmingCharacters(in:)",
		// Go uses "strings.TrimSpace(string)".
		//
		// These are standalone functions, not methods, because Go's string
		// type is a built-in primitive. You can't add methods to built-in types.
		//
		// Compare with Python: Python strings have methods directly (not
		// standalone functions): `line.strip()`, `line.startswith(".")`,
		// `line.split()`, `line.upper()`.
		line = strings.TrimSpace(line)
		if line == "" {
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
		// Compare with Swift: Swift's switch with string patterns.
		// Compare with Python: Python 3.10+ match statement.
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
			printHelp(mode, "")
		default:
			handled = false
		}

		if handled {
			continue
		}

		// Handle .help with a topic argument.
		if strings.HasPrefix(lowerLine, ".help ") {
			topic := strings.TrimSpace(line[6:])
			printHelp(mode, topic)
			continue
		}

		// Handle other dot-commands that forward to the server.
		// These are recognized by the REPL but translated by translateToProtocol.
		if strings.HasPrefix(line, ".") {
			dotLower := strings.ToLower(line)
			isForwarded := dotLower == ".status" ||
				dotLower == ".screen" ||
				dotLower == ".reset" ||
				dotLower == ".warmstart" ||
				dotLower == ".screenshot" ||
				strings.HasPrefix(dotLower, ".screenshot ") ||
				strings.HasPrefix(dotLower, ".state ") ||
				strings.HasPrefix(dotLower, ".boot ")

			if !isForwarded {
				fmt.Fprintf(os.Stderr, "Error: Unknown command: %s\n", line)
				continue
			}
		}

		// Translate REPL command to one or more CLI protocol commands.
		// Some monitor commands (e.g. `g $addr`) expand to multiple
		// sequential protocol commands.
		cliCommands := translateToProtocol(line, mode, atasciiMode)

		// Send each command to the server in order.
		for _, cliCmd := range cliCommands {
			resp, err := client.SendRaw(cliCmd)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				continue
			}

			// Display response.
			if resp.IsOK() {
				if resp.Data == "" {
					continue
				}

				// Check if the server started an interactive assembly session.
				// Response format: "ASM $XXXX"
				if strings.HasPrefix(resp.Data, "ASM $") {
					if addr, ok := parseHexAddress(resp.Data[4:]); ok {
						inAssemblyMode = true
						assemblyAddress = addr
						continue
					}
				}

				// Handle multi-line responses.
				//
				// GO CONCEPT: Protocol Separator Handling
				// ----------------------------------------
				// The CLI text protocol uses ASCII Record Separator (0x1E)
				// to encode multiple lines in a single response. We replace
				// them with actual newlines for display.
				//
				// Compare with Swift:
				//   output.replacingOccurrences(of: "\u{1E}", with: "\n")
				//
				// Compare with Python:
				//   output.replace("\x1e", "\n")
				output := strings.ReplaceAll(resp.Data, atticprotocol.MultiLineSeparator, "\n")
				fmt.Println(output)
			} else {
				fmt.Fprintf(os.Stderr, "Error: %s\n", resp.Data)
			}
		}
	}
}
