// =============================================================================
// DisassembledInstruction.swift - Disassembled 6502 Instruction Result
// =============================================================================
//
// This file defines the structure returned when disassembling a 6502
// instruction. It contains all information needed to display the instruction
// in various formats and to understand its behavior.
//
// The DisassembledInstruction provides:
// - The raw bytes that make up the instruction
// - The decoded mnemonic and operand
// - Target address calculation for branches and jumps
// - Cycle timing information
// - Flag effects
// - Various formatting options for display
//
// Example usage:
// ```swift
// let disasm = Disassembler(labels: AddressLabels.atariStandard)
// let instruction = disasm.disassemble(at: 0xE477, memory: memory)
// print(instruction.formatted)  // "$E477  A9 00     LDA #$00"
// ```
//
// =============================================================================

import Foundation

/// Represents a single disassembled 6502 instruction.
///
/// This structure contains all information about a disassembled instruction,
/// including the raw bytes, decoded instruction, target addresses, and
/// formatting methods for display.
///
/// The structure is `Sendable` for safe use across actor boundaries, which
/// is important when the disassembler is called from the EmulatorEngine actor.
public struct DisassembledInstruction: Sendable, Equatable {
    // =========================================================================
    // MARK: - Core Properties
    // =========================================================================

    /// The address where this instruction is located in memory.
    public let address: UInt16

    /// The raw bytes that make up this instruction (1-3 bytes).
    /// The first byte is always the opcode.
    public let bytes: [UInt8]

    /// The instruction mnemonic (e.g., "LDA", "JMP", "BRK").
    public let mnemonic: String

    /// The formatted operand string (e.g., "#$00", "$1234,X", "($80),Y").
    /// Empty for implied addressing mode.
    public let operand: String

    /// The addressing mode used by this instruction.
    public let addressingMode: AddressingMode

    // =========================================================================
    // MARK: - Target Address (for branches and jumps)
    // =========================================================================

    /// The target address for branch/jump instructions, if applicable.
    ///
    /// This is calculated from the operand:
    /// - For JMP absolute: the operand itself
    /// - For JMP indirect: would require memory read (not calculated here)
    /// - For branches: PC + 2 + signed offset
    /// - For JSR: the operand itself
    /// - For other instructions: nil
    public let targetAddress: UInt16?

    /// The relative offset for branch instructions (signed).
    ///
    /// Only set for relative addressing mode (branches).
    /// Positive values branch forward, negative values branch backward.
    public let relativeOffset: Int8?

    /// The label for the target address, if one exists.
    ///
    /// This is populated by the Disassembler using its label table.
    public let targetLabel: String?

    // =========================================================================
    // MARK: - Timing and Flags
    // =========================================================================

    /// Base number of CPU cycles for this instruction.
    public let cycles: Int

    /// Additional cycles that may be added when a page boundary is crossed.
    ///
    /// This applies to certain addressing modes (absolute,X/Y, indirect,Y)
    /// and to branch instructions when the branch is taken.
    public let pageCrossCycles: Int

    /// The CPU flags that may be affected by this instruction.
    public let affectedFlags: CPUFlags

    // =========================================================================
    // MARK: - Instruction Classification
    // =========================================================================

    /// Whether this is an illegal (undocumented) opcode.
    ///
    /// Illegal opcodes work on NMOS 6502 variants including the SALLY chip
    /// used in the Atari 800 XL, but aren't in official MOS documentation.
    public let isIllegal: Bool

    /// Whether this opcode halts the CPU.
    ///
    /// JAM/KIL opcodes freeze the processor and require a reset.
    public let halts: Bool

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a disassembled instruction.
    ///
    /// This initializer is typically called by the Disassembler, not directly.
    ///
    /// - Parameters:
    ///   - address: The memory address of the instruction.
    ///   - bytes: The raw instruction bytes (1-3).
    ///   - mnemonic: The instruction mnemonic.
    ///   - operand: The formatted operand string.
    ///   - addressingMode: The addressing mode.
    ///   - targetAddress: Target address for branches/jumps.
    ///   - relativeOffset: Signed offset for branches.
    ///   - targetLabel: Label for the target address.
    ///   - cycles: Base cycle count.
    ///   - pageCrossCycles: Additional cycles for page crossing.
    ///   - affectedFlags: CPU flags that may be modified.
    ///   - isIllegal: Whether this is an illegal opcode.
    ///   - halts: Whether this opcode halts the CPU.
    public init(
        address: UInt16,
        bytes: [UInt8],
        mnemonic: String,
        operand: String,
        addressingMode: AddressingMode,
        targetAddress: UInt16? = nil,
        relativeOffset: Int8? = nil,
        targetLabel: String? = nil,
        cycles: Int,
        pageCrossCycles: Int = 0,
        affectedFlags: CPUFlags = [],
        isIllegal: Bool = false,
        halts: Bool = false
    ) {
        self.address = address
        self.bytes = bytes
        self.mnemonic = mnemonic
        self.operand = operand
        self.addressingMode = addressingMode
        self.targetAddress = targetAddress
        self.relativeOffset = relativeOffset
        self.targetLabel = targetLabel
        self.cycles = cycles
        self.pageCrossCycles = pageCrossCycles
        self.affectedFlags = affectedFlags
        self.isIllegal = isIllegal
        self.halts = halts
    }

    // =========================================================================
    // MARK: - Computed Properties
    // =========================================================================

    /// The opcode byte (first byte of the instruction).
    public var opcode: UInt8 {
        bytes.first ?? 0
    }

