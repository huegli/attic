// =============================================================================
// main.swift - Attic CLI Entry Point
// =============================================================================
//
// This is the main entry point for the Attic command-line interface.
// The CLI provides a REPL (Read-Eval-Print Loop) for interacting with the
// Atari 800 XL emulator from the terminal or Emacs comint mode.
//
// Usage:
//   attic                    Launch GUI and connect REPL
//   attic --headless         Run emulator without GUI
//   attic --headless --silent  Headless without audio
//   attic --socket <path>    Connect to existing GUI
//   attic --help             Show help
//
// The CLI supports three modes:
// - Monitor: 6502 debugging (disassembly, breakpoints, memory inspection)
// - BASIC: Program entry and execution
// - DOS: Disk image management
//
// For Emacs integration, use M-x atari800-run after loading atari800.el.
//
// =============================================================================

import Foundation
import AtticCore

// =============================================================================
// MARK: - Command Line Arguments
// =============================================================================

/// Parsed command-line arguments.
struct Arguments {
    /// Start in REPL mode (default).
    var repl: Bool = true

    /// Run without launching GUI.
    var headless: Bool = false

    /// Disable audio (headless only).
    var silent: Bool = false

    /// Path to socket for connecting to existing GUI.
    var socketPath: String?

    /// Show help and exit.
    var showHelp: Bool = false

    /// Show version and exit.
    var showVersion: Bool = false
}

/// Parses command-line arguments.
///
/// This is a simple hand-written parser. For more complex needs,
/// consider using Swift Argument Parser package.
func parseArguments() -> Arguments {
    var args = Arguments()
    var arguments = CommandLine.arguments.dropFirst()  // Skip program name

    while let arg = arguments.popFirst() {
        switch arg {
        case "--repl":
            args.repl = true

        case "--headless":
            args.headless = true

        case "--silent":
            args.silent = true

        case "--socket":
            if let path = arguments.popFirst() {
                args.socketPath = path
            } else {
                printError("--socket requires a path argument")
                exit(1)
            }

        case "--help", "-h":
            args.showHelp = true

        case "--version", "-v":
            args.showVersion = true

        default:
            printError("Unknown argument: \(arg)")
            printUsage()
            exit(1)
        }
    }

    return args
}

// =============================================================================
// MARK: - Help and Usage
// =============================================================================

/// Prints usage information.
func printUsage() {
    print("""
    USAGE: attic [options]

    OPTIONS:
      --repl              Start in REPL mode (default)
      --headless          Run without launching GUI
      --silent            Disable audio output (headless mode only)
      --socket <path>     Connect to GUI at specific socket path
      --help, -h          Show this help
      --version, -v       Show version

    EXAMPLES:
      attic                                Launch GUI and connect REPL
      attic --headless                     Run emulator without GUI
      attic --headless --silent            Headless without audio
      attic --socket /tmp/attic-1234.sock  Connect to existing GUI

    MODES:
      The REPL operates in three modes. Switch with dot-commands:
        .monitor    6502 debugging (disassembly, breakpoints, stepping)
        .basic      BASIC program entry and execution
        .dos        Disk image management

    For Emacs integration, load emacs/atari800.el and use M-x atari800-run.

    """)
}

/// Prints version information.
func printVersion() {
    print("\(AtticCore.fullTitle)")
    print("Build: \(AtticCore.buildConfiguration)")
}

/// Prints an error message to stderr.
func printError(_ message: String) {
    FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
}

// =============================================================================
// MARK: - REPL Loop
// =============================================================================

/// Runs the REPL loop.
///
/// This function reads commands from stdin, executes them, and writes
/// output to stdout. It continues until the user types .quit or .shutdown.
///
/// - Parameters:
///   - repl: The REPL engine to use.
@MainActor
func runREPL(repl: REPLEngine) async {
    // Print welcome banner
    print(AtticCore.welcomeBanner)

    // Print initial prompt
    print(await repl.prompt, terminator: "")
    fflush(stdout)

    // Read lines from stdin
    while await repl.shouldContinue {
        guard let line = readLine() else {
            // EOF (Ctrl-D)
            print("\nGoodbye")
            break
        }

        // Skip empty lines
        guard !line.isEmpty else {
            print(await repl.prompt, terminator: "")
            fflush(stdout)
            continue
        }

        // Execute command
        if let output = await repl.execute(line) {
            print(output)
        }

        // Print prompt for next command
        if await repl.shouldContinue {
            print(await repl.prompt, terminator: "")
            fflush(stdout)
        }
    }
}

// =============================================================================
// MARK: - Socket Connection (Stub)
// =============================================================================

/// Connects to an existing GUI via Unix socket.
///
/// - Parameter path: Path to the Unix socket.
/// - Returns: True if connection successful.
func connectToSocket(path: String) -> Bool {
    // TODO: Implement socket connection in Phase 6
    printError("Socket connection not yet implemented")
    printError("Path: \(path)")
    return false
}

/// Launches the GUI application.
///
/// - Returns: True if GUI was launched successfully.
func launchGUI() -> Bool {
    // TODO: Implement GUI launch in Phase 6
    print("Note: GUI launch not yet implemented")
    print("Running in headless mode for now...")
    return true
}

/// Discovers an existing GUI socket.
///
/// - Returns: Path to socket, or nil if not found.
func discoverSocket() -> String? {
    // TODO: Implement socket discovery in Phase 6
    // Look for /tmp/attic-*.sock files
    return nil
}

// =============================================================================
// MARK: - Main Entry Point
// =============================================================================

@main
struct AtticCLI {
    static func main() async {
        // Parse arguments
        let args = parseArguments()

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

        // Create emulator engine
        let emulator = EmulatorEngine()

        // In headless mode, we run the emulator directly
        if args.headless {
            print("Starting in headless mode...")

            // Try to initialize emulator
            // Note: This will fail until ROMs are provided
            // For now, we'll continue anyway for testing

            // Create REPL engine
            let repl = REPLEngine(emulator: emulator)

            // Run REPL
            await runREPL(repl: repl)
        } else {
            // Normal mode: connect to or launch GUI
            if let socketPath = args.socketPath {
                // Connect to specified socket
                if !connectToSocket(path: socketPath) {
                    exit(1)
                }
            } else {
                // Try to find existing GUI socket
                if let existingSocket = discoverSocket() {
                    print("Found existing GUI at \(existingSocket)")
                    if !connectToSocket(path: existingSocket) {
                        exit(1)
                    }
                } else {
                    // Launch new GUI
                    if !launchGUI() {
                        printError("Failed to launch GUI")
                        exit(1)
                    }
                }
            }

            // For now, just run headless REPL
            // Full GUI integration in Phase 6
            let repl = REPLEngine(emulator: emulator)
            await runREPL(repl: repl)
        }
    }
}
