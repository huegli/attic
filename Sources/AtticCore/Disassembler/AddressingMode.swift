// =============================================================================
// AddressingMode.swift - 6502 Addressing Modes
// =============================================================================
//
// This file defines the addressing modes used by the 6502 processor.
// The 6502 has 13 distinct addressing modes that determine how operands
// are fetched and how effective addresses are calculated.
//
// Understanding addressing modes is crucial for:
// - Disassembling machine code correctly
// - Calculating the number of bytes per instruction
// - Formatting disassembly output appropriately
//
// The Atari 800 XL uses the 6502C (SALLY) variant, which is functionally
// identical to the standard 6502 for addressing mode purposes.
//
// Reference: See docs/6502_REFERENCE.md for complete addressing mode details.
//
// =============================================================================

import Foundation

/// Represents the addressing modes of the 6502 processor.
///
/// Each addressing mode defines how the CPU calculates the effective address
/// for an instruction's operand. The mode also determines:
/// - How many bytes the instruction occupies (1-3 bytes)
/// - How the operand should be displayed in disassembly
/// - The number of cycles the instruction takes (base cycles)
///
/// Example usage:
/// ```swift
/// let mode = AddressingMode.absoluteX
/// print(mode.byteCount)        // 3
/// print(mode.formatOperand(0x1234))  // "$1234,X"
/// ```
public enum AddressingMode: String, Sendable, CaseIterable {
    // =========================================================================
    // MARK: - Single-Byte Instructions (No Operand)
    // =========================================================================

    /// Implied addressing - the operand is implicit in the instruction.
    /// Example: `CLC` (clear carry flag), `RTS` (return from subroutine)
    /// Byte count: 1 (opcode only)
    case implied

    /// Accumulator addressing - operates on the A register.
    /// Example: `ASL A` (arithmetic shift left on accumulator)
    /// Byte count: 1 (opcode only)
    /// Note: Some assemblers write this as `ASL` without the `A`.
    case accumulator

    // =========================================================================
    // MARK: - Two-Byte Instructions (One Operand Byte)
    // =========================================================================

    /// Immediate addressing - the operand is a constant value.
    /// Example: `LDA #$42` loads the literal value $42 into A
    /// Byte count: 2 (opcode + immediate value)
    /// Format: `#$XX`
    case immediate

    /// Zero Page addressing - operand is an 8-bit address in page zero ($00-$FF).
    /// Example: `LDA $80` loads from address $0080
    /// Byte count: 2 (opcode + zero page address)
    /// Format: `$XX`
    /// This is faster than absolute addressing because only one byte of
    /// address needs to be fetched.
    case zeroPage

    /// Zero Page,X addressing - zero page address plus X register.
    /// Example: `LDA $80,X` loads from address ($80 + X) & $FF
    /// Byte count: 2 (opcode + base address)
    /// Format: `$XX,X`
    /// Note: The addition wraps within page zero (no page crossing).
    case zeroPageX

    /// Zero Page,Y addressing - zero page address plus Y register.
    /// Example: `LDX $80,Y` loads from address ($80 + Y) & $FF
    /// Byte count: 2 (opcode + base address)
    /// Format: `$XX,Y`
    /// Only used by LDX and STX instructions.
    case zeroPageY

    /// Relative addressing - used for branch instructions.
    /// Example: `BNE $F0` branches -16 bytes relative to PC
    /// Byte count: 2 (opcode + signed 8-bit offset)
    /// Format: Shows target address `$XXXX`
    /// The offset is signed (-128 to +127), relative to the address
    /// of the instruction following the branch.
    case relative

    /// Indexed Indirect (X) - also called "Indirect,X" or "(zp,X)".
    /// Example: `LDA ($80,X)` reads pointer from ($80+X) & $FF, then loads
    /// Byte count: 2 (opcode + base address)
    /// Format: `($XX,X)`
    /// Process: Add X to zero page address, read 16-bit pointer, fetch from pointer.
    case indexedIndirectX

    /// Indirect Indexed (Y) - also called "(zp),Y" or "Indirect,Y".
    /// Example: `LDA ($80),Y` reads pointer from $80, adds Y, then loads
    /// Byte count: 2 (opcode + zero page address)
    /// Format: `($XX),Y`
    /// Process: Read 16-bit pointer from zero page, add Y, fetch from result.
    /// This is the most common indirect mode for array access.
    case indirectIndexedY

    // =========================================================================
    // MARK: - Three-Byte Instructions (Two Operand Bytes)
    // =========================================================================

    /// Absolute addressing - operand is a full 16-bit address.
    /// Example: `LDA $1234` loads from address $1234
    /// Byte count: 3 (opcode + low byte + high byte)
    /// Format: `$XXXX`
    case absolute

    /// Absolute,X addressing - 16-bit address plus X register.
    /// Example: `LDA $1234,X` loads from address $1234 + X
    /// Byte count: 3 (opcode + low byte + high byte)
    /// Format: `$XXXX,X`
    /// May take an extra cycle if page boundary is crossed.
    case absoluteX

