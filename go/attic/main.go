// =============================================================================
// main.go - Attic CLI Entry Point (Go Port)
// =============================================================================
//
// This is the main entry point for the Go port of the Attic command-line
// interface. The CLI is a pure protocol client that connects to AtticServer
// via a Unix domain socket using the frozen CLI text protocol. It provides a
// REPL (Read-Eval-Print Loop) for interacting with the Atari 800 XL emulator
// from the terminal or Emacs comint mode.
//
// Usage:
//
//	attic-go                          Connect to running AtticServer (or launch one)
//	attic-go --silent                 Launch without audio
//	attic-go --socket /tmp/attic.sock Connect to specific socket
//	attic-go --help                   Show help
//
// The CLI supports three modes:
//   - Monitor: 6502 debugging (disassembly, breakpoints, memory inspection)
//   - BASIC:   Program entry and execution
//   - DOS:     Disk image management
//
// For Emacs integration, use M-x atari800-run after loading atari800.el.
//
// =============================================================================

// GO CONCEPT: Packages
// --------------------
// Every Go source file starts with a "package" declaration. All files in
// the same directory must use the same package name. The special package
// name "main" tells the Go compiler this is an executable program (not a
// library). A "main" package must contain a func main() as the entry point.
//
// Compare to Swift: Swift uses @main on a struct or top-level code in
// main.swift. Go always uses package main + func main().
//
// Compare with Python: Python uses `if __name__ == "__main__":` as the
// entry point. Any .py file can be both a script and a module. There's
// no package-name requirement for executables.
package main

// GO CONCEPT: Imports
// -------------------
// The import block lists packages this file depends on. Go has a rich
// standard library (everything without a domain prefix) and a module
// system for external packages (with domain prefixes like "github.com/...").
//
// Standard library packages used here:
//   - "fmt"     — formatted I/O (like Swift's print(), String(format:))
//   - "os"      — operating system functions (args, exit, files, env)
//   - "os/signal" — OS signal handling (SIGINT, SIGTERM)
//   - "syscall" — low-level OS primitives (signal constants, process ops)
//
// External packages:
//   - "github.com/attic/atticprotocol" — our CLI protocol client library
//
// Go enforces that every import is used. If you import "fmt" but never
// call fmt.Println, the code won't compile. This keeps imports clean.
//
// Compare to Swift: similar to "import Foundation" or "import AtticCore",
// but Go is stricter about unused imports.
//
// Compare with Python: Python's `import os`, `from os import path` is
// similar. Python doesn't enforce unused imports at the language level,
// though linters like flake8 flag them. Python also has no automatic
// import formatting built into the compiler.
import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/attic/atticprotocol"
)

// =============================================================================
// Version Information
// =============================================================================

// GO CONCEPT: Constants
// ---------------------
// Go's "const" declares compile-time constants. They can be grouped in a
// block with parentheses. Unlike Swift's "let" (which can hold any value
// computed at runtime), Go constants must be determinable at compile time
// and are limited to basic types: strings, numbers, and booleans.
//
// Constants are untyped by default — the string "0.2.0" is just a string
// constant, not specifically a string variable. This gives Go constants
// more flexibility when used in expressions.
//
// Naming convention: Go uses camelCase for private (unexported) names and
// PascalCase for public (exported) names. Since these constants start with
// lowercase letters, they are private to this package.
//
// Compare with Python: Python has no `const` keyword. By convention,
// constants use UPPER_CASE (e.g., `VERSION = "0.2.0"`), but nothing
// prevents reassignment. `typing.Final` provides type-checker enforcement
// (`VERSION: Final = "0.2.0"`) but is not enforced at runtime.
const (
	// version is the current version of the Go CLI, kept in sync with the
	// Swift AtticCore.version which is the single source of truth.
	version = "0.2.0"

	// appName is the application name.
	appName = "Attic"

	// copyright is the copyright notice.
	copyright = "Copyright (c) 2026"
)

