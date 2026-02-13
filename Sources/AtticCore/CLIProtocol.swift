// =============================================================================
// CLIProtocol.swift - Text-Based CLI Protocol for REPL Communication
// =============================================================================
//
// This file defines the text-based protocol used for communication between
// the CLI (attic) and the AtticServer. Unlike AESP (the binary protocol for
// GUI/web clients), the CLI protocol is designed for:
//
// - Emacs comint-mode compatibility
// - Human-readable text format
// - Simple line-based parsing
// - REPL-style interaction
//
// Protocol Format:
// ----------------
// Request (CLI -> Server):   CMD:<command> [arguments...]\n
// Success Response:          OK:<response-data>\n
// Error Response:            ERR:<error-message>\n
// Async Event:               EVENT:<event-type> <data>\n
// Multi-line Separator:      \x1E (Record Separator)
//
// Example Session:
//   CLI: CMD:ping
//   SRV: OK:pong
//   CLI: CMD:pause
//   SRV: OK:paused
//   CLI: CMD:read $0600 16
//   SRV: OK:data A9,00,8D,00,D4,A9,01,8D,01,D4,60,00,00,00,00,00
//
// Socket Location:
//   /tmp/attic-<pid>.sock
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Protocol Constants
// =============================================================================

/// Constants for the CLI protocol.
public enum CLIProtocolConstants {
    /// Prefix for commands (CLI -> Server).
    public static let commandPrefix = "CMD:"

    /// Prefix for success responses (Server -> CLI).
    public static let okPrefix = "OK:"

    /// Prefix for error responses (Server -> CLI).
    public static let errorPrefix = "ERR:"

    /// Prefix for async events (Server -> CLI).
    public static let eventPrefix = "EVENT:"

    /// Multi-line separator (Record Separator character).
    public static let multiLineSeparator = "\u{1E}"

    /// Socket path prefix for discovery.
    public static let socketPathPrefix = "/tmp/attic-"

    /// Socket path suffix.
    public static let socketPathSuffix = ".sock"

    /// Maximum line length in bytes.
    public static let maxLineLength = 4096

    /// Command timeout in seconds.
    public static let commandTimeout: TimeInterval = 30.0

    /// Ping timeout in seconds.
    public static let pingTimeout: TimeInterval = 1.0

    /// Connection timeout in seconds.
    public static let connectionTimeout: TimeInterval = 5.0

    /// Protocol version string.
    public static let protocolVersion = "1.0"

    /// Generates the socket path for a given process ID.
    public static func socketPath(for pid: pid_t) -> String {
        "\(socketPathPrefix)\(pid)\(socketPathSuffix)"
    }

    /// Returns the socket path for the current process.
    public static var currentSocketPath: String {
        socketPath(for: getpid())
    }
}

// =============================================================================
// MARK: - CLI Command Types
// =============================================================================

/// Represents a parsed CLI command.
///
/// These commands are a subset of what the REPL supports, focused on
/// the commands that make sense over a socket connection. They map
/// closely to the protocol specification in docs/PROTOCOL.md.
public enum CLICommand: Sendable {
    // Connection
    case ping
    case version
    case quit
    case shutdown

    // Emulator control
    case pause
    case resume
    case step(count: Int)
    case reset(cold: Bool)
    case status

    // Memory operations
    case read(address: UInt16, count: UInt16)
    case write(address: UInt16, data: [UInt8])
    case registers(modifications: [(String, UInt16)]?)

    // Breakpoints
    case breakpointSet(address: UInt16)
    case breakpointClear(address: UInt16)
    case breakpointClearAll
    case breakpointList

    // Assembly
    case assemble(address: UInt16)
    case assembleLine(address: UInt16, instruction: String)
    /// Feed an instruction to the active interactive assembly session.
    case assembleInput(instruction: String)
    /// End the active interactive assembly session.
    case assembleEnd

    // Step over
    case stepOver

    // Run until
    case runUntil(address: UInt16)

    // Memory fill
    case memoryFill(start: UInt16, end: UInt16, value: UInt8)

    // Disk operations
    case mount(drive: Int, path: String)
    case unmount(drive: Int)
    case drives

    // Boot with file
    /// Boot the emulator with a file (ATR, XEX, BAS, LST, CAS, ROM, etc.).
    /// Calls libatari800_reboot_with_file which loads the file and cold-starts.
    case boot(path: String)

    // State management
    case stateSave(path: String)
    case stateLoad(path: String)

    // Display
    case screenshot(path: String?)
    /// Read the text displayed on the GRAPHICS 0 screen as a string.
    case screenText

    // BASIC injection
    case injectBasic(base64Data: String)
    case injectKeys(text: String)

