// =============================================================================
// REPLMode.swift - REPL Mode Definitions
// =============================================================================
//
// This file defines the three operating modes of the Attic REPL:
//
// 1. Monitor Mode - Low-level debugging (disassembly, memory inspection,
//    breakpoints, stepping). Prompt: [monitor] $XXXX>
//
// 2. BASIC Mode - Entering and running BASIC programs. Programs are
//    tokenized and injected into emulator memory. Prompt: [basic] >
//
// 3. DOS Mode - Disk management (mounting ATR images, listing directories,
//    copying files). Prompt: [dos] D1:>
//
// The mode determines:
// - How commands are parsed and executed
// - The prompt format displayed to the user
// - Which commands are available
//
// Switching modes is done with global commands:
// - .monitor - Switch to monitor mode
// - .basic   - Switch to BASIC mode (Atari BASIC)
// - .basic turbo - Switch to BASIC mode (Turbo BASIC XL)
// - .dos     - Switch to DOS mode
//
// =============================================================================

import Foundation

/// The operating modes of the REPL.
///
/// Each mode provides different functionality and command sets.
/// The mode affects command parsing and prompt display.
public enum REPLMode: Sendable, Equatable {
    /// Monitor mode for low-level debugging.
    ///
    /// Available commands: disassembly (d), memory dump (m), write (>),
    /// step (s), go (g), breakpoints (bp, bc), registers (r), etc.
    case monitor

    /// BASIC mode for program entry.
    ///
    /// Supports both Atari BASIC and Turbo BASIC XL tokenizers.
    /// Commands: list, run, new, save, load, vars, etc.
    case basic(variant: BasicVariant)

    /// DOS mode for disk management.
    ///
    /// Commands: mount, unmount, dir, type, copy, delete, etc.
    case dos

    /// The BASIC dialect variants supported.
    public enum BasicVariant: Sendable, Equatable {
        /// Standard Atari BASIC (built into 800 XL)
        case atari
        /// Turbo BASIC XL (extended BASIC with additional commands)
        case turbo
    }
}

// =============================================================================
// MARK: - Prompt Generation
// =============================================================================

extension REPLMode {
    /// Returns the prompt string for this mode.
    ///
    /// The prompt format is designed for Emacs comint-mode compatibility.
    /// All prompts match the regex: `^\[.+\] .+> $`
    ///
    /// - Parameters:
    ///   - pc: Current program counter (used in monitor mode).
    ///   - drive: Current drive number (used in DOS mode).
    /// - Returns: The formatted prompt string ending with "> ".
    public func prompt(pc: UInt16 = 0, drive: Int = 1) -> String {
        switch self {
        case .monitor:
            // Monitor prompt shows current PC address
            return String(format: "[monitor] $%04X> ", pc)

        case .basic(let variant):
            // BASIC prompt shows the variant if it's Turbo BASIC
            switch variant {
            case .atari:
                return "[basic] > "
            case .turbo:
                return "[basic:turbo] > "
            }

        case .dos:
            // DOS prompt shows current drive
            return "[dos] D\(drive):> "
        }
    }

    /// Returns the mode name as a simple string.
    public var name: String {
        switch self {
        case .monitor:
            return "monitor"
        case .basic:
            return "basic"
        case .dos:
            return "dos"
        }
    }

    /// Returns a detailed description of the mode.
    public var description: String {
        switch self {
        case .monitor:
            return "Monitor mode - 6502 debugging and inspection"
        case .basic(let variant):
            switch variant {
            case .atari:
                return "BASIC mode - Atari BASIC program entry"
            case .turbo:
                return "BASIC mode - Turbo BASIC XL program entry"
            }
        case .dos:
            return "DOS mode - Disk image management"
        }
    }
}

// =============================================================================
// MARK: - Mode Switching
// =============================================================================

extension REPLMode {
    /// Parses a mode switch command and returns the target mode.
    ///
    /// Valid commands:
    /// - ".monitor" -> monitor mode
    /// - ".basic" -> BASIC mode (Atari BASIC)
    /// - ".basic turbo" -> BASIC mode (Turbo BASIC XL)
    /// - ".dos" -> DOS mode
    ///
    /// - Parameter command: The command string (e.g., ".basic turbo")
    /// - Returns: The target mode, or nil if not a valid mode switch command.
    public static func from(command: String) -> REPLMode? {
        let trimmed = command.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = trimmed.split(separator: " ")

        guard let first = parts.first else { return nil }

        switch first {
        case ".monitor":
            return .monitor

        case ".basic":
            if parts.count > 1 && parts[1] == "turbo" {
                return .basic(variant: .turbo)
            }
            return .basic(variant: .atari)

        case ".dos":
            return .dos

        default:
            return nil
        }
    }

    /// Returns the default mode (BASIC with Atari variant).
    public static var `default`: REPLMode {
        .basic(variant: .atari)
    }
}

// =============================================================================
// MARK: - Help Text
// =============================================================================

extension REPLMode {
    /// Returns the help text for available commands in this mode.
    public var helpText: String {
        switch self {
        case .monitor:
            return """
            Monitor Mode Commands:
              g [addr]         Go (resume execution, optionally from address)
              s [count]        Step count instructions (default 1)
              pause            Pause execution
              until <addr>     Run until PC reaches address

              r                Display registers
              r <reg>=<val>    Set register value (A, X, Y, S, P, PC)

              m <addr> [len]   Memory dump (default 64 bytes)
              > <addr> <bytes> Write bytes to memory
              f <s> <e> <val>  Fill memory range with value

              d [addr] [lines] Disassemble (default from PC, 16 lines)
              a <addr>         Enter assembly mode at address

              bp [addr]        Set breakpoint / list breakpoints
              bc <addr>        Clear breakpoint
              bc *             Clear all breakpoints

              w <addr> [len]   Watch memory location
              wc <addr>        Clear watch
              wc *             Clear all watches
            """

        case .basic:
            return """
            BASIC Mode Commands:
              <num> <stmt>     Enter/replace program line
              del <line>       Delete line
              del <s>-<e>      Delete range
              renum [s] [step] Renumber program

              run              Execute program
              stop             Send BREAK
              cont             Continue after BREAK
              new              Clear program

              list             List entire program
              list <line>      List single line
              list <s>-<e>     List range

              vars             Show all variables
              var <name>       Show specific variable

              save "D:FILE"    Save to ATR disk
              load "D:FILE"    Load from ATR disk
              import <path>    Import .BAS from macOS
              export <path>    Export .BAS to macOS
            """

        case .dos:
            return """
            DOS Mode Commands:
              mount <n> <path> Mount ATR at drive n (1-8)
              unmount <n>      Unmount drive
              drives           Show mounted drives
              cd <n>           Change current drive

              dir [pattern]    List files (* and ? wildcards)
              info <file>      Show file details

              type <file>      Display text file
              dump <file>      Hex dump file
              copy <s> <d>     Copy file
              rename <o> <n>   Rename file
              delete <file>    Delete file
              lock <file>      Set read-only
              unlock <file>    Clear read-only

              export <f> <p>   Extract to macOS
              import <p> <f>   Add from macOS

              newdisk <p> [t]  Create new ATR (ss/sd, ss/ed, ss/dd)
              format           Format current disk
            """
        }
    }
}