// GO CONCEPT: Functions
// ---------------------
// Functions are declared with "func". The return type comes AFTER the
// parameter list (opposite of C/Java/Swift). If a function returns nothing,
// you simply omit the return type.
//
// Syntax: func name(param1 type1, param2 type2) returnType { ... }
//
// Compare to Swift:
//   Swift: func fullTitle() -> String { return "\(appName) v\(version)" }
//   Go:    func fullTitle() string    { return fmt.Sprintf(...) }
//
// Note: Go has no string interpolation like Swift's "\(variable)". Instead
// you use fmt.Sprintf() with format verbs like %s (string), %d (integer),
// %v (default format for any value).
//
// Compare with Python:
//   Python: def full_title() -> str: return f"{APP_NAME} v{VERSION}"
// Python uses `def`, return type annotations are optional (PEP 484),
// and f-strings provide string interpolation similar to Swift's \().

// fullTitle returns the application name with version.
func fullTitle() string {
	return fmt.Sprintf("%s v%s (Go)", appName, version)
}

// GO CONCEPT: Raw String Literals
// --------------------------------
// Go has two kinds of string literals:
//   - Interpreted: "hello\nworld"  (processes escape sequences like \n, \t)
//   - Raw:         `hello\nworld`  (backticks, everything is literal)
//
// Raw strings are perfect for multi-line text — the backtick preserves
// newlines, tabs, and backslashes exactly as written. This is similar to
// Swift's multi-line strings (triple quotes """) but uses backticks instead.
//
// You can embed %s format verbs in raw strings and use them with Sprintf.
//
// Compare with Python: Python has triple-quoted strings (`"""..."""`)
// for multi-line text and raw strings (`r"..."`) that don't process
// escapes. For formatted multi-line text, use triple-quoted f-strings:
// `f"""Hello {name}"""`.

// welcomeBanner returns the banner displayed when the REPL starts.
func welcomeBanner() string {
	return fmt.Sprintf(`%s - Atari 800 XL Emulator
%s

Type '.help' for available commands.
Type '.quit' to exit.
`, fullTitle(), copyright)
}

// =============================================================================
// Command-Line Arguments
// =============================================================================

// GO CONCEPT: Structs
// -------------------
// Go structs are the primary way to group related data, similar to Swift
// structs. However, Go structs are simpler:
//   - No initializers (constructors) — you use struct literals or factory
//     functions
//   - No computed properties — use methods or plain functions instead
//   - No inheritance — Go uses composition and interfaces instead
//   - Fields are public if capitalized, private if lowercase
//
// Compare with Python: Python uses `@dataclass` for data-holding classes:
//   @dataclass
//   class Arguments:
//       silent: bool = False
//       socket_path: str = ""
// Named tuples (`NamedTuple`) are another option for immutable data.
// Python has no built-in visibility enforcement — `_private` prefix is
// convention only.
//
// Compare to Swift:
//
//   Swift:
//     struct Arguments {
//         var silent: Bool = false
//         var socketPath: String?
//     }
//
//   Go:
//     type arguments struct {
//         silent     bool
//         socketPath string   // empty string "" acts as "nil" / "none"
//     }
//
// GO CONCEPT: Zero Values
// -----------------------
// In Go, every type has a "zero value" — the default when no value is
// assigned. This eliminates the need for Swift-style optionals in many
// cases:
//   - bool    → false
//   - int     → 0
//   - string  → "" (empty string)
//   - pointer → nil
//   - slice   → nil (but behaves like empty slice)
//
// So instead of Swift's "var socketPath: String?" (optional), we use
// "socketPath string" and check for "" (empty) to mean "not set".
//
// Compare with Python: Python uses `None` as the universal "no value"
// sentinel, with `Optional[str]` type hints. There are no automatic
// zero values — uninitialized variables cause `NameError`. Default
// arguments serve a similar purpose: `def __init__(self, path: str | None = None)`.

// arguments holds the parsed command-line arguments.
type arguments struct {
	// silent disables audio output when launching the server.
	silent bool

	// socketPath is the path to an existing server socket to connect to.
	// If empty (""), the CLI will discover or launch a server automatically.
	// In Swift this would be String? (optional); in Go we use the zero value
	// (empty string) to mean "not specified".
	socketPath string

	// atascii enables rich ATASCII rendering in program listings.
	// When true, ANSI escape codes are used for inverse video and ATASCII
	// graphics characters are mapped to Unicode equivalents.
	// Defaults to true for accurate visual representation in terminals.
	atascii bool

	// showHelp causes usage information to be printed and the program to exit.
	showHelp bool

	// showVersion causes version information to be printed and the program to exit.
	showVersion bool
}

