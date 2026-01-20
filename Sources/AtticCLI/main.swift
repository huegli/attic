// =============================================================================
// main.swift - Attic CLI Entry Point
// =============================================================================
//
// This is the main entry point for the Attic command-line interface.
// The CLI provides a REPL (Read-Eval-Print Loop) for interacting with the
// Atari 800 XL emulator from the terminal or Emacs comint mode.
//
// Usage:
//   attic                    Connect to running AtticServer (or launch one)
//   attic --headless         Launch AtticServer and connect
//   attic --headless --silent  Headless without audio
//   attic --socket <path>    Connect to specific socket
//   attic --help             Show help
//
// The CLI communicates with AtticServer via a Unix socket using the CLI
// text protocol. If no server is running, the CLI can launch one.
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
// MARK: - REPL Loop (Local)
// =============================================================================

/// Runs the REPL loop with a local emulator engine.
///
/// This function reads commands from stdin, executes them, and writes
/// output to stdout. It continues until the user types .quit or .shutdown.
///
/// - Parameters:
///   - repl: The REPL engine to use.
@MainActor
func runLocalREPL(repl: REPLEngine) async {
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
// MARK: - REPL Loop (Socket)
// =============================================================================

/// Current REPL mode for socket-based REPL.
/// Tracks which mode (monitor, basic, dos) we're in for prompt display.
enum SocketREPLMode: String {
    case monitor
    case basic
    case dos

    var prompt: String {
        switch self {
        case .monitor:
            return "[monitor] >"
        case .basic:
            return "[basic] >"
        case .dos:
            return "[dos] D1:>"
        }
    }
}

/// Runs the REPL loop over a socket connection.
///
/// This function reads commands from stdin, sends them to the server,
/// and displays responses. It handles the socket protocol.
///
/// - Parameter client: The connected socket client.
@MainActor
func runSocketREPL(client: CLISocketClient) async {
    // Print welcome banner
    print(AtticCore.welcomeBanner)
    print("Connected to AtticServer via CLI protocol\n")

    var currentMode = SocketREPLMode.basic
    var shouldContinue = true

    // Print initial prompt
    print(currentMode.prompt, terminator: " ")
    fflush(stdout)

    // Read lines from stdin
    while shouldContinue {
        guard let line = readLine() else {
            // EOF (Ctrl-D)
            print("\nGoodbye")
            break
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        guard !trimmed.isEmpty else {
            print(currentMode.prompt, terminator: " ")
            fflush(stdout)
            continue
        }

        // Handle mode switching commands locally
        if trimmed.hasPrefix(".") {
            switch trimmed.lowercased() {
            case ".monitor":
                currentMode = .monitor
                print("Switched to monitor mode")
                print(currentMode.prompt, terminator: " ")
                fflush(stdout)
                continue

            case ".basic", ".basic turbo", ".basic atari":
                currentMode = .basic
                print("Switched to BASIC mode")
                print(currentMode.prompt, terminator: " ")
                fflush(stdout)
                continue

            case ".dos":
                currentMode = .dos
                print("Switched to DOS mode")
                print(currentMode.prompt, terminator: " ")
                fflush(stdout)
                continue

            case ".quit":
                // Send quit command to server
                do {
                    _ = try await client.send(.quit)
                } catch {
                    // Ignore errors on quit
                }
                print("Goodbye")
                shouldContinue = false
                continue

            case ".shutdown":
                // Send shutdown command to server
                do {
                    _ = try await client.send(.shutdown)
                } catch {
                    // Ignore errors on shutdown
                }
                print("Shutting down")
                shouldContinue = false
                continue

            case ".help":
                printHelp(mode: currentMode)
                print(currentMode.prompt, terminator: " ")
                fflush(stdout)
                continue

            case ".status":
                // Forward to server
                break

            default:
                if trimmed.hasPrefix(".state ") || trimmed == ".reset" || trimmed == ".warmstart" {
                    // Forward to server
                    break
                }
                printError("Unknown command: \(trimmed)")
                print(currentMode.prompt, terminator: " ")
                fflush(stdout)
                continue
            }
        }

        // Translate REPL command to CLI protocol command
        let cliCommand = translateToProtocol(line: trimmed, mode: currentMode)

        // Send to server
        do {
            let response = try await client.sendRaw(cliCommand)

            // Display response
            switch response {
            case .ok(let data):
                // Handle multi-line responses
                let lines = data.split(separator: "\u{1E}", omittingEmptySubsequences: false)
                for line in lines {
                    print(line)
                }

            case .error(let message):
                printError(message)
            }
        } catch {
            printError("Communication error: \(error.localizedDescription)")
        }

        // Print next prompt
        if shouldContinue {
            print(currentMode.prompt, terminator: " ")
            fflush(stdout)
        }
    }

    // Disconnect
    await client.disconnect()
}

/// Translates a REPL command to a CLI protocol command string.
///
/// - Parameters:
///   - line: The user's input line.
///   - mode: The current REPL mode.
/// - Returns: The CLI protocol command string.
func translateToProtocol(line: String, mode: SocketREPLMode) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)

    // Handle dot commands
    if trimmed.hasPrefix(".") {
        switch trimmed.lowercased() {
        case ".status":
            return "status"
        case ".reset":
            return "reset cold"
        case ".warmstart":
            return "reset warm"
        default:
            // Handle .state save/load
            if trimmed.lowercased().hasPrefix(".state save ") {
                let path = String(trimmed.dropFirst(12))
                return "state save \(path)"
            } else if trimmed.lowercased().hasPrefix(".state load ") {
                let path = String(trimmed.dropFirst(12))
                return "state load \(path)"
            }
        }
    }

    // Mode-specific command translation
    switch mode {
    case .monitor:
        return translateMonitorCommand(trimmed)
    case .basic:
        // BASIC commands are mostly local; pass through for now
        return trimmed
    case .dos:
        return translateDOSCommand(trimmed)
    }
}

