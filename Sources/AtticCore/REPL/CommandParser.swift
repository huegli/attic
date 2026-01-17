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
    // MARK: - BASIC Command Parsing (Stub)
    // =========================================================================

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
        let parts = input.split(separator: " ", maxSplits: 1)
        let command = String(parts[0]).lowercased()

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
            return .basicList(start: nil, end: nil)
        case "vars":
            return .basicVars(name: nil)
        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown BASIC command. Type .help for available commands."
            )
        }
    }

    // =========================================================================
    // MARK: - DOS Command Parsing (Stub)
    // =========================================================================

    private func parseDOSCommand(_ input: String) throws -> Command {
        let parts = input.split(separator: " ")
        guard let first = parts.first else {
            throw AtticError.invalidCommand(input, suggestion: nil)
        }

        let command = String(first).lowercased()

        switch command {
        case "drives":
            return .dosDrives
        case "dir":
            let pattern = parts.count > 1 ? String(parts[1]) : nil
            return .dosDirectory(pattern: pattern)
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