// GO CONCEPT: Slices and Slice Operations
// ----------------------------------------
// Go's "slice" is the primary dynamic array type. It's a view into an
// underlying array, with a length and capacity.
//
//   os.Args         — a []string (slice of strings) containing command-line args
//   os.Args[1:]     — a new slice starting from index 1 (skips program name)
//   remaining[0]    — first element
//   remaining[1:]   — everything after the first element
//
// Compare to Swift:
//   Swift: CommandLine.arguments.dropFirst()
//   Go:    os.Args[1:]
//
// len(slice) gives the length. Slices are passed by reference (the slice
// header is copied but it points to the same underlying array).
//
// Compare with Python: Python lists have nearly identical slicing:
// `sys.argv[1:]` skips the program name, `remaining[0]` gets the first
// element. `len(my_list)` gives the length. Python lists are always
// passed by reference (the list object is shared).
//
// GO CONCEPT: Variable Declaration Styles
// ----------------------------------------
// Go has several ways to declare variables:
//
//   var x int            — explicit type, zero-initialized (x = 0)
//   var x int = 42       — explicit type with initial value
//   var x = 42           — type inferred from value (int)
//   x := 42              — short declaration (type inferred, most common)
//
// The := operator is "short variable declaration" — it declares AND
// assigns in one step. It can only be used inside functions (not at
// package level). It's the most common way to declare local variables.
//
// Compare to Swift:
//   Swift: let x = 42    (immutable) or var x = 42 (mutable)
//   Go:    x := 42       (always mutable — Go has no "let" equivalent)
//
// Compare with Python: Python needs no declarations — just assign:
// `x = 42`. Variables are always mutable. For type hints: `x: int = 42`.
// Python has no short-declaration operator; every assignment uses `=`.

// parseArguments parses command-line arguments.
//
// This is a simple hand-written parser matching the Swift CLI's behavior.
// There are only 6 flags and no subcommands, so a framework like cobra
// would be over-engineering.
func parseArguments() arguments {
	// Create an arguments struct with atascii defaulting to true.
	// This is a "struct literal" — you can name specific fields and all
	// others get their zero values (false for bool, "" for string).
	args := arguments{
		atascii: true, // Default: rich ATASCII rendering enabled
	}

	// os.Args is a []string (slice of strings) with all command-line arguments.
	// os.Args[0] is the program name, so [1:] skips it.
	remaining := os.Args[1:]

	// GO CONCEPT: For Loops
	// ---------------------
	// Go has only ONE loop keyword: "for". It replaces while, do-while,
	// and traditional for loops from other languages.
	//
	//   for i := 0; i < 10; i++ { }  — traditional C-style for
	//   for condition { }             — while loop
	//   for { }                       — infinite loop (while true)
	//   for i, v := range slice { }   — iterate over collection
	//
	// Here we use "for len(remaining) > 0" as a while loop, consuming
	// arguments one at a time from the front of the slice.
	//
	// Compare with Python: Python uses `for x in iterable:` (like Go's
	// range) and `while condition:`. There's no C-style for loop.
	// `while remaining:` is the Python equivalent of `for len(remaining) > 0`.
	for len(remaining) > 0 {
		arg := remaining[0]
		remaining = remaining[1:]

		// GO CONCEPT: Switch Statements
		// ------------------------------
		// Go's switch is cleaner than C's: no "break" needed (cases don't
		// fall through by default). You can match multiple values in one
		// case with commas. If you DO want fallthrough, use the explicit
		// "fallthrough" keyword.
		//
		// Compare to Swift: very similar behavior (no implicit fallthrough).
		//
		// Compare with Python: Python 3.10+ has `match`/`case` (structural
		// pattern matching): `match arg: case "--silent": ...`. Earlier Python
		// uses `if`/`elif` chains. Multiple values: `case "--help" | "-h":`.
		switch arg {
		case "--silent":
			args.silent = true

		case "--atascii":
			args.atascii = true

		case "--plain":
			args.atascii = false

		case "--socket":
			if len(remaining) == 0 {
				printError("--socket requires a path argument")
				os.Exit(1)
			}
			args.socketPath = remaining[0]
			remaining = remaining[1:]

		// Multiple values in one case — equivalent to Swift's "case "--help", "-h":"
		case "--help", "-h":
			args.showHelp = true

		case "--version", "-v":
			args.showVersion = true

		default:
			printError(fmt.Sprintf("Unknown argument: %s", arg))
			printUsage()
			os.Exit(1)
		}
	}

	return args
}

