// =============================================================================
// CommandParser.swift - REPL Command Parser
// =============================================================================
//
// This file provides command parsing for the REPL. Commands are parsed
// according to the current mode (monitor, basic, dos) and converted into
// structured Command values for execution.
//
// Command Types:
// - Global commands start with '.' (e.g., .help, .monitor, .quit)
// - Mode-specific commands depend on the current mode
//
// Parsing handles:
// - Tokenizing input into command name and arguments
// - Validating argument counts and types
// - Converting hex addresses ($XXXX) and decimal values
// - Providing helpful error messages with suggestions
//
// Example parsing:
//
//     let parser = CommandParser()
//
//     // In monitor mode
//     let cmd = try parser.parse("m $0600 32", mode: .monitor)
//     // Returns: Command.memoryDump(address: 0x0600, length: 32)
//
//     // In BASIC mode
//     let cmd = try parser.parse("10 PRINT \"HELLO\"", mode: .basic)
//     // Returns: Command.basicLine(number: 10, content: "PRINT \"HELLO\"")
//
// =============================================================================

import Foundation

/// Represents a parsed REPL command.
///
/// Each case corresponds to a specific action that can be performed.
/// The associated values contain the parsed arguments.
public enum Command: Sendable {
    // =========================================================================
    // Global Commands (available in all modes)
    // =========================================================================

    /// Switch REPL mode (.monitor, .basic, .dos)
    case switchMode(REPLMode)

    /// Display help (.help, .help <command>)
    case help(topic: String?)

    /// Show emulator status (.status)
    case status

    /// Cold reset (.reset)
    case reset

    /// Warm reset (.warmstart)
    case warmStart

    /// Take screenshot (.screenshot [path])
    case screenshot(path: String?)

    /// Save state (.state save <path>)
    case saveState(path: String)

    /// Load state (.state load <path>)
    case loadState(path: String)

    /// Exit CLI (.quit)
    case quit

    /// Shutdown GUI and exit (.shutdown)
    case shutdown

    // =========================================================================
    // Monitor Mode Commands
    // =========================================================================

    /// Go/resume execution (g [address])
    case go(address: UInt16?)

    /// Step instructions (s [count])
    case step(count: Int)

    /// Step over subroutine (so)
    case stepOver

    /// Pause execution (pause)
    case pause

    /// Run until address (until <address>)
    case runUntil(address: UInt16)

    /// Display/set registers (r, r A=$XX)
    case registers(modifications: [(String, UInt16)]?)

    /// Memory dump (m <address> [length])
    case memoryDump(address: UInt16, length: Int)

    /// Write memory (> <address> <bytes>)
    case memoryWrite(address: UInt16, bytes: [UInt8])

    /// Fill memory (f <start> <end> <value>)
    case memoryFill(start: UInt16, end: UInt16, value: UInt8)

    /// Disassemble (d [address] [lines])
    case disassemble(address: UInt16?, lines: Int)

    /// Enter assembly mode (a <address>)
    case assemble(address: UInt16)

    /// Set breakpoint (bp <address>)
    case breakpointSet(address: UInt16)

    /// List breakpoints (bp)
    case breakpointList

    /// Clear breakpoint (bc <address>)
    case breakpointClear(address: UInt16)

    /// Clear all breakpoints (bc *)
    case breakpointClearAll

    // =========================================================================
    // BASIC Mode Commands
    // =========================================================================

    /// Enter/replace a BASIC line (10 PRINT "HELLO")
    case basicLine(number: Int, content: String)

    /// Delete line(s) (del 10, del 10-20)
    case basicDelete(start: Int, end: Int?)

    /// Renumber (renum [start] [step])
    case basicRenumber(start: Int?, step: Int?)

    /// Run program (run)
    case basicRun

    /// Stop/break (stop)
    case basicStop

    /// Continue (cont)
    case basicContinue

    /// New/clear (new)
    case basicNew