    // Disassembly
    /// Disassemble memory at the specified address for the given number of lines.
    /// If address is nil, disassemble from the current PC.
    /// If lines is nil, default to 16 lines.
    case disassemble(address: UInt16?, lines: Int?)

    // BASIC line entry (tokenization and injection)
    case basicLine(line: String)
    case basicNew
    case basicRun
    /// List the BASIC program. When `atascii` is true, the listing uses
    /// ANSI reverse video and Unicode glyphs for ATASCII graphics characters.
    case basicList(atascii: Bool)

    // BASIC editing commands
    /// Delete a BASIC line or range of lines (e.g., "10" or "10-50").
    case basicDelete(lineOrRange: String)
    /// Stop a running BASIC program (equivalent to pressing BREAK).
    case basicStop
    /// Continue execution of a stopped BASIC program.
    case basicCont
    /// List all BASIC variables and their current values.
    case basicVars
    /// Show value and type of a specific BASIC variable.
    case basicVar(name: String)
    /// Show information about the current BASIC program (size, line count, etc.).
    case basicInfo
    /// Export the current BASIC program to a file. Path is tilde-expanded.
    case basicExport(path: String)
    /// Import a BASIC program from a file. Path is tilde-expanded.
    case basicImport(path: String)
    /// List files on a disk drive (1-8). Nil means the default drive.
    case basicDir(drive: Int?)
    /// Renumber BASIC program lines, optionally specifying start and step.
    case basicRenumber(start: Int?, step: Int?)
    /// Save tokenized BASIC program to an ATR disk file.
    case basicSave(drive: Int?, filename: String)
    /// Load tokenized BASIC program from an ATR disk file.
    case basicLoad(drive: Int?, filename: String)

    // DOS mode commands — file and disk management via DiskManager.
    // These map to the same operations available in the old direct-REPL
    // DOS mode, but routed through the CLI socket protocol.

    /// Change the current drive (1-8).
    case dosChangeDrive(drive: Int)
    /// List directory contents, optionally filtered by a wildcard pattern.
    case dosDirectory(pattern: String?)
    /// Show detailed file information (size, sectors, locked status, etc.).
    case dosFileInfo(filename: String)
    /// Display a text file's contents (ATASCII decoded).
    case dosType(filename: String)
    /// Display a hex dump of a file's contents.
    case dosDump(filename: String)
    /// Copy a file between drives (e.g., "D1:FILE D2:FILE").
    case dosCopy(source: String, destination: String)
    /// Rename a file on the current drive.
    case dosRename(oldName: String, newName: String)
    /// Delete a file from the current drive.
    case dosDelete(filename: String)
    /// Lock a file (set read-only flag in directory).
    case dosLock(filename: String)
    /// Unlock a file (clear read-only flag in directory).
    case dosUnlock(filename: String)
    /// Export a file from ATR disk to the host filesystem.
    case dosExport(filename: String, hostPath: String)
    /// Import a file from the host filesystem to ATR disk.
    case dosImport(hostPath: String, filename: String)
    /// Create a new blank ATR disk image. Type is "sd", "ed", or "dd".
    case dosNewDisk(path: String, type: String?)
    /// Format the current drive (erases all data).
    case dosFormat
}

// =============================================================================
// MARK: - CLI Response Types
// =============================================================================

/// Represents a response to a CLI command.
public enum CLIResponse: Sendable {
    /// Success response with optional data.
    case ok(String)

    /// Error response with message.
    case error(String)

    /// Formats the response for transmission.
    public var formatted: String {
        switch self {
        case .ok(let data):
            return "\(CLIProtocolConstants.okPrefix)\(data)"
        case .error(let message):
            return "\(CLIProtocolConstants.errorPrefix)\(message)"
        }
    }

    /// Creates an OK response with multiple lines joined by the separator.
    public static func okMultiLine(_ lines: [String]) -> CLIResponse {
        .ok(lines.joined(separator: CLIProtocolConstants.multiLineSeparator))
    }
}

// =============================================================================
// MARK: - CLI Event Types
// =============================================================================

/// Represents an asynchronous event from the server.
public enum CLIEvent: Sendable {
    /// Breakpoint was hit at the specified address with register state.
    case breakpoint(address: UInt16, a: UInt8, x: UInt8, y: UInt8, s: UInt8, p: UInt8)

    /// Emulator stopped (e.g., BRK without breakpoint).
    case stopped(address: UInt16)

    /// Async error occurred.
    case error(message: String)