// =============================================================================
// Help and Usage
// =============================================================================

// printUsage prints usage information to stdout.
func printUsage() {
	// Using a raw string literal (backticks) for the multi-line help text.
	// fmt.Print (no "ln") prints without adding a trailing newline — the
	// raw string already includes one at the end.
	fmt.Print(`USAGE: attic-go [options]

OPTIONS:
  --silent            Disable audio output
  --plain             Plain ASCII rendering (no ANSI codes or Unicode)
  --socket <path>     Connect to existing server at specific socket path
  --help, -h          Show this help
  --version, -v       Show version

DISPLAY:
  By default, program listings use ANSI escape codes for inverse video
  characters and Unicode glyphs for ATASCII graphics. Use --plain for
  clean ASCII output compatible with text files and simple terminals.

EXAMPLES:
  attic-go                                Launch server and connect REPL
  attic-go --plain                        Use plain ASCII rendering
  attic-go --socket /tmp/attic-1234.sock  Connect to existing server

MODES:
  The REPL operates in three modes. Switch with dot-commands:
    .monitor    6502 debugging (disassembly, breakpoints, stepping)
    .basic      BASIC program entry and execution
    .dos        Disk image management

For Emacs integration, load emacs/atari800.el and use M-x atari800-run.
`)
}

// printVersion prints version information to stdout.
func printVersion() {
	// fmt.Println adds a trailing newline; fmt.Print does not.
	fmt.Println(fullTitle())
}

// GO CONCEPT: Writing to stderr
// ------------------------------
// Go's fmt.Fprintf takes an io.Writer as first argument, letting you
// write to any destination. os.Stderr is the standard error stream.
//
// Compare to Swift:
//   Swift: FileHandle.standardError.write("Error: \(msg)\n".data(using: .utf8)!)
//   Go:    fmt.Fprintf(os.Stderr, "Error: %s\n", msg)
//
// Compare with Python: `print(f"Error: {msg}", file=sys.stderr)`.
// Python's print() takes a `file` keyword argument. You can also use
// `sys.stderr.write(f"Error: {msg}\n")`.

// printError prints an error message to stderr.
func printError(message string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", message)
}

// =============================================================================
// Server Discovery and Connection
// =============================================================================

// GO CONCEPT: Multiple Return Values
// ------------------------------------
// Go functions can return multiple values. This is one of Go's most
// distinctive features and is used extensively for error handling.
//
// Common patterns:
//   value, err := someFunction()     — returns a result + error
//   value, ok := someMap[key]        — returns value + existence boolean
//
// Compare to Swift:
//   Swift uses Result<T, Error>, throws, or tuples for similar patterns.
//   Go's approach is simpler but more verbose — you check "if err != nil"
//   after every call that might fail.
//
// Compare with Python: Python returns tuples for multiple values:
// `def launch() -> tuple[str, int, Exception | None]:`. Callers unpack:
// `path, pid, err = launch()`. But Python's idiomatic approach uses
// exceptions (`try`/`except`) instead of returning errors.
//
// GO CONCEPT: Pointers
// --------------------
// Go has pointers, but they're much simpler than C pointers:
//   - No pointer arithmetic (can't do ptr++ or ptr[5])
//   - Garbage collected (no need to free memory)
//   - &value gets the address of a value (creates a pointer)
//   - *pointer dereferences (gets the value at the address)
//   - *Type in a type declaration means "pointer to Type"
//
// The return type *atticprotocol.Client means "a pointer to a Client".
// We use a pointer because Client is a large struct with internal state
// (connection, mutexes), so we want to share one instance rather than
// copying it.
//
// Compare to Swift: Swift classes are reference types (always passed by
// reference), so there's no need for explicit pointers. Go structs are
// value types by default, so you use pointers when you need reference
// semantics.
//
// Compare with Python: Python has no pointers — all objects are accessed
// by reference. Mutable objects (lists, dicts, class instances) are
// always shared, never copied. There's no need to choose between value
// and reference semantics.

