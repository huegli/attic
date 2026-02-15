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
//   attic --silent           Launch without audio
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
        /// Disable audio output.
        var silent: Bool = false

        /// Path to socket for connecting to existing GUI.
        var socketPath: String?

        /// Enable rich ATASCII rendering in program listings.
        /// When true, ANSI escape codes are used for inverse video and
        /// ATASCII graphics characters are mapped to Unicode equivalents.
        /// Defaults to true for accurate visual representation in terminals.
        var atascii: Bool = true

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
            case "--silent":
                args.silent = true

            case "--atascii":
                args.atascii = true

            case "--plain":
                args.atascii = false

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
          attic                                Launch server and connect REPL
          attic --plain                        Use plain ASCII rendering
          attic --socket /tmp/attic-1234.sock  Connect to existing server

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
    /// and displays responses. It handles the socket protocol and the
    /// interactive assembly sub-mode.
    ///
    /// The LineEditor provides Emacs-style line editing (Ctrl-A/E/K, arrow
    /// keys) and persistent command history when running in a terminal.
    /// When stdin is a pipe (Emacs comint, scripted input), it falls back
    /// to readLine() for compatibility.
    ///
    /// - Parameter client: The connected socket client.
    @MainActor
    static func runSocketREPL(client: CLISocketClient) async {
        // Print welcome banner
        print(AtticCore.welcomeBanner)
        print("Connected to AtticServer via CLI protocol\n")

        // Create line editor for interactive input with history
        let lineEditor = LineEditor()

        var currentMode = SocketREPLMode.basic
        var shouldContinue = true

        // Interactive assembly sub-mode state.
        // When active, user input is routed to "asm input" / "asm end"
        // instead of being interpreted as normal REPL commands.
        var inAssemblyMode = false
        var assemblyAddress: UInt16 = 0

        // Read lines from stdin.
        // The LineEditor handles prompt display — no manual print+fflush needed.
        while shouldContinue {
            // Determine the appropriate prompt based on current state
            let prompt: String
            if inAssemblyMode {
                prompt = "$\(String(format: "%04X", assemblyAddress)):"
            } else {
                prompt = currentMode.prompt
            }

            guard let line = lineEditor.getLine(prompt: prompt) else {
                // EOF (Ctrl-D) — end assembly session if active
                if inAssemblyMode {
                    _ = try? await client.sendRaw("asm end")
                    inAssemblyMode = false
                }
                print("\nGoodbye")
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // --- Interactive assembly sub-mode ---
            // Empty line or "." exits assembly mode; anything else is assembled.
            if inAssemblyMode {
                if trimmed.isEmpty || trimmed == "." {
                    // End the assembly session
                    do {
                        let response = try await client.sendRaw("asm end")
                        switch response {
                        case .ok(let data):
                            print(data)
                        case .error(let message):
                            printError(message)
                        }
                    } catch {
                        printError("Communication error: \(error.localizedDescription)")
                    }
                    inAssemblyMode = false
                    // Loop continues — prompt handled by lineEditor.getLine()
                    continue
                }

                // Feed instruction to the active assembly session
                do {
                    let response = try await client.sendRaw("asm input \(trimmed)")
                    switch response {
                    case .ok(let data):
                        // Response format: "formatted line\x1E$XXXX"
                        let parts = data.split(
                            separator: Character("\u{1E}"),
                            maxSplits: 1,
                            omittingEmptySubsequences: false
                        )
                        // Print the assembled line
                        print(parts[0])
                        // Extract next address for the prompt
                        if parts.count > 1, let addr = parseHexAddress(String(parts[1])) {
                            assemblyAddress = addr
                        }
                    case .error(let message):
                        printError(message)
                        // Session stays alive on error — user can retry
                    }
                } catch {
                    printError("Communication error: \(error.localizedDescription)")
                }

                // Loop continues — assembly prompt handled by lineEditor.getLine()
                continue
            }

            // Skip empty lines (normal mode)
            guard !trimmed.isEmpty else {
                continue
            }

            // Handle mode switching commands locally
            if trimmed.hasPrefix(".") {
                switch trimmed.lowercased() {
                case ".monitor":
                    currentMode = .monitor
                    print("Switched to monitor mode")
                    continue

                case ".basic", ".basic turbo", ".basic atari":
                    currentMode = .basic
                    print("Switched to BASIC mode")
                    continue

                case ".dos":
                    currentMode = .dos
                    print("Switched to DOS mode")
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
                    printHelp(mode: currentMode, topic: nil)
                    continue

                case ".status":
                    // Forward to server
                    break

                case ".screen":
                    // Forward to server
                    break

                default:
                    let lowerTrimmed = trimmed.lowercased()

                    // Handle .help <topic> — show help for a specific command
                    if lowerTrimmed.hasPrefix(".help ") {
                        let topic = String(trimmed.dropFirst(6))
                            .trimmingCharacters(in: .whitespaces)
                        printHelp(mode: currentMode, topic: topic)
                        continue
                    }

                    // Handle commands that forward to server
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
                    continue
                }
            }

            // Translate REPL command to one or more CLI protocol commands.
            // Some monitor commands (e.g. `g $addr`) expand to multiple
            // sequential protocol commands.
            let cliCommands = translateToProtocol(line: trimmed, mode: currentMode)

            // Send each command to the server in order
            do {
                for cliCommand in cliCommands {
                    let response = try await client.sendRaw(cliCommand)

                    // Display response
                    switch response {
                    case .ok(let data):
                        // Check if the server started an interactive assembly session.
                        // Response format: "ASM $XXXX"
                        if data.hasPrefix("ASM $") {
                            if let addr = parseHexAddress(String(data.dropFirst(4))) {
                                inAssemblyMode = true
                                assemblyAddress = addr
                                // Loop continues — assembly prompt handled by lineEditor.getLine()
                                continue
                            }
                        }

                        // Handle multi-line responses
                        let lines = data.split(separator: "\u{1E}", omittingEmptySubsequences: false)
                        for line in lines {
                            print(line)
                        }

                    case .error(let message):
                        printError(message)
                    }
                }
            } catch {
                printError("Communication error: \(error.localizedDescription)")
            }

        }

        // Save history and release libedit resources before disconnecting
        lineEditor.shutdown()

        // Disconnect
        await client.disconnect()
    }

    /// Translates a REPL command to one or more CLI protocol command strings.
    ///
    /// Most commands produce a single protocol string, but some (like `g $addr`
    /// in monitor mode) expand to a sequence — e.g. set PC then resume.
    ///
    /// - Parameters:
    ///   - line: The user's input line.
    ///   - mode: The current REPL mode.
    /// - Returns: An array of CLI protocol command strings to send in order.
    static func translateToProtocol(line: String, mode: SocketREPLMode) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Handle dot commands
        if trimmed.hasPrefix(".") {
            let lowerTrimmed = trimmed.lowercased()
            switch lowerTrimmed {
            case ".status":
                return ["status"]
            case ".screen":
                return ["screen"]
            case ".reset":
                return ["reset cold"]
            case ".warmstart":
                return ["reset warm"]
            case ".screenshot":
                return ["screenshot"]
            default:
                // Handle .screenshot with path
                if lowerTrimmed.hasPrefix(".screenshot ") {
                    let path = String(trimmed.dropFirst(12))
                    return ["screenshot \(path)"]
                }
                // Handle .state save/load
                if lowerTrimmed.hasPrefix(".state save ") {
                    let path = String(trimmed.dropFirst(12))
                    return ["state save \(path)"]
                } else if lowerTrimmed.hasPrefix(".state load ") {
                    let path = String(trimmed.dropFirst(12))
                    return ["state load \(path)"]
                }
                // Handle .boot <path>
                if lowerTrimmed.hasPrefix(".boot ") {
                    let path = String(trimmed.dropFirst(6))
                    return ["boot \(path)"]
                }
            }
        }

        // Mode-specific command translation
        switch mode {
        case .monitor:
            return translateMonitorCommand(trimmed)
        case .basic:
            return [translateBASICCommand(trimmed)]
        case .dos:
            return [translateDOSCommand(trimmed)]
        }
    }

    /// Translates a monitor mode command.
    ///
    /// Most commands produce a single protocol string, but `g $addr` expands
    /// to two commands: set the program counter, then resume execution.
    static func translateMonitorCommand(_ cmd: String) -> [String] {
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first else { return [cmd] }

        let cmdLower = String(command).lowercased()
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch cmdLower {
        case "g":
            if args.isEmpty {
                return ["resume"]
            }
            // g $addr -> set PC first, then resume
            return ["registers pc=\(args)", "resume"]
        case "s", "step":
            return args.isEmpty ? ["step"] : ["step \(args)"]
        case "p", "pause":
            return ["pause"]
        case "r", "registers":
            return args.isEmpty ? ["registers"] : ["registers \(args)"]
        case "m", "memory":
            // m $0600 16 -> read $0600 16
            return ["read \(args)"]
        case ">":
            // > $0600 A9,00 -> write $0600 A9,00
            return ["write \(args)"]
        case "d", "disassemble":
            // TODO: Not yet implemented
            return ["disassemble \(args)"]
        case "b", "breakpoint":
            return ["breakpoint \(args)"]
        default:
            return [cmd]
        }
    }

    /// Translates a BASIC mode command.
    ///
    /// Recognizes special commands (list, run, new) and translates them to
    /// protocol commands. Everything else is sent as injected keystrokes.
    static func translateBASICCommand(_ cmd: String) -> String {
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let keyword = parts.first.map { String($0).uppercased() } ?? ""
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch keyword {
        // Read-only listing via protocol (detokenizer, not screen scrape)
        case "LIST":
            // Forward optional range arguments (e.g. "10", "10-50", "10-", "-50")
            // along with the ATASCII flag to the server protocol command.
            var result = "basic list"
            if !args.isEmpty { result += " \(args)" }
            if atasciiMode { result += " atascii" }
            return result

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
        case "RENUM", "RENUMBER":
            return args.isEmpty ? "basic renum" : "basic renum \(args)"
        case "SAVE":
            guard !args.isEmpty else { return "basic save" }  // let server report error
            return "basic save \(args)"
        case "LOAD":
            guard !args.isEmpty else { return "basic load" }  // let server report error
            return "basic load \(args)"

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
    ///
    /// DOS commands are prefixed with `dos ` for the protocol, mirroring
    /// how BASIC commands are prefixed with `basic `. The three original
    /// disk commands (mount, unmount, drives) remain at the top level
    /// since they're shared across modes.
    static func translateDOSCommand(_ cmd: String) -> String {
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first else { return cmd }

        let cmdLower = String(command).lowercased()
        let args = parts.count > 1 ? String(parts[1]) : ""

        switch cmdLower {
        // Top-level disk commands (shared, not DOS-prefixed)
        case "mount":
            return "mount \(args)"
        case "unmount", "umount":
            return "unmount \(args)"
        case "drives":
            return "drives"

        // DOS mode commands — prefixed with "dos" for the protocol
        case "cd":
            return "dos cd \(args)"
        case "dir":
            return args.isEmpty ? "dos dir" : "dos dir \(args)"
        case "info":
            return "dos info \(args)"
        case "type":
            return "dos type \(args)"
        case "dump":
            return "dos dump \(args)"
        case "copy", "cp":
            return "dos copy \(args)"
        case "rename", "ren":
            return "dos rename \(args)"
        case "delete", "del":
            return "dos delete \(args)"
        case "lock":
            return "dos lock \(args)"
        case "unlock":
            return "dos unlock \(args)"
        case "export":
            return "dos export \(args)"
        case "import":
            return "dos import \(args)"
        case "newdisk":
            return "dos newdisk \(args)"
        case "format":
            return "dos format"

        default:
            return cmd
        }
    }

    /// Parses a hex address string like "$0600" into a UInt16.
    ///
    /// - Parameter str: The hex address string (must have "$" prefix).
    /// - Returns: The parsed address, or nil if invalid.
    static func parseHexAddress(_ str: String) -> UInt16? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("$") else { return nil }
        return UInt16(trimmed.dropFirst(), radix: 16)
    }

    /// Prints help for the current mode, or detailed help for a specific command.
    ///
    /// When `topic` is nil, prints the full command listing for the mode.
    /// When a topic is given, looks it up in the global and mode-specific help
    /// dictionaries and prints the detailed text.
    static func printHelp(mode: SocketREPLMode, topic: String?) {
        // If no topic, show the full listing
        guard let topic = topic, !topic.isEmpty else {
            printHelpOverview(mode: mode)
            return
        }

        // Normalize: strip leading dot for global commands, lowercase
        let key = topic.lowercased().hasPrefix(".") ?
            String(topic.lowercased().dropFirst()) : topic.lowercased()

        // Check global commands first, then mode-specific
        if let text = globalHelp[key] {
            print(text)
        } else if let text = modeHelp(for: mode)[key] {
            print(text)
        } else {
            printError("No help for '\(topic)'. Type .help to see available commands.")
        }
    }

    /// Prints the full command listing (original .help behavior).
    private static func printHelpOverview(mode: SocketREPLMode) {
        print("""
        Global Commands:
          .monitor          Switch to monitor mode
          .basic            Switch to BASIC mode
          .dos              Switch to DOS mode
          .help [cmd]       Show help (or help for a specific command)
          .status           Show emulator status
          .screenshot [p]   Save screenshot (default: ~/Desktop/Attic-<time>.png)
          .screen           Read screen text (GRAPHICS 0 only)
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
              a <addr>          Interactive assembly (enter instructions line by line)
              a <addr> <instr>  Assemble single instruction
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
              renum [s] [step]  Renumber lines (default: start 10, step 10)
              info              Show program size (lines, bytes, variables)
              vars              List all variables with values
              var <name>        Show single variable (e.g. var X, var A$)
              stop              Send BREAK to stop running program
              cont              Continue after BREAK
              save D:FILE       Save program to ATR disk (e.g. save D:TEST)
              load D:FILE       Load program from ATR disk (e.g. load D:TEST)
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
              cd <n>            Change current drive (1-8)
              dir [pattern]     List directory (e.g. dir *.COM)
              info <file>       Show file details (size, sectors, locked)
              type <file>       Display text file contents
              dump <file>       Hex dump of file contents
              copy <src> <dst>  Copy file (e.g. copy D1:FILE D2:FILE)
              rename <old> <new> Rename a file
              delete <file>     Delete a file
              lock <file>       Lock file (read-only)
              unlock <file>     Unlock file
              export <f> <path> Export disk file to host filesystem
              import <path> <f> Import host file to disk
              newdisk <p> [type] Create new ATR (type: sd, ed, dd)
              format            Format current drive (erases all data!)
            """)
        }
    }

    // =========================================================================
    // MARK: - Topic-Specific Help Text
    // =========================================================================

    /// Detailed help for global dot-commands (keys without leading dot).
    private static let globalHelp: [String: String] = [
        "monitor": """
          .monitor
            Switch to monitor mode for 6502 debugging.
            Provides disassembly, breakpoints, memory inspection, and
            register manipulation.
          """,
        "basic": """
          .basic
            Switch to BASIC mode for writing and running Atari BASIC programs.
            Numbered lines are tokenized and injected into emulator memory.
            Non-numbered input is typed into the emulator as keystrokes.
          """,
        "dos": """
          .dos
            Switch to DOS mode for disk image management.
            Mount, browse, and manipulate ATR disk images and their files.
          """,
        "help": """
          .help [command]
            Show help for all commands, or detailed help for a specific command.
            Examples:
              .help           Show full command listing for current mode
              .help mount     Show detailed help for the mount command
              .help g         Show detailed help for the go command
              .help .boot     Show detailed help for the .boot command
          """,
        "status": """
          .status
            Show emulator status including running state, program counter,
            mounted disk drives, and active breakpoints.
          """,
        "screenshot": """
          .screenshot [path]
            Capture the emulator display as a PNG screenshot.
            If no path is given, saves to ~/Desktop/Attic-<timestamp>.png.
            Examples:
              .screenshot
              .screenshot ~/captures/screen.png
          """,
        "screen": """
          .screen
            Read the text currently displayed on the Atari GRAPHICS 0 screen.
            Returns the 40x24 character text screen as plain text.
            Only works when the emulator is in text mode (GRAPHICS 0).
          """,
        "boot": """
          .boot <path>
            Boot the emulator with a file. Supported formats:
              .ATR  - Disk image (mounted to D1: and booted)
              .XEX  - Executable (loaded and run)
              .BAS  - BASIC program (loaded into BASIC)
              .CAS  - Cassette image
              .ROM  - Cartridge ROM
            Example:
              .boot ~/games/StarRaiders.atr
          """,
        "reset": """
          .reset
            Perform a cold reset of the emulator. Reinitializes all hardware
            and clears memory. Equivalent to powering off and on.
          """,
        "warmstart": """
          .warmstart
            Perform a warm reset. Equivalent to pressing the RESET key on
            the Atari. Preserves memory contents but resets the CPU.
          """,
        "state": """
          .state save <path>
          .state load <path>
            Save or load the complete emulator state (CPU, memory, hardware).
            Examples:
              .state save ~/saves/game.state
              .state load ~/saves/game.state
          """,
        "quit": """
          .quit
            Disconnect from the server and exit the CLI.
            If the server was launched by this CLI session, it keeps running.
          """,
        "shutdown": """
          .shutdown
            Disconnect and stop the server. If this CLI session launched
            the server, sends SIGTERM to terminate it. If the server was
            already running, only disconnects (leaves the server running).
          """,
    ]

    /// Returns the help dictionary for mode-specific commands.
    private static func modeHelp(for mode: SocketREPLMode) -> [String: String] {
        switch mode {
        case .monitor: return monitorHelp
        case .basic: return basicHelp
        case .dos: return dosHelp
        }
    }

    /// Detailed help for monitor mode commands.
    private static let monitorHelp: [String: String] = [
        "g": """
          g [addr]
            Resume execution from the current PC, or from a specified address.
            If an address is given, sets PC before resuming.
            Examples:
              g             Resume from current PC
              g $E000       Set PC to $E000 and resume
          """,
        "s": """
          s [n]
            Step the emulator by n frames (default: 1).
            After stepping, displays the current register state.
            Examples:
              s             Step 1 frame
              s 10          Step 10 frames
          """,
        "step": """
          step [n]
            Alias for 's'. Step the emulator by n frames (default: 1).
          """,
        "p": """
          p
            Pause emulation. The emulator must be paused before writing
            memory or modifying CPU registers.
          """,
        "pause": """
          pause
            Alias for 'p'. Pause emulation.
          """,
        "r": """
          r [reg=val ...]
            Display CPU registers, or set one or more register values.
            Register names: A, X, Y, S (stack pointer), P (flags), PC.
            Examples:
              r                 Show all registers
              r a=42            Set accumulator to $42
              r pc=E000 a=00    Set PC and A
          """,
        "registers": """
          registers [reg=val ...]
            Alias for 'r'. Display or set CPU registers.
          """,
        "m": """
          m <addr> [len]
            Dump memory starting at addr for len bytes (default: 16).
            Address must be prefixed with $.
            Examples:
              m $0600           Dump 16 bytes at $0600
              m $D000 64        Dump 64 bytes at $D000
          """,
        "memory": """
          memory <addr> [len]
            Alias for 'm'. Dump memory contents.
          """,
        ">": """
          > <addr> <bytes>
            Write bytes to memory. Emulator must be paused first.
            Bytes are comma-separated hex values.
            Examples:
              > $0600 A9,00,8D,00,D4    Write 5 bytes at $0600
          """,
        "a": """
          a <addr> [instruction]
            Assemble 6502 code. Two modes:
              a $0600             Enter interactive assembly (line by line)
              a $0600 LDA #$42   Assemble a single instruction
            In interactive mode, enter one instruction per line.
            Enter a blank line to exit.
            Examples:
              a $0600
              a $0600 NOP
              a $0600 JMP $E459
          """,
        "b": """
          b <set|clear|list> [addr]
            Manage breakpoints using the 6502 BRK instruction.
            Examples:
              b set $0600       Set breakpoint at $0600
              b clear $0600     Clear breakpoint at $0600
              b list            List all active breakpoints
          """,
        "breakpoint": """
          breakpoint <set|clear|list> [addr]
            Alias for 'b'. Manage breakpoints.
          """,
        "d": """
          d [addr] [lines]
            Disassemble 6502 code starting at addr.
            If no address given, disassembles from current PC.
            Examples:
              d                 Disassemble 16 lines from PC
              d $E000           Disassemble from $E000
              d $E000 32        Disassemble 32 lines from $E000
          """,
        "disassemble": """
          disassemble [addr] [lines]
            Alias for 'd'. Disassemble 6502 code.
          """,
    ]

    /// Detailed help for BASIC mode commands.
    private static let basicHelp: [String: String] = [
        "list": """
          list [range]
            List the BASIC program in memory using the detokenizer.
            Optionally specify a line range.
            Examples:
              list              List entire program
              list 10-50        List lines 10 through 50
          """,
        "del": """
          del <line|range>
            Delete a single line or a range of lines.
            Examples:
              del 30            Delete line 30
              del 10-50         Delete lines 10 through 50
          """,
        "renum": """
          renum [start] [step]
            Renumber all program lines. Default start is 10, step is 10.
            Updates GOTO/GOSUB references automatically.
            Examples:
              renum             Renumber 10, 20, 30, ...
              renum 100 5       Renumber 100, 105, 110, ...
          """,
        "info": """
          info
            Show program statistics: number of lines, total bytes used,
            and variable count.
          """,
        "vars": """
          vars
            List all BASIC variables with their current values.
            Shows variable name, type (numeric, string, array), and value.
          """,
        "var": """
          var <name>
            Show a single variable's value.
            Examples:
              var X             Show numeric variable X
              var A$            Show string variable A$
          """,
        "stop": """
          stop
            Send BREAK to stop a running BASIC program.
            The program can be continued with 'cont'.
          """,
        "cont": """
          cont
            Continue execution after a BREAK or STOP statement.
          """,
        "save": """
          save D:FILE
            Save the current BASIC program to a mounted ATR disk.
            The file spec must include the drive prefix (D: or D1: etc).
            Examples:
              save D:TEST       Save as TEST on current drive
              save D2:GAME      Save as GAME on drive 2
          """,
        "load": """
          load D:FILE
            Load a BASIC program from a mounted ATR disk.
            Examples:
              load D:TEST       Load TEST from current drive
              load D2:GAME      Load GAME from drive 2
          """,
        "export": """
          export <path>
            Export the current BASIC listing to a host filesystem file.
            Example:
              export ~/programs/myprog.bas
          """,
        "import": """
          import <path>
            Import a BASIC listing from a host filesystem file.
            Lines are tokenized and loaded into emulator memory.
            Example:
              import ~/programs/myprog.bas
          """,
        "dir": """
          dir [drive]
            List the directory of a mounted disk. Defaults to current drive.
            Examples:
              dir               List current drive
              dir 2             List drive 2
          """,
    ]

    /// Detailed help for DOS mode commands.
    private static let dosHelp: [String: String] = [
        "mount": """
          mount <n> <path>
            Mount an ATR disk image to drive n (1-8).
            Examples:
              mount 1 ~/disks/dos.atr
              mount 2 ~/disks/game.atr
          """,
        "unmount": """
          unmount <n>
            Unmount the disk image from drive n.
            Example:
              unmount 2
          """,
        "drives": """
          drives
            List all drive slots (D1: through D8:) and their mounted images.
          """,
        "cd": """
          cd <n>
            Change the current working drive (1-8).
            Subsequent commands like dir, type, etc. use this drive.
            Example:
              cd 2
          """,
        "dir": """
          dir [pattern]
            List the directory of the current drive.
            Optional glob pattern filters results.
            Examples:
              dir               List all files
              dir *.COM         List only .COM files
          """,
        "info": """
          info <file>
            Show detailed information about a file: size in bytes,
            sector count, and whether it's locked.
            Example:
              info AUTORUN.SYS
          """,
        "type": """
          type <file>
            Display the contents of a text file.
            Example:
              type README.TXT
          """,
        "dump": """
          dump <file>
            Show a hex dump of a file's contents, with both hex bytes
            and ASCII representation.
            Example:
              dump GAME.COM
          """,
        "copy": """
          copy <source> <dest>
            Copy a file. Use drive prefixes for cross-drive copies.
            Examples:
              copy D1:FILE.COM D2:FILE.COM
              copy GAME.BAS BACKUP.BAS
          """,
        "rename": """
          rename <old> <new>
            Rename a file on the current drive.
            Example:
              rename OLDNAME.BAS NEWNAME.BAS
          """,
        "delete": """
          delete <file>
            Delete a file from the current drive.
            Example:
              delete TEMP.DAT
          """,
        "lock": """
          lock <file>
            Lock a file (make it read-only).
            Example:
              lock IMPORTANT.DAT
          """,
        "unlock": """
          unlock <file>
            Unlock a previously locked file.
            Example:
              unlock IMPORTANT.DAT
          """,
        "export": """
          export <file> <path>
            Export a file from the ATR disk to the host filesystem.
            Example:
              export GAME.BAS ~/exports/game.bas
          """,
        "import": """
          import <path> <file>
            Import a file from the host filesystem into the ATR disk.
            Example:
              import ~/programs/game.bas GAME.BAS
          """,
        "newdisk": """
          newdisk <path> [type]
            Create a new blank ATR disk image. Type can be:
              sd   Single density (90KB, 720 sectors)
              ed   Enhanced density (130KB, 1040 sectors)
              dd   Double density (180KB, 720 sectors)
            Default is single density.
            Example:
              newdisk ~/disks/blank.atr dd
          """,
        "format": """
          format
            Format the current drive, erasing all data.
            This writes a fresh directory and VTOC to the disk.
            WARNING: All existing data on the disk will be lost!
          """,
    ]

    // =========================================================================
    // MARK: - Socket Connection
    // =========================================================================

    /// The socket client for CLI communication.
    @MainActor static var socketClient: CLISocketClient?

    /// PID of the server process if this CLI session launched it.
    /// Nil means the server was already running when we connected.
    /// Access is sequential: set during launch (before REPL), read on shutdown.
    nonisolated(unsafe) static var launchedServerPid: Int32?

    /// Whether rich ATASCII rendering is enabled for this session.
    /// Set once during argument parsing (before REPL), read during command translation.
    /// Defaults to true so inverse video and ATASCII graphics render correctly.
    nonisolated(unsafe) static var atasciiMode: Bool = true

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
    /// - Parameter silent: Whether to disable audio.
    /// - Returns: The socket path if successful, nil otherwise.
    static func launchServer(silent: Bool) -> String? {
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

        // Store session-wide ATASCII rendering preference
        atasciiMode = args.atascii

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
            socketPath = launchServer(silent: args.silent)

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