    /// Formats the event for transmission.
    public var formatted: String {
        switch self {
        case .breakpoint(let addr, let a, let x, let y, let s, let p):
            return "\(CLIProtocolConstants.eventPrefix)breakpoint $\(hex4(addr)) A=$\(hex2(a)) X=$\(hex2(x)) Y=$\(hex2(y)) S=$\(hex2(s)) P=$\(hex2(p))"
        case .stopped(let addr):
            return "\(CLIProtocolConstants.eventPrefix)stopped $\(hex4(addr))"
        case .error(let message):
            return "\(CLIProtocolConstants.eventPrefix)error \(message)"
        }
    }

    private func hex2(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }

    private func hex4(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }
}

// =============================================================================
// MARK: - CLI Command Parser
// =============================================================================

/// Parses CLI protocol commands from text lines.
///
/// The parser handles the text format specified in docs/PROTOCOL.md,
/// converting command strings into CLICommand values.
public struct CLICommandParser: Sendable {
    public init() {}

    /// Parses a command line into a CLICommand.
    ///
    /// - Parameter line: The raw command line (with or without CMD: prefix).
    /// - Returns: The parsed command.
    /// - Throws: CLIProtocolError if parsing fails.
    public func parse(_ line: String) throws -> CLICommand {
        // Strip CMD: prefix if present
        var commandLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if commandLine.hasPrefix(CLIProtocolConstants.commandPrefix) {
            commandLine = String(commandLine.dropFirst(CLIProtocolConstants.commandPrefix.count))
        }

        // Check line length
        guard commandLine.count <= CLIProtocolConstants.maxLineLength else {
            throw CLIProtocolError.lineTooLong
        }

        // Split into command and arguments
        let parts = commandLine.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let commandWord = parts.first else {
            throw CLIProtocolError.invalidCommand("")
        }

        let command = String(commandWord).lowercased()
        let argsString = parts.count > 1 ? String(parts[1]) : ""

        // Parse based on command word
        switch command {
        // Connection commands
        case "ping":
            return .ping
        case "version":
            return .version
        case "quit":
            return .quit
        case "shutdown":
            return .shutdown

        // Emulator control
        case "pause":
            return .pause
        case "resume":
            return .resume
        case "step":
            return try parseStep(argsString)
        case "reset":
            return try parseReset(argsString)
        case "status":
            return .status

        // Memory operations
        case "read":
            return try parseRead(argsString)
        case "write":
            return try parseWrite(argsString)
        case "registers":
            return try parseRegisters(argsString)

        // Breakpoints
        case "breakpoint":
            return try parseBreakpoint(argsString)

        // Disassembly
        case "disasm", "disassemble", "d":
            return try parseDisassemble(argsString)

        // Assembly
        case "asm", "assemble", "a":
            return try parseAssemble(argsString)

        // Step over
        case "stepover", "so":
            return .stepOver

        // Run until
        case "until", "rununtil":
            return try parseRunUntil(argsString)

        // Memory fill
        case "fill":
            return try parseFill(argsString)

        // Disk operations
        case "mount":
            return try parseMount(argsString)
        case "unmount":
            return try parseUnmount(argsString)
        case "drives":
            return .drives

        // Boot with file
        case "boot":
            return try parseBoot(argsString)

        // State management
        case "state":
            return try parseState(argsString)

        // Display
        case "screenshot":
            return .screenshot(path: argsString.isEmpty ? nil : argsString)
        case "screen":
            return .screenText

        // Injection
        case "inject":
            return try parseInject(argsString)

        // BASIC commands
        case "basic":
            return try parseBasic(argsString)

        // DOS mode commands
        case "dos":
            return try parseDOS(argsString)

        default:
            throw CLIProtocolError.invalidCommand(command)
        }
    }

    // MARK: - Individual Command Parsers

    private func parseStep(_ args: String) throws -> CLICommand {
        if args.isEmpty {
            return .step(count: 1)
        }
        guard let count = Int(args), count > 0 else {
            throw CLIProtocolError.invalidStepCount(args)
        }
        return .step(count: count)
    }

    private func parseReset(_ args: String) throws -> CLICommand {
        switch args.lowercased() {
        case "cold", "":
            return .reset(cold: true)
        case "warm":
            return .reset(cold: false)
        default:
            throw CLIProtocolError.invalidResetType(args)
        }
    }

    private func parseRead(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("read requires address and count")
        }

        guard let address = parseAddress(String(parts[0])) else {
            throw CLIProtocolError.invalidAddress(String(parts[0]))
        }

        guard let count = UInt16(parts[1]) else {
            throw CLIProtocolError.invalidCount(String(parts[1]))
        }