// discoverOrConnect discovers an existing AtticServer socket, or launches a
// new server if none is found. Returns the connected client and the PID of
// the launched server (0 if we connected to an existing server).
func discoverOrConnect(args arguments) (*atticprotocol.Client, int) {
	// NewClient() is a factory function (Go convention instead of constructors).
	// It returns a *Client (pointer to Client).
	client := atticprotocol.NewClient()

	// GO CONCEPT: var vs :=
	// ----------------------
	// "var socketPath string" declares a variable with its zero value ("").
	// We use "var" here instead of ":=" because we don't have an initial
	// value to assign — we'll set it in one of the if/else branches below.
	//
	// Compare with Python: Python doesn't distinguish declaration from
	// assignment. Just write `socket_path = ""` or leave it unassigned until
	// the if/else block. Variables come into existence on first assignment.
	var socketPath string
	var launchedPid int

	if args.socketPath != "" {
		// User specified a socket path explicitly
		socketPath = args.socketPath
	} else {
		// Try to discover an existing server
		socketPath = atticprotocol.DiscoverSocket()
	}

	// If no socket found, launch a new server
	if socketPath == "" {
		fmt.Println("No running AtticServer found. Launching...")

		// GO CONCEPT: Error Handling with Multiple Returns
		// -------------------------------------------------
		// launchServer returns three values: (socketPath, pid, error).
		// The idiomatic pattern is to check "if err != nil" immediately.
		//
		// We use "var err error" here because socketPath and launchedPid are
		// already declared above. Using ":=" would create NEW local variables
		// that shadow the outer ones. But we can use ":=" for err since it's
		// new in this scope, and plain "=" for the others... EXCEPT Go's
		// short declaration ":=" requires at least one new variable on the
		// left side. So we declare err with "var" first to use "=" for all.
		//
		// Compare with Python: Python uses try/except instead of error returns:
		//   try:
		//       path, pid = launch_server(silent)
		//   except LaunchError as e:
		//       print_error(str(e)); sys.exit(1)
		// This is more concise but hides the error path in a separate block.
		var err error
		socketPath, launchedPid, err = launchServer(args.silent)
		if err != nil {
			// %v is the "default format" verb — it prints any value in a
			// human-readable way. For errors, it calls the Error() method.
			printError(fmt.Sprintf("Failed to start AtticServer: %v", err))
			printError("You can start it manually with: AtticServer")
			os.Exit(1)
		}
		fmt.Printf("AtticServer started (PID: %d)\n", launchedPid)
	}

	// GO CONCEPT: Short Variable Scoping in if
	// ------------------------------------------
	// Go allows a short statement before the condition in "if":
	//   if err := doSomething(); err != nil { ... }
	//
	// The variable "err" is scoped to the if/else block only. This is a
	// very common pattern for error handling — declare the error, check it,
	// and handle it all in one statement. The variable doesn't leak into
	// the surrounding scope.
	//
	// Compare to Swift:
	//   if let error = try? doSomething() { ... }  (not quite the same)
	//   guard let result = ... else { ... }         (more similar in spirit)
	//
	// Compare with Python: Python 3.8+ has the walrus operator (`:=`) for
	// assignment expressions: `if (err := do_something()) is not None:`.
	// However, the variable leaks into the surrounding scope — Python has
	// no block scoping for if/while statements.

	// Connect to the socket
	fmt.Printf("Connecting to %s...\n", socketPath)
	if err := client.Connect(socketPath); err != nil {
		printError(fmt.Sprintf("Failed to connect to AtticServer: %v", err))
		os.Exit(1)
	}

	return client, launchedPid
}