    /// List program (list, list 10, list 10-20)
    case basicList(start: Int?, end: Int?)

    /// Show variables (vars, var NAME)
    case basicVars(name: String?)

    /// Save to ATR (save "D:FILE")
    case basicSaveATR(filename: String)

    /// Load from ATR (load "D:FILE")
    case basicLoadATR(filename: String)

    /// Import from host (import /path)
    case basicImport(path: String)

    /// Export to host (export /path)
    case basicExport(path: String)

    // =========================================================================
    // DOS Mode Commands
    // =========================================================================

    /// Mount disk (mount 1 /path/to/disk.atr)
    case dosMountDisk(drive: Int, path: String)

    /// Unmount disk (unmount 1)
    case dosUnmount(drive: Int)

    /// List drives (drives)
    case dosDrives

    /// Change drive (cd 2)
    case dosChangeDrive(drive: Int)

    /// List directory (dir, dir *.COM)
    case dosDirectory(pattern: String?)

    /// File info (info FILE.COM)
    case dosFileInfo(filename: String)

    /// Type file (type README.TXT)
    case dosType(filename: String)

    /// Hex dump (dump FILE.COM)
    case dosDump(filename: String)

    /// Copy file (copy SRC.COM D2:DST.COM)
    case dosCopy(source: String, destination: String)

    /// Rename file (rename OLD.COM NEW.COM)
    case dosRename(oldName: String, newName: String)

    /// Delete file (delete FILE.COM)
    case dosDelete(filename: String)

    /// Lock file (lock FILE.COM)
    case dosLock(filename: String)

    /// Unlock file (unlock FILE.COM)
    case dosUnlock(filename: String)

    /// Export to host (export FILE.COM /path)
    case dosExport(filename: String, path: String)

    /// Import from host (import /path FILE.COM)
    case dosImport(path: String, filename: String)

    /// Create new disk (newdisk /path ss/sd)
    case dosNewDisk(path: String, type: String?)

    /// Format disk (format)
    case dosFormat
}

// =============================================================================
// MARK: - Command Parser
// =============================================================================

/// Parses command strings into Command values.
///
/// The parser handles both global commands (prefixed with '.') and
/// mode-specific commands based on the current REPL mode.
public struct CommandParser {
    /// Creates a new command parser.
    public init() {}

    /// Parses a command string according to the current mode.
    ///
    /// - Parameters:
    ///   - input: The command string entered by the user.
    ///   - mode: The current REPL mode.
    /// - Returns: The parsed Command.
    /// - Throws: AtticError.invalidCommand if parsing fails.
    public func parse(_ input: String, mode: REPLMode) throws -> Command {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw AtticError.invalidCommand("", suggestion: "Enter a command or type .help")
        }

        // Check for global commands first (start with '.')
        if trimmed.hasPrefix(".") {
            return try parseGlobalCommand(trimmed)
        }