        return .read(address: address, count: count)
    }

    private func parseWrite(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("write requires address and data")
        }

        guard let address = parseAddress(String(parts[0])) else {
            throw CLIProtocolError.invalidAddress(String(parts[0]))
        }

        let dataStr = String(parts[1])
        var bytes: [UInt8] = []

        for byteStr in dataStr.split(separator: ",") {
            let trimmed = byteStr.trimmingCharacters(in: .whitespaces)
            guard let byte = parseHexByte(trimmed) else {
                throw CLIProtocolError.invalidByte(trimmed)
            }
            bytes.append(byte)
        }

        guard !bytes.isEmpty else {
            throw CLIProtocolError.missingArgument("write requires at least one byte")
        }

        return .write(address: address, data: bytes)
    }

    private func parseRegisters(_ args: String) throws -> CLICommand {
        if args.isEmpty {
            return .registers(modifications: nil)
        }

        var modifications: [(String, UInt16)] = []

        // Parse assignments like "A=$50 X=$10"
        for part in args.split(separator: " ", omittingEmptySubsequences: true) {
            let assignment = String(part)
            let components = assignment.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else {
                throw CLIProtocolError.invalidRegisterFormat(assignment)
            }

            let regName = String(components[0]).uppercased()
            guard ["A", "X", "Y", "S", "P", "PC"].contains(regName) else {
                throw CLIProtocolError.invalidRegister(regName)
            }

            guard let value = parseAddress(String(components[1])) else {
                throw CLIProtocolError.invalidValue(String(components[1]))
            }

            modifications.append((regName, value))
        }

        return .registers(modifications: modifications)
    }

    private func parseBreakpoint(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let subcommand = parts.first else {
            throw CLIProtocolError.missingArgument("breakpoint requires subcommand (set, clear, clearall, list)")
        }

        switch String(subcommand).lowercased() {
        case "set":
            guard parts.count > 1 else {
                throw CLIProtocolError.missingArgument("breakpoint set requires address")
            }
            guard let address = parseAddress(String(parts[1])) else {
                throw CLIProtocolError.invalidAddress(String(parts[1]))
            }
            return .breakpointSet(address: address)

        case "clear":
            guard parts.count > 1 else {
                throw CLIProtocolError.missingArgument("breakpoint clear requires address")
            }
            guard let address = parseAddress(String(parts[1])) else {
                throw CLIProtocolError.invalidAddress(String(parts[1]))
            }
            return .breakpointClear(address: address)

        case "clearall":
            return .breakpointClearAll

        case "list":
            return .breakpointList

        default:
            throw CLIProtocolError.invalidCommand("breakpoint \(subcommand)")
        }
    }

    private func parseAssemble(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard !parts.isEmpty else {
            throw CLIProtocolError.missingArgument("assemble requires address")
        }

        let firstWord = String(parts[0]).lowercased()

        // Check for interactive assembly session subcommands.
        // "input" and "end" are not valid hex addresses so there's no ambiguity
        // with the existing address-based parsing.
        if firstWord == "input" {
            guard parts.count > 1 else {
                throw CLIProtocolError.missingArgument("asm input requires an instruction")
            }
            return .assembleInput(instruction: String(parts[1]))
        }

        if firstWord == "end" {
            return .assembleEnd
        }

        guard let address = parseAddress(String(parts[0])) else {
            throw CLIProtocolError.invalidAddress(String(parts[0]))
        }

        // If there's an instruction on the same line, it's a single-line assembly
        if parts.count > 1 {
            let instruction = String(parts[1])
            return .assembleLine(address: address, instruction: instruction)
        }

        // Otherwise, start interactive assembly mode
        return .assemble(address: address)
    }

    private func parseRunUntil(_ args: String) throws -> CLICommand {
        guard !args.isEmpty else {
            throw CLIProtocolError.missingArgument("until requires address")
        }

        guard let address = parseAddress(args.trimmingCharacters(in: .whitespaces)) else {
            throw CLIProtocolError.invalidAddress(args)
        }

        return .runUntil(address: address)
    }

    private func parseFill(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else {
            throw CLIProtocolError.missingArgument("fill requires start, end, and value")
        }

        guard let start = parseAddress(String(parts[0])) else {
            throw CLIProtocolError.invalidAddress(String(parts[0]))
        }

        guard let end = parseAddress(String(parts[1])) else {
            throw CLIProtocolError.invalidAddress(String(parts[1]))
        }

        guard let value = parseHexByte(String(parts[2])) else {
            throw CLIProtocolError.invalidByte(String(parts[2]))
        }

        return .memoryFill(start: start, end: end, value: value)
    }

    private func parseMount(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("mount requires drive number and path")
        }

        guard let drive = Int(parts[0]), drive >= 1, drive <= 8 else {
            throw CLIProtocolError.invalidDriveNumber(String(parts[0]))
        }

        return .mount(drive: drive, path: String(parts[1]))
    }

    private func parseUnmount(_ args: String) throws -> CLICommand {
        guard let drive = Int(args), drive >= 1, drive <= 8 else {
            throw CLIProtocolError.invalidDriveNumber(args)
        }
        return .unmount(drive: drive)
    }

    /// Parses a `boot <path>` command.
    ///
    /// The path argument is required and may contain spaces. Tilde (~) is
    /// expanded to the user's home directory.
    private func parseBoot(_ args: String) throws -> CLICommand {
        let path = args.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            throw CLIProtocolError.missingArgument("boot requires a file path")
        }
        // Expand ~ to home directory for convenience
        let expandedPath = NSString(string: path).expandingTildeInPath
        return .boot(path: expandedPath)
    }

    private func parseState(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let subcommand = parts.first else {
            throw CLIProtocolError.missingArgument("state requires subcommand (save or load)")
        }

        guard parts.count > 1 else {
            throw CLIProtocolError.missingArgument("state \(subcommand) requires path")
        }

        let path = String(parts[1])

        switch String(subcommand).lowercased() {
        case "save":
            return .stateSave(path: path)
        case "load":
            return .stateLoad(path: path)
        default:
            throw CLIProtocolError.invalidCommand("state \(subcommand)")
        }
    }

    private func parseInject(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let subcommand = parts.first else {
            throw CLIProtocolError.missingArgument("inject requires subcommand (basic or keys)")
        }

        guard parts.count > 1 else {
            throw CLIProtocolError.missingArgument("inject \(subcommand) requires data")
        }

        let data = String(parts[1])

        switch String(subcommand).lowercased() {
        case "basic":
            return .injectBasic(base64Data: data)
        case "keys":
            return .injectKeys(text: parseEscapes(data))
        default:
            throw CLIProtocolError.invalidCommand("inject \(subcommand)")
        }
    }

    /// Parses a disassemble command.
    ///
    /// Syntax: `disassemble [address] [lines]`
    /// - If no address is given, disassembles from current PC.
    /// - If no line count is given, defaults to 16 lines.
    ///
    /// Examples:
    /// - `d` - Disassemble 16 lines from PC
    /// - `d $0600` - Disassemble 16 lines from $0600
    /// - `d $0600 8` - Disassemble 8 lines from $0600
    private func parseDisassemble(_ args: String) throws -> CLICommand {
        if args.isEmpty {
            // No arguments: disassemble from PC, 16 lines
            return .disassemble(address: nil, lines: nil)
        }

        let parts = args.split(separator: " ", omittingEmptySubsequences: true)

        // First argument is the address (optional)
        var address: UInt16?
        var lines: Int?

        if !parts.isEmpty {
            address = parseAddress(String(parts[0]))
            if address == nil {
                throw CLIProtocolError.invalidAddress(String(parts[0]))
            }
        }

        // Second argument is the line count (optional)
        if parts.count >= 2 {
            guard let count = Int(parts[1]), count > 0 else {
                throw CLIProtocolError.invalidCount(String(parts[1]))
            }
            lines = count
        }

        return .disassemble(address: address, lines: lines)
    }

    /// Parses BASIC subcommands.
    ///
    /// Recognized subcommands (case-insensitive): NEW, RUN, LIST, DEL, STOP,
    /// CONT, VARS, VAR, INFO, EXPORT, IMPORT, DIR. Anything else that starts
    /// with a digit falls through to `basicLine` (a numbered BASIC line).
    private func parseBasic(_ args: String) throws -> CLICommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            throw CLIProtocolError.missingArgument("basic requires a line or command")
        }

        // Split into first word and remaining argument text
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let firstWord = String(parts[0]).uppercased()
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        switch firstWord {
        case "NEW":
            return .basicNew
        case "RUN":
            return .basicRun
        case "LIST":
            let atascii = rest.uppercased() == "ATASCII"
            return .basicList(atascii: atascii)
        case "DEL":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic del requires a line number or range (e.g., 10 or 10-50)")
            }
            return .basicDelete(lineOrRange: rest)
        case "STOP":
            return .basicStop
        case "CONT":
            return .basicCont
        case "VARS":
            return .basicVars
        case "VAR":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic var requires a variable name")
            }
            return .basicVar(name: rest)
        case "INFO":
            return .basicInfo
        case "EXPORT":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic export requires a file path")
            }
            let expandedPath = NSString(string: rest).expandingTildeInPath
            return .basicExport(path: expandedPath)
        case "IMPORT":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic import requires a file path")
            }
            let expandedPath = NSString(string: rest).expandingTildeInPath
            return .basicImport(path: expandedPath)
        case "DIR":
            if rest.isEmpty {
                return .basicDir(drive: nil)
            }
            guard let drive = Int(rest), drive >= 1, drive <= 8 else {
                throw CLIProtocolError.invalidDriveNumber(rest)
            }
            return .basicDir(drive: drive)
        case "RENUM", "RENUMBER":
            return try parseBasicRenum(rest)
        case "SAVE":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic save requires a filename (e.g., D:TEST or D2:FILE)")
            }
            let (drive, filename) = parseDrivePrefix(rest)
            return .basicSave(drive: drive, filename: filename)
        case "LOAD":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("basic load requires a filename (e.g., D:TEST or D2:FILE)")
            }
            let (drive, filename) = parseDrivePrefix(rest)
            return .basicLoad(drive: drive, filename: filename)
        default:
            // Anything else is a numbered BASIC line (e.g., "10 PRINT X")
            return .basicLine(line: trimmed)
        }
    }

    // MARK: - BASIC Command Helpers

    /// Parses the RENUM subcommand arguments.
    ///
    /// Formats:
    /// - `RENUM` - renumber with defaults (start=10, step=10)
    /// - `RENUM 100` - start at 100, step=10
    /// - `RENUM 100 20` - start at 100, step 20
    private func parseBasicRenum(_ args: String) throws -> CLICommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .basicRenumber(start: nil, step: nil)
        }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard let start = Int(parts[0]), start >= 0 else {
            throw CLIProtocolError.invalidValue(String(parts[0]))
        }

        var step: Int? = nil
        if parts.count > 1 {
            guard let s = Int(parts[1]), s > 0 else {
                throw CLIProtocolError.invalidValue(String(parts[1]))
            }
            step = s
        }

        return .basicRenumber(start: start, step: step)
    }

    // MARK: - DOS Command Parser

    /// Parses DOS subcommands for disk and file operations.
    ///
    /// Recognized subcommands (case-insensitive): CD, DIR, INFO, TYPE, DUMP,
    /// COPY, RENAME, DELETE, LOCK, UNLOCK, EXPORT, IMPORT, NEWDISK, FORMAT.
    private func parseDOS(_ args: String) throws -> CLICommand {
        let trimmed = args.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            throw CLIProtocolError.missingArgument("dos requires a subcommand (cd, dir, info, type, dump, copy, rename, delete, lock, unlock, export, import, newdisk, format)")
        }

        // Split into subcommand and remaining argument text
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let subcommand = String(parts[0]).uppercased()
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        switch subcommand {
        case "CD":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos cd requires a drive number (1-8)")
            }
            guard let drive = Int(rest), drive >= 1, drive <= 8 else {
                throw CLIProtocolError.invalidDriveNumber(rest)
            }
            return .dosChangeDrive(drive: drive)

        case "DIR":
            return .dosDirectory(pattern: rest.isEmpty ? nil : rest)

        case "INFO":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos info requires a filename")
            }
            return .dosFileInfo(filename: rest)

        case "TYPE":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos type requires a filename")
            }
            return .dosType(filename: rest)

        case "DUMP":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos dump requires a filename")
            }
            return .dosDump(filename: rest)

        case "COPY":
            return try parseDOSCopy(rest)

        case "RENAME":
            return try parseDOSRename(rest)

        case "DELETE", "DEL":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos delete requires a filename")
            }
            return .dosDelete(filename: rest)

        case "LOCK":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos lock requires a filename")
            }
            return .dosLock(filename: rest)

        case "UNLOCK":
            guard !rest.isEmpty else {
                throw CLIProtocolError.missingArgument("dos unlock requires a filename")
            }
            return .dosUnlock(filename: rest)

        case "EXPORT":
            return try parseDOSExport(rest)

        case "IMPORT":
            return try parseDOSImport(rest)

        case "NEWDISK":
            return try parseDOSNewDisk(rest)

        case "FORMAT":
            return .dosFormat

        default:
            throw CLIProtocolError.invalidCommand("dos \(subcommand)")
        }
    }

    /// Parses `dos copy <source> <destination>`.
    ///
    /// Both source and destination can include drive prefixes (e.g., D1:FILE).
    /// Example: `dos copy D1:GAME.BAS D2:GAME.BAS`
    private func parseDOSCopy(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("dos copy requires source and destination (e.g., D1:FILE D2:FILE)")
        }
        return .dosCopy(source: String(parts[0]), destination: String(parts[1]))
    }

    /// Parses `dos rename <oldname> <newname>`.
    private func parseDOSRename(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("dos rename requires old name and new name")
        }
        return .dosRename(oldName: String(parts[0]), newName: String(parts[1]))
    }

    /// Parses `dos export <filename> <hostpath>`.
    ///
    /// Exports a file from the ATR disk image to the host filesystem.
    /// The host path is tilde-expanded.
    private func parseDOSExport(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("dos export requires filename and host path")
        }
        let hostPath = NSString(string: String(parts[1])).expandingTildeInPath
        return .dosExport(filename: String(parts[0]), hostPath: hostPath)
    }

    /// Parses `dos import <hostpath> <filename>`.
    ///
    /// Imports a file from the host filesystem to the ATR disk image.
    /// The host path is tilde-expanded.
    private func parseDOSImport(_ args: String) throws -> CLICommand {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw CLIProtocolError.missingArgument("dos import requires host path and filename")
        }
        let hostPath = NSString(string: String(parts[0])).expandingTildeInPath
        return .dosImport(hostPath: hostPath, filename: String(parts[1]))
    }

    /// Parses `dos newdisk <path> [type]`.
    ///
    /// Creates a new blank ATR disk image. Type is optional:
    /// - "sd" (default) — single density 90KB
    /// - "ed" — enhanced density 130KB
    /// - "dd" — double density 180KB
    ///
    /// The path is tilde-expanded.
    private func parseDOSNewDisk(_ args: String) throws -> CLICommand {
        guard !args.isEmpty else {
            throw CLIProtocolError.missingArgument("dos newdisk requires a file path")
        }

        let parts = args.split(separator: " ", omittingEmptySubsequences: true)

        // Last token might be a disk type (sd, ed, dd)
        var type: String? = nil
        var pathParts = parts

        if parts.count >= 2 {
            let lastPart = String(parts.last!).lowercased()
            if ["sd", "ed", "dd"].contains(lastPart) {
                type = lastPart
                pathParts = parts.dropLast()
            }
        }

        let path = NSString(string: pathParts.map(String.init).joined(separator: " ")).expandingTildeInPath
        return .dosNewDisk(path: path, type: type)
    }

    /// Parses a `Dn:FILENAME` prefix to extract drive number and filename.
    ///
    /// Supports formats:
    /// - `D:FILE` → drive nil (default), filename "FILE"
    /// - `D1:FILE` → drive 1, filename "FILE"
    /// - `D2:FILE` → drive 2, filename "FILE"
    /// - `FILE` → drive nil, filename "FILE"
    private func parseDrivePrefix(_ input: String) -> (drive: Int?, filename: String) {
        let upper = input.uppercased()

        // Match D: or Dn: prefix
        if upper.hasPrefix("D") && upper.count > 1 {
            let afterD = upper.dropFirst()
            if afterD.hasPrefix(":") {
                // D:FILENAME — default drive
                let filename = String(input.dropFirst(2))
                return (nil, filename)
            }
            if let colonIndex = afterD.firstIndex(of: ":") {
                let driveStr = String(afterD[afterD.startIndex..<colonIndex])
                if let drive = Int(driveStr), drive >= 1, drive <= 8 {
                    let filenameStart = afterD.index(after: colonIndex)
                    let filename = String(afterD[filenameStart...])
                    return (drive, filename)
                }
            }
        }

        // No drive prefix
        return (nil, input)
    }

    // MARK: - Helper Functions

    /// Parses an address (hex with $ prefix or decimal).
    private func parseAddress(_ str: String) -> UInt16? {
        if str.hasPrefix("$") {
            return UInt16(str.dropFirst(), radix: 16)
        } else if str.hasPrefix("0x") || str.hasPrefix("0X") {
            return UInt16(str.dropFirst(2), radix: 16)
        } else {
            return UInt16(str)
        }
    }

    /// Parses a hex byte (with or without $ prefix).
    private func parseHexByte(_ str: String) -> UInt8? {
        let hexStr = str.hasPrefix("$") ? String(str.dropFirst()) : str
        return UInt8(hexStr, radix: 16)
    }

    /// Parses escape sequences in a string.
    private func parseEscapes(_ str: String) -> String {
        var result = ""
        var iterator = str.makeIterator()

        while let char = iterator.next() {
            if char == "\\" {
                if let escaped = iterator.next() {
                    switch escaped {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "s": result.append(" ")  // Space
                    case "e": result.append("\u{1B}")  // Escape
                    case "\\": result.append("\\")
                    default: result.append(escaped)
                    }
                }
            } else {
                result.append(char)
            }
        }

        return result
    }
}