    /// Absolute,Y addressing - 16-bit address plus Y register.
    /// Example: `LDA $1234,Y` loads from address $1234 + Y
    /// Byte count: 3 (opcode + low byte + high byte)
    /// Format: `$XXXX,Y`
    /// May take an extra cycle if page boundary is crossed.
    case absoluteY

    /// Indirect addressing - used only by JMP instruction.
    /// Example: `JMP ($1234)` reads 16-bit address from $1234, jumps there
    /// Byte count: 3 (opcode + low byte + high byte)
    /// Format: `($XXXX)`
    /// Note: Famous 6502 bug - if low byte is $FF, high byte comes from
    /// $XX00 instead of $XX00+$0100 (doesn't cross page boundary).
    case indirect

    // =========================================================================
    // MARK: - Special (Illegal Opcodes)
    // =========================================================================

    /// Unknown/invalid opcode - used for illegal instructions that have
    /// no defined addressing mode or are completely undefined.
    case unknown
}

// =============================================================================
// MARK: - Computed Properties
// =============================================================================

extension AddressingMode {
    /// The number of bytes this addressing mode requires (including opcode).
    ///
    /// This is essential for the disassembler to know how many bytes to
    /// consume for each instruction.
    ///
    /// - Returns: 1 for implied/accumulator, 2 for zero page/immediate/relative,
    ///            3 for absolute/indirect, 1 for unknown.
    public var byteCount: Int {
        switch self {
        case .implied, .accumulator, .unknown:
            return 1
        case .immediate, .zeroPage, .zeroPageX, .zeroPageY, .relative,
             .indexedIndirectX, .indirectIndexedY:
            return 2
        case .absolute, .absoluteX, .absoluteY, .indirect:
            return 3
        }
    }

    /// The number of operand bytes (excluding the opcode).
    ///
    /// Useful for reading just the operand portion from memory.
    public var operandByteCount: Int {
        byteCount - 1
    }

    /// Human-readable description of the addressing mode.
    ///
    /// Used in documentation and debugging output.
    public var description: String {
        switch self {
        case .implied:          return "Implied"
        case .accumulator:      return "Accumulator"
        case .immediate:        return "Immediate"
        case .zeroPage:         return "Zero Page"
        case .zeroPageX:        return "Zero Page,X"
        case .zeroPageY:        return "Zero Page,Y"
        case .relative:         return "Relative"
        case .indexedIndirectX: return "Indexed Indirect (X)"
        case .indirectIndexedY: return "Indirect Indexed (Y)"
        case .absolute:         return "Absolute"
        case .absoluteX:        return "Absolute,X"
        case .absoluteY:        return "Absolute,Y"
        case .indirect:         return "Indirect"
        case .unknown:          return "Unknown"
        }
    }

    /// Short notation used in assembly syntax references.
    ///
    /// These match common 6502 assembly documentation notation.
    public var notation: String {
        switch self {
        case .implied:          return "impl"
        case .accumulator:      return "A"
        case .immediate:        return "#"
        case .zeroPage:         return "zp"
        case .zeroPageX:        return "zp,X"
        case .zeroPageY:        return "zp,Y"
        case .relative:         return "rel"
        case .indexedIndirectX: return "(zp,X)"
        case .indirectIndexedY: return "(zp),Y"
        case .absolute:         return "abs"
        case .absoluteX:        return "abs,X"
        case .absoluteY:        return "abs,Y"
        case .indirect:         return "(abs)"
        case .unknown:          return "???"
        }
    }
}

// =============================================================================
// MARK: - Operand Formatting
// =============================================================================

extension AddressingMode {
    /// Formats the operand value according to this addressing mode.
    ///
    /// This produces the standard 6502 assembly syntax for the operand.
    /// The `operandValue` parameter is interpreted differently based on the mode:
    /// - For immediate: the literal byte value
    /// - For zero page modes: the 8-bit address
    /// - For absolute modes: the 16-bit address
    /// - For relative: the target address (not the offset)
    ///
    /// - Parameters:
    ///   - operandValue: The operand value (8 or 16 bits depending on mode).
    ///   - label: Optional label to use instead of numeric address.
    /// - Returns: Formatted operand string (e.g., "#$42", "$1234,X", "($80),Y").
    public func formatOperand(_ operandValue: UInt16, label: String? = nil) -> String {
        let addrStr = label ?? String(format: "$%04X", operandValue)
        let byteStr = label ?? String(format: "$%02X", operandValue & 0xFF)

        switch self {
        case .implied:
            return ""
        case .accumulator:
            return "A"
        case .immediate:
            return "#\(byteStr)"
        case .zeroPage:
            return byteStr
        case .zeroPageX:
            return "\(byteStr),X"
        case .zeroPageY:
            return "\(byteStr),Y"
        case .relative:
            // For relative, operandValue is the target address
            return addrStr
        case .indexedIndirectX:
            return "(\(byteStr),X)"
        case .indirectIndexedY:
            return "(\(byteStr)),Y"
        case .absolute:
            return addrStr
        case .absoluteX:
            return "\(addrStr),X"
        case .absoluteY:
            return "\(addrStr),Y"
        case .indirect:
            return "(\(addrStr))"
        case .unknown:
            return "???"
        }
    }
}