        // Parse based on current mode
        switch mode {
        case .monitor:
            return try parseMonitorCommand(trimmed)
        case .basic:
            return try parseBasicCommand(trimmed)
        case .dos:
            return try parseDOSCommand(trimmed)
        }
    }

    // =========================================================================
    // MARK: - Global Command Parsing
    // =========================================================================

    private func parseGlobalCommand(_ input: String) throws -> Command {
        let parts = input.split(separator: " ", maxSplits: 1)
        let command = String(parts[0]).lowercased()
        let args = parts.count > 1 ? String(parts[1]) : nil

        switch command {
        case ".monitor":
            return .switchMode(.monitor)
        case ".basic":
            if let args = args, args.lowercased() == "turbo" {
                return .switchMode(.basic(variant: .turbo))
            }
            return .switchMode(.basic(variant: .atari))
        case ".dos":
            return .switchMode(.dos)
        case ".help":
            return .help(topic: args)
        case ".status":
            return .status
        case ".reset":
            return .reset
        case ".warmstart":
            return .warmStart
        case ".screenshot":
            return .screenshot(path: args)
        case ".state":
            return try parseStateCommand(args)
        case ".quit":
            return .quit
        case ".shutdown":
            return .shutdown
        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown global command. Type .help for available commands."
            )
        }
    }

    private func parseStateCommand(_ args: String?) throws -> Command {
        guard let args = args else {
            throw AtticError.invalidCommand(
                ".state",
                suggestion: "Usage: .state save <path> or .state load <path>"
            )
        }

        let parts = args.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            throw AtticError.invalidCommand(
                ".state \(args)",
                suggestion: "Usage: .state save <path> or .state load <path>"
            )
        }

        let subcommand = String(parts[0]).lowercased()
        let path = String(parts[1])

        switch subcommand {
        case "save":
            return .saveState(path: path)
        case "load":
            return .loadState(path: path)
        default:
            throw AtticError.invalidCommand(
                ".state \(subcommand)",
                suggestion: "Use '.state save' or '.state load'"
            )
        }
    }

    // =========================================================================
    // MARK: - Monitor Command Parsing
    // =========================================================================

    private func parseMonitorCommand(_ input: String) throws -> Command {
        let parts = input.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else {
            throw AtticError.invalidCommand(input, suggestion: nil)
        }

        let command = String(first).lowercased()
        let argsString = parts.count > 1 ? String(parts[1]) : ""

        switch command {
        // Execution control
        case "g":
            return try parseGo(argsString)
        case "s":
            return try parseStepMonitor(argsString)
        case "so":
            return .stepOver
        case "pause":
            return .pause
        case "until":
            return try parseUntil(argsString)

        // Registers
        case "r":
            return try parseRegistersMonitor(argsString)

        // Memory
        case "m":
            return try parseMemoryDump(argsString)
        case ">":
            return try parseMemoryWriteMonitor(argsString)
        case "f":
            return try parseMemoryFillMonitor(argsString)

        // Disassembly
        case "d":
            return try parseDisassembleMonitor(argsString)

        // Assembly
        case "a":
            return try parseAssembleMonitor(argsString)

        // Breakpoints
        case "bp":
            return try parseBreakpointSetOrList(argsString)
        case "bc":
            return try parseBreakpointClear(argsString)

        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown monitor command. Commands: g, s, so, pause, until, r, m, >, f, d, a, bp, bc"
            )
        }
    }

    // MARK: - Monitor Command Helpers

    private func parseGo(_ args: String) throws -> Command {
        if args.isEmpty {
            return .go(address: nil)
        }
        guard let address = parseAddress(args) else {
            throw AtticError.invalidCommand("g \(args)", suggestion: "Invalid address. Use: g [$address]")
        }
        return .go(address: address)
    }

    private func parseStepMonitor(_ args: String) throws -> Command {
        if args.isEmpty {
            return .step(count: 1)
        }
        guard let count = Int(args), count > 0 else {
            throw AtticError.invalidCommand("s \(args)", suggestion: "Invalid count. Use: s [count]")
        }
        return .step(count: count)
    }

    private func parseUntil(_ args: String) throws -> Command {
        guard !args.isEmpty else {
            throw AtticError.invalidCommand("until", suggestion: "Usage: until <address>")
        }
        guard let address = parseAddress(args) else {
            throw AtticError.invalidCommand("until \(args)", suggestion: "Invalid address")
        }
        return .runUntil(address: address)
    }

    private func parseRegistersMonitor(_ args: String) throws -> Command {
        if args.isEmpty {
            return .registers(modifications: nil)
        }

        // Parse register assignments like "A=$50 X=$10 PC=$0600"
        var modifications: [(String, UInt16)] = []
        let assignments = args.split(separator: " ")

        for assignment in assignments {
            let parts = assignment.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw AtticError.invalidCommand("r \(args)", suggestion: "Use format: r A=$XX X=$XX")
            }

            let regName = String(parts[0]).uppercased()
            guard ["A", "X", "Y", "S", "P", "PC"].contains(regName) else {
                throw AtticError.invalidCommand("r \(args)", suggestion: "Valid registers: A, X, Y, S, P, PC")
            }

            guard let value = parseAddress(String(parts[1])) else {
                throw AtticError.invalidCommand("r \(args)", suggestion: "Invalid value for \(regName)")
            }

            modifications.append((regName, value))
        }

        return .registers(modifications: modifications)
    }

    private func parseMemoryDump(_ args: String) throws -> Command {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard !parts.isEmpty else {
            throw AtticError.invalidCommand("m", suggestion: "Usage: m <address> [length]")
        }

        guard let address = parseAddress(String(parts[0])) else {
            throw AtticError.invalidCommand("m \(args)", suggestion: "Invalid address")
        }

        let length = parts.count > 1 ? (Int(parts[1]) ?? 64) : 64
        return .memoryDump(address: address, length: length)
    }

    private func parseMemoryWriteMonitor(_ args: String) throws -> Command {
        let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw AtticError.invalidCommand("> \(args)", suggestion: "Usage: > <address> <bytes>")
        }

        guard let address = parseAddress(String(parts[0])) else {
            throw AtticError.invalidCommand("> \(args)", suggestion: "Invalid address")
        }

        // Parse bytes (space or comma separated, with optional $ prefix)
        let bytesStr = String(parts[1])
        var bytes: [UInt8] = []

        let byteStrs = bytesStr.split { $0 == " " || $0 == "," }
        for byteStr in byteStrs {
            var str = String(byteStr).trimmingCharacters(in: .whitespaces)
            if str.hasPrefix("$") {
                str = String(str.dropFirst())
            }
            guard let byte = UInt8(str, radix: 16) else {
                throw AtticError.invalidCommand("> \(args)", suggestion: "Invalid byte value: \(byteStr)")
            }
            bytes.append(byte)
        }

        guard !bytes.isEmpty else {
            throw AtticError.invalidCommand("> \(args)", suggestion: "No bytes specified")
        }

        return .memoryWrite(address: address, bytes: bytes)
    }

    private func parseMemoryFillMonitor(_ args: String) throws -> Command {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else {
            throw AtticError.invalidCommand("f \(args)", suggestion: "Usage: f <start> <end> <value>")
        }

        guard let start = parseAddress(String(parts[0])) else {
            throw AtticError.invalidCommand("f \(args)", suggestion: "Invalid start address")
        }

        guard let end = parseAddress(String(parts[1])) else {
            throw AtticError.invalidCommand("f \(args)", suggestion: "Invalid end address")
        }

        var valueStr = String(parts[2])
        if valueStr.hasPrefix("$") {
            valueStr = String(valueStr.dropFirst())
        }
        guard let value = UInt8(valueStr, radix: 16) else {
            throw AtticError.invalidCommand("f \(args)", suggestion: "Invalid fill value")
        }

        return .memoryFill(start: start, end: end, value: value)
    }

    private func parseDisassembleMonitor(_ args: String) throws -> Command {
        let parts = args.split(separator: " ", omittingEmptySubsequences: true)

        var address: UInt16? = nil
        var lines: Int = 16

        if !parts.isEmpty {
            address = parseAddress(String(parts[0]))
        }

        if parts.count > 1, let l = Int(parts[1]) {
            lines = l
        }

        return .disassemble(address: address, lines: lines)
    }

    private func parseAssembleMonitor(_ args: String) throws -> Command {
        guard !args.isEmpty else {
            throw AtticError.invalidCommand("a", suggestion: "Usage: a <address>")
        }

        guard let address = parseAddress(args.trimmingCharacters(in: .whitespaces)) else {
            throw AtticError.invalidCommand("a \(args)", suggestion: "Invalid address")
        }

        return .assemble(address: address)
    }

    private func parseBreakpointSetOrList(_ args: String) throws -> Command {
        if args.isEmpty {
            return .breakpointList
        }

        guard let address = parseAddress(args) else {
            throw AtticError.invalidCommand("bp \(args)", suggestion: "Invalid address")
        }

        return .breakpointSet(address: address)
    }

    private func parseBreakpointClear(_ args: String) throws -> Command {
        guard !args.isEmpty else {
            throw AtticError.invalidCommand("bc", suggestion: "Usage: bc <address> or bc *")
        }

        if args == "*" {
            return .breakpointClearAll
        }

        guard let address = parseAddress(args) else {
            throw AtticError.invalidCommand("bc \(args)", suggestion: "Invalid address")
        }

        return .breakpointClear(address: address)
    }

    // =========================================================================
    // MARK: - BASIC Command Parsing
    // =========================================================================

    /// Parses BASIC mode commands for program editing and execution.
    ///
    /// BASIC mode supports the following commands:
    /// - Line entry: `10 PRINT "HELLO"` - enter/replace a program line
    /// - `run` - execute the program
    /// - `stop` - break program execution
    /// - `cont` - continue after break
    /// - `new` - clear program and variables
    /// - `list [start] [-end]` - list program lines
    /// - `vars [name]` - show variables
    /// - `del start [-end]` - delete lines
    /// - `renum [start] [step]` - renumber lines
    /// - `save D:FILENAME` - save tokenized program to ATR disk
    /// - `load D:FILENAME` - load tokenized program from ATR disk
    /// - `import <path>` - import .BAS file from host
    /// - `export <path>` - export to .BAS file on host
    private func parseBasicCommand(_ input: String) throws -> Command {
        // Check if it's a line number (BASIC program entry)
        if let firstChar = input.first, firstChar.isNumber {
            // Extract line number and content
            var lineNumStr = ""
            var remaining = input[...]

            while let char = remaining.first, char.isNumber {
                lineNumStr.append(char)
                remaining = remaining.dropFirst()
            }

            guard let lineNum = Int(lineNumStr) else {
                throw AtticError.invalidCommand(input, suggestion: "Invalid line number")
            }

            let content = String(remaining).trimmingCharacters(in: .whitespaces)
            return .basicLine(number: lineNum, content: content)
        }

        // Parse BASIC commands
        let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let command = String(parts[0]).lowercased()
        let argsString = parts.count > 1 ? String(parts[1]) : ""

        switch command {
        case "run":
            return .basicRun

        case "stop":
            return .basicStop

        case "cont":
            return .basicContinue

        case "new":
            return .basicNew

        case "list":
            return try parseListCommand(argsString)

        case "vars", "var":
            // vars [name]
            let name = argsString.trimmingCharacters(in: .whitespaces)
            return .basicVars(name: name.isEmpty ? nil : name.uppercased())

        case "del", "delete":
            return try parseDeleteCommand(argsString)

        case "renum", "renumber":
            return try parseRenumberCommand(argsString)

        case "import":
            guard !argsString.isEmpty else {
                throw AtticError.invalidCommand(
                    "import",
                    suggestion: "Usage: import <path>  (e.g., import ~/program.bas)"
                )
            }
            return .basicImport(path: argsString)

        case "export":
            guard !argsString.isEmpty else {
                throw AtticError.invalidCommand(
                    "export",
                    suggestion: "Usage: export <path>  (e.g., export ~/program.bas)"
                )
            }
            return .basicExport(path: argsString)

        case "save":
            guard !argsString.isEmpty else {
                throw AtticError.invalidCommand(
                    "save",
                    suggestion: "Usage: save D:FILENAME  (e.g., save D:TEST or save D2:MYPROG)"
                )
            }
            return .basicSaveATR(filename: argsString)

        case "load":
            guard !argsString.isEmpty else {
                throw AtticError.invalidCommand(
                    "load",
                    suggestion: "Usage: load D:FILENAME  (e.g., load D:TEST or load D2:MYPROG)"
                )
            }
            return .basicLoadATR(filename: argsString)

        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown BASIC command. Commands: run, stop, cont, new, list, vars, del, renum, save, load, import, export"
            )
        }
    }

    // =========================================================================
    // MARK: - BASIC Command Helpers
    // =========================================================================

    /// Parses the LIST command with optional line range.
    ///
    /// Formats:
    /// - `list` - list all lines
    /// - `list 10` - list line 10 only
    /// - `list 10-` - list from line 10 to end
    /// - `list -50` - list from start to line 50
    /// - `list 10-50` - list lines 10 through 50
    private func parseListCommand(_ args: String) throws -> Command {
        let trimmed = args.trimmingCharacters(in: .whitespaces)

        // No arguments - list all
        if trimmed.isEmpty {
            return .basicList(start: nil, end: nil)
        }

        // Check for range (contains '-')
        if trimmed.contains("-") {
            let rangeParts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

            var start: Int? = nil
            var end: Int? = nil

            // Parse start if present
            if !rangeParts[0].isEmpty {
                guard let s = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)) else {
                    throw AtticError.invalidCommand(
                        "list \(args)",
                        suggestion: "Invalid start line number"
                    )
                }
                start = s
            }

            // Parse end if present
            if rangeParts.count > 1 && !rangeParts[1].isEmpty {
                guard let e = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) else {
                    throw AtticError.invalidCommand(
                        "list \(args)",
                        suggestion: "Invalid end line number"
                    )
                }
                end = e
            }

            return .basicList(start: start, end: end)
        }

        // Single line number
        guard let lineNum = Int(trimmed) else {
            throw AtticError.invalidCommand(
                "list \(args)",
                suggestion: "Invalid line number. Use: list [start[-end]]"
            )
        }

        // Single line number means list that line only
        return .basicList(start: lineNum, end: lineNum)
    }

    /// Parses the DEL command for deleting lines.
    ///
    /// Formats:
    /// - `del 10` - delete line 10
    /// - `del 10-50` - delete lines 10 through 50
    private func parseDeleteCommand(_ args: String) throws -> Command {
        let trimmed = args.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            throw AtticError.invalidCommand(
                "del",
                suggestion: "Usage: del <line> or del <start>-<end>"
            )
        }

        // Check for range
        if trimmed.contains("-") {
            let rangeParts = trimmed.split(separator: "-", maxSplits: 1)
            guard rangeParts.count == 2 else {
                throw AtticError.invalidCommand(
                    "del \(args)",
                    suggestion: "Usage: del <start>-<end>"
                )
            }

            guard let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                  let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) else {
                throw AtticError.invalidCommand(
                    "del \(args)",
                    suggestion: "Invalid line numbers"
                )
            }

            return .basicDelete(start: start, end: end)
        }

        // Single line
        guard let lineNum = Int(trimmed) else {
            throw AtticError.invalidCommand(
                "del \(args)",
                suggestion: "Invalid line number"
            )
        }

        return .basicDelete(start: lineNum, end: nil)
    }

    /// Parses the RENUM command for renumbering lines.
    ///
    /// Formats:
    /// - `renum` - renumber starting at 10, step 10
    /// - `renum 100` - renumber starting at 100, step 10
    /// - `renum 100 20` - renumber starting at 100, step 20
    private func parseRenumberCommand(_ args: String) throws -> Command {
        let trimmed = args.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return .basicRenumber(start: nil, step: nil)
        }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)

        var start: Int? = nil
        var step: Int? = nil

        if !parts.isEmpty {
            guard let s = Int(parts[0]) else {
                throw AtticError.invalidCommand(
                    "renum \(args)",
                    suggestion: "Invalid start number"
                )
            }
            start = s
        }

        if parts.count > 1 {
            guard let st = Int(parts[1]) else {
                throw AtticError.invalidCommand(
                    "renum \(args)",
                    suggestion: "Invalid step value"
                )
            }
            step = st
        }

        return .basicRenumber(start: start, step: step)
    }

    // =========================================================================
    // MARK: - DOS Command Parsing
    // =========================================================================

    /// Parses DOS mode commands for disk and file management.
    ///
    /// DOS mode supports the following commands:
    /// - `mount <n> <path>` - Mount ATR at drive n (1-8)
    /// - `unmount <n>` - Unmount drive n
    /// - `drives` - Show all drives
    /// - `cd <n>` - Change current drive
    /// - `dir [pattern]` - List files
    /// - `info <file>` - Show file info
    /// - `type <file>` - Display text file
    /// - `dump <file>` - Hex dump of file
    /// - `copy <src> <dest>` - Copy file
    /// - `rename <old> <new>` - Rename file
    /// - `delete <file>` - Delete file
    /// - `lock <file>` - Lock file (read-only)
    /// - `unlock <file>` - Unlock file
    /// - `export <file> <path>` - Export to host
    /// - `import <path> <file>` - Import from host
    /// - `newdisk <path> [type]` - Create new ATR
    /// - `format` - Format current disk
    private func parseDOSCommand(_ input: String) throws -> Command {
        let parts = input.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else {
            throw AtticError.invalidCommand(input, suggestion: nil)
        }

        let command = String(first).lowercased()

        switch command {
        // =================================================================
        // Drive Management
        // =================================================================

        case "mount":
            // mount <drive> <path>
            guard parts.count >= 3 else {
                throw AtticError.invalidCommand(
                    "mount",
                    suggestion: "Usage: mount <drive> <path>  (e.g., mount 1 ~/disks/game.atr)"
                )
            }
            guard let drive = Int(parts[1]), drive >= 1 && drive <= 8 else {
                throw AtticError.invalidCommand(
                    "mount",
                    suggestion: "Drive must be 1-8"
                )
            }
            // Join remaining parts as path (handles spaces in path)
            let path = parts.dropFirst(2).joined(separator: " ")
            return .dosMountDisk(drive: drive, path: path)

        case "unmount":
            // unmount <drive>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "unmount",
                    suggestion: "Usage: unmount <drive>  (e.g., unmount 1)"
                )
            }
            guard let drive = Int(parts[1]), drive >= 1 && drive <= 8 else {
                throw AtticError.invalidCommand(
                    "unmount",
                    suggestion: "Drive must be 1-8"
                )
            }
            return .dosUnmount(drive: drive)

        case "drives":
            return .dosDrives

        case "cd":
            // cd <drive>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "cd",
                    suggestion: "Usage: cd <drive>  (e.g., cd 2)"
                )
            }
            guard let drive = Int(parts[1]), drive >= 1 && drive <= 8 else {
                throw AtticError.invalidCommand(
                    "cd",
                    suggestion: "Drive must be 1-8"
                )
            }
            return .dosChangeDrive(drive: drive)

        // =================================================================
        // Directory Operations
        // =================================================================

        case "dir":
            // dir [pattern]
            let pattern = parts.count > 1 ? String(parts[1]) : nil
            return .dosDirectory(pattern: pattern)

        case "info":
            // info <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "info",
                    suggestion: "Usage: info <filename>  (e.g., info GAME.COM)"
                )
            }
            return .dosFileInfo(filename: String(parts[1]))

        // =================================================================
        // File Viewing
        // =================================================================

        case "type":
            // type <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "type",
                    suggestion: "Usage: type <filename>  (e.g., type README.TXT)"
                )
            }
            return .dosType(filename: String(parts[1]))

        case "dump":
            // dump <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "dump",
                    suggestion: "Usage: dump <filename>  (e.g., dump GAME.COM)"
                )
            }
            return .dosDump(filename: String(parts[1]))

        // =================================================================
        // File Operations
        // =================================================================

        case "copy":
            // copy <source> <destination>
            guard parts.count >= 3 else {
                throw AtticError.invalidCommand(
                    "copy",
                    suggestion: "Usage: copy <source> <dest>  (e.g., copy GAME.COM D2:BACKUP.COM)"
                )
            }
            return .dosCopy(source: String(parts[1]), destination: String(parts[2]))

        case "rename":
            // rename <oldname> <newname>
            guard parts.count >= 3 else {
                throw AtticError.invalidCommand(
                    "rename",
                    suggestion: "Usage: rename <old> <new>  (e.g., rename GAME.COM ARCADE.COM)"
                )
            }
            return .dosRename(oldName: String(parts[1]), newName: String(parts[2]))

        case "delete", "del":
            // delete <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "delete",
                    suggestion: "Usage: delete <filename>  (e.g., delete SAVE.DAT)"
                )
            }
            return .dosDelete(filename: String(parts[1]))

        case "lock":
            // lock <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "lock",
                    suggestion: "Usage: lock <filename>  (e.g., lock GAME.COM)"
                )
            }
            return .dosLock(filename: String(parts[1]))

        case "unlock":
            // unlock <filename>
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "unlock",
                    suggestion: "Usage: unlock <filename>  (e.g., unlock GAME.COM)"
                )
            }
            return .dosUnlock(filename: String(parts[1]))

        // =================================================================
        // Host Transfer
        // =================================================================

        case "export":
            // export <filename> <hostpath>
            guard parts.count >= 3 else {
                throw AtticError.invalidCommand(
                    "export",
                    suggestion: "Usage: export <file> <path>  (e.g., export GAME.COM ~/Desktop/game.com)"
                )
            }
            let filename = String(parts[1])
            // Join remaining parts as path (handles spaces)
            let path = parts.dropFirst(2).joined(separator: " ")
            return .dosExport(filename: filename, path: path)

        case "import":
            // import <hostpath> <filename>
            guard parts.count >= 3 else {
                throw AtticError.invalidCommand(
                    "import",
                    suggestion: "Usage: import <path> <file>  (e.g., import ~/Desktop/game.com GAME.COM)"
                )
            }
            // For import, the path is first, so we need to be careful about spaces
            // If filename is last part, path is everything before it
            let filename = String(parts.last!)
            let path = parts.dropFirst().dropLast().joined(separator: " ")
            return .dosImport(path: path, filename: filename)

        // =================================================================
        // Disk Management
        // =================================================================

        case "newdisk":
            // newdisk <path> [type]
            guard parts.count >= 2 else {
                throw AtticError.invalidCommand(
                    "newdisk",
                    suggestion: "Usage: newdisk <path> [type]  (types: ss/sd, ss/ed, ss/dd)"
                )
            }
            // Check if last part is a disk type
            let lastPart = String(parts.last!).lowercased()
            let validTypes = ["ss/sd", "ss/ed", "ss/dd"]
            if validTypes.contains(lastPart) && parts.count >= 3 {
                let path = parts.dropFirst().dropLast().joined(separator: " ")
                return .dosNewDisk(path: path, type: lastPart)
            } else {
                let path = parts.dropFirst().joined(separator: " ")
                return .dosNewDisk(path: path, type: nil)
            }

        case "format":
            return .dosFormat

        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown DOS command. Type .help for available commands."
            )
        }
    }

    // =========================================================================
    // MARK: - Utility Functions
    // =========================================================================

    /// Parses an address string (hex or decimal) into a UInt16.
    ///
    /// Supports formats:
    /// - $XXXX (hex with $ prefix)
    /// - 0xXXXX (hex with 0x prefix)
    /// - NNNNN (decimal)
    private func parseAddress(_ string: String) -> UInt16? {
        var str = string.trimmingCharacters(in: .whitespaces)

        // Handle $ prefix (common 6502 convention)
        if str.hasPrefix("$") {
            str = String(str.dropFirst())
            return UInt16(str, radix: 16)
        }

        // Handle 0x prefix
        if str.lowercased().hasPrefix("0x") {
            str = String(str.dropFirst(2))
            return UInt16(str, radix: 16)
        }

        // Try decimal
        return UInt16(str)
    }
}