// =============================================================================
// MARK: - CLI Protocol Errors
// =============================================================================

/// Errors that can occur during CLI protocol parsing or execution.
public enum CLIProtocolError: Error, LocalizedError, Sendable {
    case lineTooLong
    case invalidCommand(String)
    case invalidAddress(String)
    case invalidCount(String)
    case invalidByte(String)
    case invalidStepCount(String)
    case invalidResetType(String)
    case invalidRegister(String)
    case invalidRegisterFormat(String)
    case invalidValue(String)
    case invalidDriveNumber(String)
    case missingArgument(String)
    case connectionFailed(String)
    case timeout
    case socketNotFound
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .lineTooLong:
            return "Line too long"
        case .invalidCommand(let cmd):
            return "Invalid command '\(cmd)'"
        case .invalidAddress(let addr):
            return "Invalid address '\(addr)'"
        case .invalidCount(let count):
            return "Invalid count '\(count)'"
        case .invalidByte(let byte):
            return "Invalid byte value '\(byte)'"
        case .invalidStepCount(let count):
            return "Invalid step count '\(count)'"
        case .invalidResetType(let type):
            return "Invalid reset type '\(type)'"
        case .invalidRegister(let reg):
            return "Invalid register '\(reg)'"
        case .invalidRegisterFormat(let fmt):
            return "Invalid register format '\(fmt)'"
        case .invalidValue(let val):
            return "Invalid value '\(val)'"
        case .invalidDriveNumber(let drive):
            return "Invalid drive number '\(drive)'"
        case .missingArgument(let msg):
            return msg
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .timeout:
            return "Command timed out"
        case .socketNotFound:
            return "No server socket found"
        case .unexpectedResponse(let resp):
            return "Unexpected response: \(resp)"
        }
    }

    /// Formats the error for CLI protocol response.
    public var cliResponse: CLIResponse {
        .error(errorDescription ?? "Unknown error")
    }
}

