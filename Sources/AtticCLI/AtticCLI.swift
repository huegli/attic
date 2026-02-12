// =============================================================================
// main.swift - Attic CLI Entry Point
// =============================================================================
//
// This is the main entry point for the Attic command-line interface.
// The CLI is a pure protocol client that connects to AtticServer via a Unix
// socket using the CLI text protocol. It provides a REPL (Read-Eval-Print Loop)
// for interacting with the Atari 800 XL emulator from the terminal or Emacs
// comint mode.
//
// Usage:
//   attic                    Connect to running AtticServer (or launch one)
//   attic --headless         Launch AtticServer and connect
//   attic --headless --silent  Headless without audio
//   attic --socket <path>    Connect to specific socket
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
// MARK: - Main Entry Point
// =============================================================================

/// The main entry point for the Attic CLI.
/// All declarations are inside the struct to comply with Swift 6's requirement
/// that @main cannot be used in a module with top-level code.
@main
struct AtticCLI {

    // =========================================================================
    // MARK: - Command Line Arguments
    // =========================================================================

    /// Parsed command-line arguments.
    struct Arguments {
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
    static func parseArguments() -> Arguments {
        var args = Arguments()
        var arguments = CommandLine.arguments.dropFirst()  // Skip program name

        while let arg = arguments.popFirst() {
            switch arg {
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

    // =========================================================================
    // MARK: - Help and Usage
    // =========================================================================

    /// Prints usage information.
    static func printUsage() {
        print("""
        USAGE: attic [options]

        OPTIONS:
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
    static func printVersion() {
        print("\(AtticCore.fullTitle)")
        print("Build: \(AtticCore.buildConfiguration)")
    }

    /// Prints an error message to stderr.
    static func printError(_ message: String) {
        FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    }

    // =========================================================================
    // MARK: - REPL Loop (Socket)
    // =========================================================================

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
    static func runSocketREPL(client: CLISocketClient) async {
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
                    if let pid = launchedServerPid {
                        // We launched the server — shut it down
                        do {
                            _ = try await client.send(.shutdown)
                        } catch {
                            // Ignore errors on shutdown
                        }
                        // Ensure the process is terminated
                        kill(pid, SIGTERM)
                        print("Shutting down server (PID: \(pid))")
                    } else {
                        // Server was already running — just disconnect
                        print("Server was not launched by this session, leaving it running.")
                    }
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
                    // Handle commands that forward to server
                    let lowerTrimmed = trimmed.lowercased()
                    if lowerTrimmed.hasPrefix(".state ") ||
                       lowerTrimmed == ".reset" ||
                       lowerTrimmed == ".warmstart" ||
                       lowerTrimmed == ".screenshot" ||
                       lowerTrimmed.hasPrefix(".screenshot ") ||
                       lowerTrimmed.hasPrefix(".boot ") {
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
    static func translateToProtocol(line: String, mode: SocketREPLMode) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Handle dot commands
        if trimmed.hasPrefix(".") {
            let lowerTrimmed = trimmed.lowercased()
            switch lowerTrimmed {
            case ".status":
                return "status"
            case ".reset":
                return "reset cold"
            case ".warmstart":
                return "reset warm"
            case ".screenshot":
                return "screenshot"
            default:
                // Handle .screenshot with path
                if lowerTrimmed.hasPrefix(".screenshot ") {
                    let path = String(trimmed.dropFirst(12))
                    return "screenshot \(path)"
                }
                // Handle .state save/load
                if lowerTrimmed.hasPrefix(".state save ") {
                    let path = String(trimmed.dropFirst(12))
                    return "state save \(path)"
                } else if lowerTrimmed.hasPrefix(".state load ") {
                    let path = String(trimmed.dropFirst(12))
                    return "state load \(path)"
                }
                // Handle .boot <path>
                if lowerTrimmed.hasPrefix(".boot ") {
                    let path = String(trimmed.dropFirst(6))
                    return "boot \(path)"
                }
            }
        }

        // Mode-specific command translation
        switch mode {
        case .monitor:
            return translateMonitorCommand(trimmed)
        case .basic:
            return translateBASICCommand(trimmed)
        case .dos:
            return translateDOSCommand(trimmed)
        }
    }

    /// Translates a monitor mode command.
    static func translateMonitorCommand(_ cmd: String) -> String {
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

    /// Translates a BASIC mode command.
    ///
    /// Recognizes special commands (list, run, new) and translates them to
    /// protocol commands. Everything else is sent as injected keystrokes.
    static func translateBASICCommand(_ cmd: String) -> String {
        let upper = cmd.uppercased()
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let keyword = parts.first.map { String($0).uppercased() } ?? ""
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch keyword {
        // Read-only listing via protocol (detokenizer, not screen scrape)
        case "LIST":
            return "basic list"

        // BASIC editing commands - routed to protocol handlers
        case "DEL", "DELETE":
            guard !args.isEmpty else { return "basic del" }  // let server report error
            return "basic del \(args)"
        case "STOP":
            return "basic stop"
        case "CONT":
            return "basic cont"
        case "VARS":
            return "basic vars"
        case "VAR":
            guard !args.isEmpty else { return "basic var" }  // let server report error
            return "basic var \(args)"
        case "INFO":
            return "basic info"
        case "EXPORT":
            guard !args.isEmpty else { return "basic export" }  // let server report error
            return "basic export \(args)"
        case "IMPORT":
            guard !args.isEmpty else { return "basic import" }  // let server report error
            return "basic import \(args)"
        case "DIR":
            return args.isEmpty ? "basic dir" : "basic dir \(args)"

        default:
            // Default: inject keys to type BASIC input via keyboard (natural input)
            // Escape special characters and add RETURN at the end
            let escaped = cmd
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: " ", with: "\\s")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "inject keys \(escaped)\\n"
        }
    }

    /// Translates a DOS mode command.
    static func translateDOSCommand(_ cmd: String) -> String {
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
    static func printHelp(mode: SocketREPLMode) {
        print("""
        Global Commands:
          .monitor          Switch to monitor mode
          .basic            Switch to BASIC mode
          .dos              Switch to DOS mode
          .help             Show help
          .status           Show emulator status
          .screenshot [p]   Save screenshot (default: ~/Desktop/Attic-<time>.png)
          .boot <path>      Boot with file (ATR, XEX, BAS, etc.)
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
              Enter BASIC lines with line numbers (e.g. 10 PRINT "HELLO")
              list              List program (via detokenizer)
              del <line|range>  Delete line or range (e.g. del 30, del 10-50)
              info              Show program size (lines, bytes, variables)
              vars              List all variables with values
              var <name>        Show single variable (e.g. var X, var A$)
              stop              Send BREAK to stop running program
              cont              Continue after BREAK
              export <path>     Export listing to file
              import <path>     Import listing from file
              dir [drive]       List disk directory (default: current drive)
              Other input is typed into the emulator as keystrokes
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

    // =========================================================================
    // MARK: - Socket Connection
    // =========================================================================

    /// The socket client for CLI communication.
    @MainActor static var socketClient: CLISocketClient?

    /// PID of the server process if this CLI session launched it.
    /// Nil means the server was already running when we connected.
    /// Access is sequential: set during launch (before REPL), read on shutdown.
    nonisolated(unsafe) static var launchedServerPid: Int32?

    /// Connects to AtticServer via Unix socket.
    ///
    /// - Parameter path: Path to the Unix socket.
    /// - Returns: True if connection successful.
    @MainActor static func connectToSocket(path: String) async -> Bool {
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

    /// Launches AtticServer as a subprocess using the shared ServerLauncher.
    ///
    /// - Parameters:
    ///   - headless: Whether to run without GUI (unused, kept for API compatibility).
    ///   - silent: Whether to disable audio.
    /// - Returns: The socket path if successful, nil otherwise.
    static func launchServer(headless: Bool, silent: Bool) -> String? {
        let launcher = ServerLauncher()
        let options = ServerLaunchOptions(silent: silent)

        switch launcher.launchServer(options: options) {
        case .success(let socketPath, let pid):
            print("AtticServer started (PID: \(pid))")
            launchedServerPid = pid
            return socketPath

        case .executableNotFound:
            printError("Could not find AtticServer executable")
            return nil

        case .launchFailed(let error):
            printError("Failed to launch AtticServer: \(error.localizedDescription)")
            return nil

        case .socketTimeout(let pid):
            printError("AtticServer started (PID: \(pid)) but socket not found")
            return nil
        }
    }

    /// Discovers an existing AtticServer socket.
    ///
    /// - Returns: Path to socket, or nil if not found.
    static func discoverSocket() -> String? {
        let client = CLISocketClient()
        return client.discoverSocket()
    }

    // =========================================================================
    // MARK: - Main Function
    // =========================================================================

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
        if await !Self.connectToSocket(path: path) {
            printError("Failed to connect to AtticServer")
            exit(1)
        }

        // Get the connected client and run REPL
        guard let client = Self.socketClient else {
            printError("Socket client not initialized")
            exit(1)
        }

        // Run socket-based REPL
        await runSocketREPL(client: client)
    }
}