// =============================================================================
// Signal Handling
// =============================================================================

// GO CONCEPT: Channels and Goroutines
// ------------------------------------
// Channels and goroutines are Go's core concurrency primitives. They're
// what makes Go unique compared to most other languages.
//
// GOROUTINE: A goroutine is a lightweight thread managed by the Go runtime.
// You start one with the "go" keyword before a function call:
//   go myFunction()          — runs myFunction concurrently
//   go func() { ... }()     — runs an anonymous function concurrently
//
// Goroutines are extremely cheap (a few KB of stack each) compared to OS
// threads (typically 1-8 MB each). You can easily run thousands of them.
//
// CHANNEL: A channel is a typed communication pipe between goroutines.
// Think of it as a thread-safe queue.
//   ch := make(chan int)      — create an unbuffered channel of ints
//   ch := make(chan int, 5)   — create a buffered channel (capacity 5)
//   ch <- value               — send a value into the channel (blocks if full)
//   value := <-ch             — receive a value from the channel (blocks if empty)
//
// Compare to Swift:
//   Swift uses async/await and actors for concurrency.
//   Go uses goroutines (lightweight threads) and channels (message passing).
//   Both avoid manual thread management, but the mental models differ:
//   - Swift: "await" suspends the current task until a result is ready
//   - Go: goroutines run independently, channels synchronize them
//
// Compare with Python: Python has `threading.Thread` (OS threads,
// limited by GIL), `multiprocessing.Process` (separate processes), and
// `asyncio` (cooperative coroutines with async/await). `queue.Queue` is
// Python's closest equivalent to Go channels for thread communication.
//
// GO CONCEPT: Function Values (First-Class Functions)
// ---------------------------------------------------
// In Go, functions are first-class values — you can assign them to
// variables, pass them as arguments, and return them from other functions.
//
// The parameter "cleanup func()" means: "a function that takes no
// arguments and returns nothing". This is similar to Swift closures:
//   Swift: func setupSignalHandler(cleanup: @escaping () -> Void)
//   Go:    func setupSignalHandler(cleanup func())
//
// Compare with Python: Python functions are first-class too:
//   `def setup_signal_handler(cleanup: Callable[[], None]):`
// Python also has `lambda` for inline functions:
//   `cleanup = lambda: client.disconnect()`

// setupSignalHandler installs handlers for SIGINT and SIGTERM so the CLI can
// clean up (save history, disconnect, optionally stop the server) on exit.
func setupSignalHandler(cleanup func()) {
	// make(chan os.Signal, 1) creates a buffered channel with capacity 1.
	// The buffer size of 1 is important: signal.Notify requires a buffered
	// channel so the signal delivery doesn't block if we're not ready to
	// receive it yet.
	sigCh := make(chan os.Signal, 1)

	// signal.Notify tells the Go runtime to send SIGINT and SIGTERM signals
	// to our channel instead of using the default behavior (which would
	// kill the process immediately).
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// "go func() { ... }()" launches an anonymous goroutine.
	// This goroutine will block on "<-sigCh" (waiting to receive from the
	// channel) until a signal arrives. It runs concurrently with the rest
	// of the program.
	//
	// The trailing "()" is important — it immediately CALLS the anonymous
	// function. "go func() { ... }" without "()" would be a syntax error.
	go func() {
		<-sigCh       // Block until a signal is received (the value is discarded)
		fmt.Println() // Print a newline after ^C for clean terminal output
		cleanup()     // Run the cleanup function passed by the caller
		os.Exit(0)
	}()
}

// =============================================================================
// Main
// =============================================================================

// GO CONCEPT: The main() Function
// --------------------------------
// Every Go executable must have a func main() in package main. This is the
// program's entry point — Go calls it automatically when the program starts.
//
// Unlike Swift's @main struct (which can be async), Go's main() is always
// synchronous. For async operations, you launch goroutines from main() and
// use channels or sync primitives to coordinate.
//
// When main() returns, the entire program exits — even if other goroutines
// are still running. This is different from many languages where background
// threads keep the process alive.
//
// Compare with Python: Python uses `if __name__ == "__main__": main()`
// as the entry point convention. Unlike Go, Python doesn't exit when the
// main function returns if non-daemon threads are still running. Python's
// `atexit` module provides cleanup hooks similar to Go's deferred cleanup.