// =============================================================================
// MARK: - Response Parser
// =============================================================================

/// Parses responses from the CLI protocol.
public struct CLIResponseParser: Sendable {
    public init() {}

    /// Parses a response line.
    ///
    /// - Parameter line: The response line to parse.
    /// - Returns: The parsed response or event.
    public func parse(_ line: String) throws -> ParsedResponse {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix(CLIProtocolConstants.okPrefix) {
            let data = String(trimmed.dropFirst(CLIProtocolConstants.okPrefix.count))
            return .response(.ok(data))
        } else if trimmed.hasPrefix(CLIProtocolConstants.errorPrefix) {
            let message = String(trimmed.dropFirst(CLIProtocolConstants.errorPrefix.count))
            return .response(.error(message))
        } else if trimmed.hasPrefix(CLIProtocolConstants.eventPrefix) {
            let eventData = String(trimmed.dropFirst(CLIProtocolConstants.eventPrefix.count))
            return .event(try parseEvent(eventData))
        } else {
            throw CLIProtocolError.unexpectedResponse(trimmed)
        }
    }

    private func parseEvent(_ data: String) throws -> CLIEvent {
        let parts = data.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let eventType = parts.first else {
            throw CLIProtocolError.unexpectedResponse("empty event")
        }

        switch String(eventType).lowercased() {
        case "breakpoint":
            // Format: breakpoint $XXXX A=$XX X=$XX Y=$XX S=$XX P=$XX
            var address: UInt16 = 0
            var a: UInt8 = 0, x: UInt8 = 0, y: UInt8 = 0, s: UInt8 = 0, p: UInt8 = 0

            // Extract the address (first $XXXX after "breakpoint")
            if let addressMatch = data.range(of: #"\$([0-9A-Fa-f]{4})"#, options: .regularExpression) {
                let addressStr = String(data[addressMatch]).dropFirst()  // Remove $
                address = UInt16(addressStr, radix: 16) ?? 0
            }

            // Extract register values using "REG=$XX" pattern
            let regPattern = #"([AXYSP])=\$([0-9A-Fa-f]{2})"#
            if let regex = try? NSRegularExpression(pattern: regPattern) {
                let nsData = data as NSString
                let matches = regex.matches(in: data, range: NSRange(location: 0, length: nsData.length))
                for match in matches {
                    let regName = nsData.substring(with: match.range(at: 1))
                    let regValue = UInt8(nsData.substring(with: match.range(at: 2)), radix: 16) ?? 0
                    switch regName {
                    case "A": a = regValue
                    case "X": x = regValue
                    case "Y": y = regValue
                    case "S": s = regValue
                    case "P": p = regValue
                    default: break
                    }
                }
            }

            return .breakpoint(address: address, a: a, x: x, y: y, s: s, p: p)

        case "stopped":
            if let addressMatch = data.range(of: #"\$([0-9A-Fa-f]{4})"#, options: .regularExpression) {
                let addressStr = String(data[addressMatch]).dropFirst()
                if let address = UInt16(addressStr, radix: 16) {
                    return .stopped(address: address)
                }
            }
            return .stopped(address: 0)

        case "error":
            let message = parts.count > 1 ? String(parts[1]) : "Unknown error"
            return .error(message: message)

        default:
            throw CLIProtocolError.unexpectedResponse("unknown event type '\(eventType)'")
        }
    }

    /// Result of parsing a response.
    public enum ParsedResponse: Sendable {
        case response(CLIResponse)
        case event(CLIEvent)
    }
}