/// Translates a monitor mode command.
func translateMonitorCommand(_ cmd: String) -> String {
    let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let command = parts.first else { return cmd }

    let cmdLower = String(command).lowercased()
    let args = parts.count > 1 ? String(parts[1]) : ""

    switch cmdLower {
    case "g":
        return args.isEmpty ? "resume" : "resume"  // TODO: Set PC first
    case "s", "step":
        return args.isEmpty ? "step" : "step \(args)"
    case "p", "pause":
        return "pause"
    case "r", "registers":
        return args.isEmpty ? "registers" : "registers \(args)"
    case "m", "memory":
        // m $0600 16 -> read $0600 16
        return "read \(args)"
    case ">":
        // > $0600 A9,00 -> write $0600 A9,00
        return "write \(args)"
    case "d", "disassemble":
        // TODO: Not yet implemented
        return "disassemble \(args)"
    case "b", "breakpoint":
        return "breakpoint \(args)"
    default:
        return cmd
    }
}

/// Translates a DOS mode command.
func translateDOSCommand(_ cmd: String) -> String {
    let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard let command = parts.first else { return cmd }

    let cmdLower = String(command).lowercased()
    let args = parts.count > 1 ? String(parts[1]) : ""

    switch cmdLower {
    case "mount":
        return "mount \(args)"
    case "unmount", "umount":
        return "unmount \(args)"
    case "drives", "dir":
        return args.isEmpty ? "drives" : cmd
    default:
        return cmd
    }
}

/// Prints help for the current mode.
func printHelp(mode: SocketREPLMode) {
    print("""
    Global Commands:
      .monitor          Switch to monitor mode
      .basic            Switch to BASIC mode
      .dos              Switch to DOS mode
      .help             Show help
      .status           Show emulator status
      .reset            Cold reset
      .warmstart        Warm reset
      .state save <p>   Save state to file
      .state load <p>   Load state from file
      .quit             Exit CLI
      .shutdown         Exit and stop server
    """)

    switch mode {
    case .monitor:
        print("""

        Monitor Commands:
          g [addr]          Go (resume) from current or specified address
          s [n]             Step n instructions (default: 1)
          p                 Pause emulation
          r [reg=val...]    Display/set registers
          m <addr> <len>    Memory dump
          > <addr> <bytes>  Write memory
          b set <addr>      Set breakpoint
          b clear <addr>    Clear breakpoint
          b list            List breakpoints
        """)

    case .basic:
        print("""

        BASIC Mode:
          Enter BASIC lines with line numbers
          Commands are forwarded to the emulator
        """)

    case .dos:
        print("""

        DOS Commands:
          mount <n> <path>  Mount disk image to drive n
          unmount <n>       Unmount drive n
          drives            List mounted drives
        """)
    }
}

// =============================================================================
// MARK: - Socket Connection
// =============================================================================

/// The global socket client for CLI communication.
/// Uses @MainActor for thread-safety as the CLI runs on the main actor.
@MainActor var socketClient: CLISocketClient?

