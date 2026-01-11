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
    // MARK: - Monitor Command Parsing (Stub)
    // =========================================================================

    private func parseMonitorCommand(_ input: String) throws -> Command {
        let parts = input.split(separator: " ")
        guard let first = parts.first else {
            throw AtticError.invalidCommand(input, suggestion: nil)
        }

        let command = String(first).lowercased()

        // Stub implementation - full parsing will be implemented in Phase 8
        switch command {
        case "g":
            return .go(address: nil)
        case "s":
            let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            return .step(count: count)
        case "pause":
            return .pause
        case "r":
            return .registers(modifications: nil)
        case "d":
            return .disassemble(address: nil, lines: 16)
        case "bp":
            if parts.count > 1 {
                if let addr = parseAddress(String(parts[1])) {
                    return .breakpointSet(address: addr)
                }
            }
            return .breakpointList
        case "bc":
            if parts.count > 1 {
                if parts[1] == "*" {
                    return .breakpointClearAll
                }
                if let addr = parseAddress(String(parts[1])) {
                    return .breakpointClear(address: addr)
                }
            }
            throw AtticError.invalidCommand("bc", suggestion: "Usage: bc <address> or bc *")
        default:
            throw AtticError.invalidCommand(
                command,
                suggestion: "Unknown monitor command. Type .help for available commands."
            )
        }
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
