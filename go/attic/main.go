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

package main

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

const (
	// version is the current version of the Go CLI, kept in sync with the
	// Swift AtticCore.version which is the single source of truth.
	version = "0.2.0"

	// appName is the application name.
	appName = "Attic"

	// copyright is the copyright notice.
	copyright = "Copyright (c) 2024"
)

// fullTitle returns the application name with version.
func fullTitle() string {
	return fmt.Sprintf("%s v%s (Go)", appName, version)
}

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

// arguments holds the parsed command-line arguments.
type arguments struct {
	// silent disables audio output when launching the server.
	silent bool

	// socketPath is the path to an existing server socket to connect to.
	// If empty, the CLI will discover or launch a server automatically.
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

// parseArguments parses command-line arguments.
//
// This is a simple hand-written parser matching the Swift CLI's behavior.
// There are only 6 flags and no subcommands, so a framework like cobra
// would be over-engineering.
func parseArguments() arguments {
	args := arguments{
		atascii: true, // Default: rich ATASCII rendering enabled
	}

	// Skip program name (os.Args[0])
	remaining := os.Args[1:]

	for len(remaining) > 0 {
		arg := remaining[0]
		remaining = remaining[1:]

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
	fmt.Println(fullTitle())
}

// printError prints an error message to stderr.
func printError(message string) {
	fmt.Fprintf(os.Stderr, "Error: %s\n", message)
}

// =============================================================================
// Server Discovery and Connection
// =============================================================================

// discoverOrConnect discovers an existing AtticServer socket, or launches a
// new server if none is found. Returns the connected client and the PID of
// the launched server (0 if we connected to an existing server).
func discoverOrConnect(args arguments) (*atticprotocol.Client, int) {
	client := atticprotocol.NewClient()
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
		var err error
		socketPath, launchedPid, err = launchServer(args.silent)
		if err != nil {
			printError(fmt.Sprintf("Failed to start AtticServer: %v", err))
			printError("You can start it manually with: AtticServer")
			os.Exit(1)
		}
		fmt.Printf("AtticServer started (PID: %d)\n", launchedPid)
	}

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

// setupSignalHandler installs handlers for SIGINT and SIGTERM so the CLI can
// clean up (save history, disconnect, optionally stop the server) on exit.
func setupSignalHandler(cleanup func()) {
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		fmt.Println() // Newline after ^C
		cleanup()
		os.Exit(0)
	}()
}

// =============================================================================
// Main
// =============================================================================

func main() {
	// Parse arguments
	args := parseArguments()

	// Handle --help
	if args.showHelp {
		printUsage()
		return
	}

	// Handle --version
	if args.showVersion {
		printVersion()
		return
	}

	// Discover or launch server, then connect
	client, launchedPid := discoverOrConnect(args)

	// Set up event handler for async events (breakpoints, stops, errors)
	client.SetEventHandler(func(event atticprotocol.Event) {
		// Print async events to stdout as they arrive
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

	// Cleanup function for signal handling and normal exit
	cleanup := func() {
		client.Disconnect()
		if launchedPid > 0 {
			// We launched the server, so terminate it on exit
			if proc, err := os.FindProcess(launchedPid); err == nil {
				proc.Signal(syscall.SIGTERM)
			}
		}
	}

	// Install signal handlers
	setupSignalHandler(cleanup)

	// Print welcome banner
	fmt.Print(welcomeBanner())
	fmt.Println("Connected to AtticServer via CLI protocol")
	fmt.Println()

	// Run the REPL (placeholder - will be implemented in Phase 4)
	runREPL(client, args.atascii)

	// Clean up on normal exit
	cleanup()
}