/// Connects to AtticServer via Unix socket.
///
/// - Parameter path: Path to the Unix socket.
/// - Returns: True if connection successful.
@MainActor func connectToSocket(path: String) async -> Bool {
    let client = CLISocketClient()

    do {
        try await client.connect(to: path)
        socketClient = client
        return true
    } catch {
        printError("Failed to connect to \(path): \(error.localizedDescription)")
        return false
    }
}

/// Launches AtticServer as a subprocess.
///
/// - Parameters:
///   - headless: Whether to run without GUI.
///   - silent: Whether to disable audio.
/// - Returns: The socket path if successful, nil otherwise.
func launchServer(headless: Bool, silent: Bool) -> String? {
    // Build the path to AtticServer executable
    // In development, it's in the same build directory
    // In production, it would be in /usr/local/bin or similar

    let serverPath = findServerExecutable()
    guard let serverPath = serverPath else {
        printError("Could not find AtticServer executable")
        return nil
    }

    // Create arguments
    var arguments: [String] = []
    if silent {
        arguments.append("--silent")
    }

    // Launch server
    let process = Process()
    process.executableURL = URL(fileURLWithPath: serverPath)
    process.arguments = arguments

    // Redirect output to /dev/null to avoid cluttering CLI output
    // In debug mode, you might want to redirect to a log file instead
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        printError("Failed to launch AtticServer: \(error.localizedDescription)")
        return nil
    }

    // Wait briefly for server to start and create socket
    Thread.sleep(forTimeInterval: 0.5)

    // The socket path is based on the server's PID
    let socketPath = CLIProtocolConstants.socketPath(for: process.processIdentifier)

    // Wait for socket to appear (with timeout)
    var retries = 10
    while retries > 0 {
        if FileManager.default.fileExists(atPath: socketPath) {
            print("AtticServer started (PID: \(process.processIdentifier))")
            return socketPath
        }
        Thread.sleep(forTimeInterval: 0.2)
        retries -= 1
    }

    printError("AtticServer started but socket not found at \(socketPath)")
    return nil
}

/// Finds the AtticServer executable.
///
/// Searches in several locations:
/// 1. Same directory as the CLI executable
/// 2. PATH environment variable
/// 3. Common installation locations
func findServerExecutable() -> String? {
    let fileManager = FileManager.default

    // Get the directory containing this CLI executable
    let executablePath = CommandLine.arguments[0]
    let executableDir = (executablePath as NSString).deletingLastPathComponent

    // Check in same directory
    let sameDirPath = (executableDir as NSString).appendingPathComponent("AtticServer")
    if fileManager.isExecutableFile(atPath: sameDirPath) {
        return sameDirPath
    }

    // Check in PATH
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        for dir in pathEnv.split(separator: ":") {
            let path = (String(dir) as NSString).appendingPathComponent("AtticServer")
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
    }

    // Check common locations
    let commonPaths = [
        "/usr/local/bin/AtticServer",
        "/opt/homebrew/bin/AtticServer",
        "~/.local/bin/AtticServer"
    ]

    for path in commonPaths {
        let expandedPath = (path as NSString).expandingTildeInPath
        if fileManager.isExecutableFile(atPath: expandedPath) {
            return expandedPath
        }
    }

    return nil
}

/// Discovers an existing AtticServer socket.
///
/// - Returns: Path to socket, or nil if not found.
func discoverSocket() -> String? {
    let client = CLISocketClient()
    return client.discoverSocket()
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

        // Determine socket path and connection mode
        var socketPath: String?

        if let specifiedPath = args.socketPath {
            // User specified a socket path
            socketPath = specifiedPath
        } else {
            // Try to discover existing server
            socketPath = discoverSocket()
        }

        // If no socket found and we need one, launch server
        if socketPath == nil {
            print("No running AtticServer found. Launching...")
            socketPath = launchServer(headless: args.headless, silent: args.silent)

            if socketPath == nil {
                printError("Failed to start AtticServer")
                printError("You can start it manually with: AtticServer")
                exit(1)
            }
        }

        // Connect to the socket
        guard let path = socketPath else {
            printError("No socket path available")
            exit(1)
        }

        print("Connecting to \(path)...")
        if await !connectToSocket(path: path) {
            printError("Failed to connect to AtticServer")
            exit(1)
        }

        // Get the connected client and run REPL
        guard let client = socketClient else {
            printError("Socket client not initialized")
            exit(1)
        }

        // Run socket-based REPL
        await runSocketREPL(client: client)
    }
}