func main() {
	// Parse arguments
	args := parseArguments()

	// Handle --help
	if args.showHelp {
		printUsage()
		return // Returning from main() exits the program with code 0
	}

	// Handle --version
	if args.showVersion {
		printVersion()
		return
	}

	// Discover or launch server, then connect
	client, launchedPid := discoverOrConnect(args)

	// GO CONCEPT: Closures (Anonymous Functions with Captured Variables)
	// ------------------------------------------------------------------
	// Go supports closures — anonymous functions that capture variables
	// from their surrounding scope. The function literal below captures
	// "event" from its parameter, plus it has access to any variables
	// in the enclosing scope.
	//
	// This is identical in concept to Swift closures:
	//   Swift: client.setEventHandler { event in ... }
	//   Go:    client.SetEventHandler(func(event atticprotocol.Event) { ... })
	//
	// Note the naming convention: Go uses PascalCase for exported
	// (public) methods: SetEventHandler, not setEventHandler.
	//
	// Compare with Python: Python closures work the same way:
	//   `client.set_event_handler(lambda event: print(event))`
	// Python's `lambda` is limited to single expressions; for multi-line
	// closures, define a nested function: `def handler(event): ...`.

	// Set up event handler for async events (breakpoints, stops, errors)
	client.SetEventHandler(func(event atticprotocol.Event) {
		// This closure runs in the client's reader goroutine (a background
		// goroutine). It prints async events to stdout as they arrive.
		switch event.Type {
		case atticprotocol.EventBreakpoint:
			fmt.Printf("\n*** Breakpoint at $%04X  A=$%02X X=$%02X Y=$%02X S=$%02X P=$%02X\n",
				event.Address, event.A, event.X, event.Y, event.S, event.P)
		case atticprotocol.EventStopped:
			fmt.Printf("\n*** Stopped at $%04X\n", event.Address)
		case atticprotocol.EventError:
			fmt.Printf("\n*** Error: %s\n", event.Message)
		}
	})

	// Set up disconnect handler
	client.SetDisconnectHandler(func(err error) {
		fmt.Fprintf(os.Stderr, "\nDisconnected from AtticServer: %v\n", err)
	})

	// GO CONCEPT: Closures Capture by Reference
	// -------------------------------------------
	// This closure captures "client" and "launchedPid" from the enclosing
	// scope. In Go, closures capture variables by reference (they see the
	// current value at the time they run, not the value when they were
	// created). This is the same as Swift's default capture behavior.
	//
	// Compare with Python: Python closures also capture by reference, with
	// a well-known gotcha in loops: `for i in range(3): funcs.append(lambda: i)`
	// — all three lambdas return 2. The fix is a default argument:
	// `lambda i=i: i`. Go avoids this because loop variables are re-scoped
	// per iteration since Go 1.22.
	//
	// We define cleanup as a variable holding a function value so we can
	// pass it to setupSignalHandler AND call it at the end of main().

	// Cleanup function for signal handling and normal exit
	cleanup := func() {
		client.Disconnect()
		if launchedPid > 0 {
			// We launched the server, so terminate it on exit.
			// os.FindProcess gets a handle to a process by PID.
			// On Unix it always succeeds, even if the process is gone.
			if proc, err := os.FindProcess(launchedPid); err == nil {
				// Send SIGTERM (graceful shutdown request) to the server
				proc.Signal(syscall.SIGTERM)
			}
		}
	}

	// Install signal handlers (runs cleanup in a background goroutine when
	// SIGINT or SIGTERM is received)
	setupSignalHandler(cleanup)

	// Print welcome banner
	fmt.Print(welcomeBanner())
	fmt.Println("Connected to AtticServer via CLI protocol")
	fmt.Println()

	// Run the REPL — this blocks until the user types .quit or Ctrl-D.
	// (Stub implementation for Phase 1; full version in Phase 4.)
	runREPL(client, args.atascii)

	// Clean up on normal exit (REPL returned because user typed .quit)
	cleanup()
}