    /// The number of bytes this instruction occupies.
    public var byteCount: Int {
        bytes.count
    }

    /// The address of the next instruction after this one.
    public var nextAddress: UInt16 {
        address &+ UInt16(byteCount)
    }

    /// Whether this instruction is a branch (conditional or unconditional).
    public var isBranch: Bool {
        addressingMode == .relative
    }

    /// Whether this instruction is a jump (JMP or JSR).
    public var isJump: Bool {
        mnemonic == "JMP" || mnemonic == "JSR"
    }

    /// Whether this instruction can change the program counter non-sequentially.
    ///
    /// This includes branches, jumps, returns, and interrupts.
    public var changesFlow: Bool {
        isBranch || isJump ||
        mnemonic == "RTS" || mnemonic == "RTI" ||
        mnemonic == "BRK" || halts
    }

    /// Whether this instruction reads from memory (excluding immediate mode).
    public var readsMemory: Bool {
        switch addressingMode {
        case .immediate, .implied, .accumulator:
            return false
        default:
            // Store instructions don't read (they write)
            return !["STA", "STX", "STY", "SAX"].contains(mnemonic)
        }
    }

    /// Whether this instruction writes to memory.
    public var writesMemory: Bool {
        // Store instructions
        if ["STA", "STX", "STY", "SAX", "AHX", "SHY", "SHX", "TAS"].contains(mnemonic) {
            return true
        }
        // Read-modify-write instructions
        if ["ASL", "LSR", "ROL", "ROR", "INC", "DEC",
            "SLO", "RLA", "SRE", "RRA", "DCP", "ISC"].contains(mnemonic) {
            return addressingMode != .accumulator
        }
        return false
    }
}

// =============================================================================
// MARK: - Formatting
// =============================================================================

extension DisassembledInstruction {
    /// Formats the raw bytes as a hex string.
    ///
    /// Examples: "A9 00", "8D 00 D4", "EA"
    public var bytesString: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Formats the bytes with fixed-width padding (for alignment).
    ///
    /// Always produces 8 characters: "XX       ", "XX XX    ", or "XX XX XX"
    public var paddedBytesString: String {
        let str = bytesString
        return str.padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    /// The full instruction text (mnemonic + operand).
    ///
    /// Examples: "LDA #$00", "STA $D400", "RTS"
    public var instructionText: String {
        operand.isEmpty ? mnemonic : "\(mnemonic) \(operand)"
    }

    /// Standard formatted output for disassembly display.
    ///
    /// Format: "$XXXX  XX XX XX  MNEMONIC OPERAND"
    ///
    /// Example: "$E477  A9 00     LDA #$00"
    public var formatted: String {
        let addrStr = String(format: "$%04X", address)
        return "\(addrStr)  \(paddedBytesString)  \(instructionText)"
    }

    /// Formatted output with branch offset annotation.
    ///
    /// For branch instructions, adds the relative offset in parentheses.
    /// Example: "$E477  D0 05     BNE $E47E (+5)"
    public var formattedWithOffset: String {
        guard let offset = relativeOffset, isBranch else {
            return formatted
        }

        let offsetStr = offset >= 0 ? "+\(offset)" : "\(offset)"
        return "\(formatted) (\(offsetStr))"
    }

    /// Formatted output with label if available.
    ///
    /// For branch/jump instructions with a known label, shows the label.
    /// Example: "$E477  D0 05     BNE LOOP (+5)"
    public var formattedWithLabel: String {
        guard let label = targetLabel, (isBranch || isJump) else {
            return formattedWithOffset
        }

        // Replace numeric target with label in operand
        let labeledOperand: String
        if isBranch, let offset = relativeOffset {
            let offsetStr = offset >= 0 ? "+\(offset)" : "\(offset)"
            labeledOperand = "\(label) (\(offsetStr))"
        } else {
            labeledOperand = label
        }

        let addrStr = String(format: "$%04X", address)
        return "\(addrStr)  \(paddedBytesString)  \(mnemonic) \(labeledOperand)"
    }

    /// Detailed multi-line output for inspection.
    ///
    /// Shows all available information about the instruction.
    public var detailed: String {
        var lines: [String] = []

        lines.append("Address: \(String(format: "$%04X", address))")
        lines.append("Bytes: \(bytesString)")
        lines.append("Instruction: \(instructionText)")
        lines.append("Mode: \(addressingMode.description)")
        lines.append("Cycles: \(cycles)" + (pageCrossCycles > 0 ? " (+\(pageCrossCycles) on page cross)" : ""))

        if !affectedFlags.description.isEmpty && affectedFlags.description != "-" {
            lines.append("Flags: \(affectedFlags.description)")
        }

        if let target = targetAddress {
            var targetStr = String(format: "$%04X", target)
            if let label = targetLabel {
                targetStr += " (\(label))"
            }
            lines.append("Target: \(targetStr)")
        }

        if let offset = relativeOffset {
            lines.append("Offset: \(offset)")
        }

        if isIllegal {
            lines.append("Note: Illegal/undocumented opcode")
        }

        if halts {
            lines.append("Warning: This instruction halts the CPU!")
        }

        return lines.joined(separator: "\n")
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension DisassembledInstruction: CustomStringConvertible {
    /// Default string representation uses the standard formatted output.
    public var description: String {
        formatted
    }
}

// =============================================================================
// MARK: - CustomDebugStringConvertible
// =============================================================================

extension DisassembledInstruction: CustomDebugStringConvertible {
    /// Debug representation includes all details.
    public var debugDescription: String {
        detailed
    }
}
