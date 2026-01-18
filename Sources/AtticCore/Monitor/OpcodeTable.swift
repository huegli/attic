// =============================================================================
// OpcodeTable.swift - Complete 6502 Opcode Reference Table
// =============================================================================
//
// This file provides a complete reference table for all 6502 opcodes, including:
// - Mnemonic (instruction name)
// - Addressing mode
// - Instruction length in bytes
// - Cycle count (base, not including page crossing)
//
// This table is used by:
// - The disassembler (Phase 10) to decode instructions
// - The assembler to encode instructions
// - The stepping logic to determine instruction length for BRK placement
//
// 6502 Addressing Modes:
// ----------------------
// The 6502 has 13 different addressing modes, each with a distinctive syntax:
//
// | Mode            | Syntax      | Bytes | Example        |
// |-----------------|-------------|-------|----------------|
// | Implied         | (none)      | 1     | INX            |
// | Accumulator     | A           | 1     | ASL A          |
// | Immediate       | #$nn        | 2     | LDA #$00       |
// | Zero Page       | $nn         | 2     | LDA $00        |
// | Zero Page,X     | $nn,X       | 2     | LDA $00,X      |
// | Zero Page,Y     | $nn,Y       | 2     | LDX $00,Y      |
// | Absolute        | $nnnn       | 3     | LDA $1234      |
// | Absolute,X      | $nnnn,X     | 3     | LDA $1234,X    |
// | Absolute,Y      | $nnnn,Y     | 3     | LDA $1234,Y    |
// | Indirect        | ($nnnn)     | 3     | JMP ($1234)    |
// | Indexed Indirect| ($nn,X)     | 2     | LDA ($00,X)    |
// | Indirect Indexed| ($nn),Y     | 2     | LDA ($00),Y    |
// | Relative        | $nnnn       | 2     | BNE $0600      |
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Addressing Mode Enumeration
// =============================================================================

/// The 6502's addressing modes.
///
/// Each mode determines how the operand is interpreted and affects both
/// instruction length and cycle count.
public enum AddressingMode: String, Sendable, CaseIterable {
    /// No operand - instruction operates implicitly.
    /// Example: INX, DEY, RTS
    case implied = "IMP"

    /// Operates on the accumulator register.
    /// Example: ASL A, ROL A
    case accumulator = "ACC"

    /// 8-bit literal value follows the opcode.
    /// Example: LDA #$00
    case immediate = "IMM"

    /// 8-bit zero page address (page 0: $00-$FF).
    /// Example: LDA $00
    case zeroPage = "ZP"

    /// Zero page address indexed by X.
    /// Example: LDA $00,X
    case zeroPageX = "ZPX"

    /// Zero page address indexed by Y.
    /// Example: LDX $00,Y
    case zeroPageY = "ZPY"

    /// 16-bit absolute address.
    /// Example: LDA $1234
    case absolute = "ABS"

    /// Absolute address indexed by X.
    /// Example: LDA $1234,X
    case absoluteX = "ABX"

    /// Absolute address indexed by Y.
    /// Example: LDA $1234,Y
    case absoluteY = "ABY"

    /// Indirect addressing (JMP only).
    /// Example: JMP ($1234)
    case indirect = "IND"

    /// Indexed indirect: add X to zero page pointer first.
    /// Example: LDA ($00,X)
    case indexedIndirect = "IZX"

    /// Indirect indexed: get pointer, then add Y.
    /// Example: LDA ($00),Y
    case indirectIndexed = "IZY"

    /// Relative addressing for branch instructions.
    /// The operand is a signed 8-bit offset.
    case relative = "REL"

    /// Returns the number of bytes for this addressing mode.
    public var bytes: Int {
        switch self {
        case .implied, .accumulator:
            return 1
        case .immediate, .zeroPage, .zeroPageX, .zeroPageY,
             .indexedIndirect, .indirectIndexed, .relative:
            return 2
        case .absolute, .absoluteX, .absoluteY, .indirect:
            return 3
        }
    }

    /// Returns whether this mode can cross a page boundary (affecting cycles).
    public var canCrossPage: Bool {
        switch self {
        case .absoluteX, .absoluteY, .indirectIndexed:
            return true
        default:
            return false
        }
    }
}

// =============================================================================
// MARK: - Opcode Information Structure
// =============================================================================

/// Information about a single 6502 opcode.
///
/// This structure contains everything needed to:
/// - Disassemble the instruction
/// - Assemble from mnemonic + operand
/// - Determine instruction length for stepping
public struct OpcodeInfo: Sendable {
    /// The instruction mnemonic (e.g., "LDA", "STA", "JMP").
    public let mnemonic: String

    /// The addressing mode for this opcode.
    public let mode: AddressingMode

    /// Base cycle count (not including page crossing penalty).
    public let cycles: Int

    /// Whether crossing a page boundary adds an extra cycle.
    public let pageCross: Bool

    /// Number of bytes this instruction occupies (derived from mode).
    public var bytes: Int {
        mode.bytes
    }

    public init(mnemonic: String, mode: AddressingMode, cycles: Int, pageCross: Bool = false) {
        self.mnemonic = mnemonic
        self.mode = mode
        self.cycles = cycles
        self.pageCross = pageCross
    }
}

// =============================================================================
// MARK: - Opcode Table
// =============================================================================

/// Complete 6502 opcode lookup table.
///
/// This table maps each opcode byte (0x00-0xFF) to its OpcodeInfo.
/// Invalid/undocumented opcodes are not included - lookups for those
/// will return nil.
///
/// Usage:
///
///     if let info = OpcodeTable.lookup(0xA9) {
///         print(info.mnemonic)  // "LDA"
///         print(info.mode)      // .immediate
///         print(info.bytes)     // 2
///     }
///
public enum OpcodeTable {
    /// The main opcode lookup table.
    /// Index is the opcode byte, value is OpcodeInfo (or nil for invalid).
    public static let table: [UInt8: OpcodeInfo] = buildTable()

    /// Looks up information for an opcode.
    ///
    /// - Parameter opcode: The opcode byte to look up.
    /// - Returns: OpcodeInfo if valid, nil if invalid/undocumented.
    public static func lookup(_ opcode: UInt8) -> OpcodeInfo? {
        table[opcode]
    }

    /// Returns the instruction length in bytes for an opcode.
    ///
    /// - Parameter opcode: The opcode byte.
    /// - Returns: Length in bytes (1-3), or 1 for invalid opcodes.
    public static func instructionLength(_ opcode: UInt8) -> Int {
        table[opcode]?.bytes ?? 1
    }

    /// Returns all opcodes for a given mnemonic.
    ///
    /// - Parameter mnemonic: The instruction mnemonic (case-insensitive).
    /// - Returns: Dictionary mapping AddressingMode to opcode byte.
    public static func opcodesFor(mnemonic: String) -> [AddressingMode: UInt8] {
        let upper = mnemonic.uppercased()
        var result: [AddressingMode: UInt8] = [:]

        for (opcode, info) in table {
            if info.mnemonic == upper {
                result[info.mode] = opcode
            }
        }

        return result
    }

    /// Returns the opcode for a mnemonic and addressing mode combination.
    ///
    /// - Parameters:
    ///   - mnemonic: The instruction mnemonic.
    ///   - mode: The addressing mode.
    /// - Returns: The opcode byte, or nil if invalid combination.
    public static func opcode(for mnemonic: String, mode: AddressingMode) -> UInt8? {
        let upper = mnemonic.uppercased()

        for (opcode, info) in table {
            if info.mnemonic == upper && info.mode == mode {
                return opcode
            }
        }

        return nil
    }

    /// Returns all valid mnemonics.
    public static var allMnemonics: Set<String> {
        Set(table.values.map { $0.mnemonic })
    }

    // =========================================================================
    // MARK: - Table Builder
    // =========================================================================

    /// Builds the complete opcode table.
    private static func buildTable() -> [UInt8: OpcodeInfo] {
        var t: [UInt8: OpcodeInfo] = [:]

        // Helper to add an entry
        func add(_ opcode: UInt8, _ mnemonic: String, _ mode: AddressingMode,
                 _ cycles: Int, pageCross: Bool = false) {
            t[opcode] = OpcodeInfo(mnemonic: mnemonic, mode: mode,
                                   cycles: cycles, pageCross: pageCross)
        }

        // =====================================================================
        // Load/Store Operations
        // =====================================================================

        // LDA - Load Accumulator
        add(0xA9, "LDA", .immediate, 2)
        add(0xA5, "LDA", .zeroPage, 3)
        add(0xB5, "LDA", .zeroPageX, 4)
        add(0xAD, "LDA", .absolute, 4)
        add(0xBD, "LDA", .absoluteX, 4, pageCross: true)
        add(0xB9, "LDA", .absoluteY, 4, pageCross: true)
        add(0xA1, "LDA", .indexedIndirect, 6)
        add(0xB1, "LDA", .indirectIndexed, 5, pageCross: true)

        // LDX - Load X Register
        add(0xA2, "LDX", .immediate, 2)
        add(0xA6, "LDX", .zeroPage, 3)
        add(0xB6, "LDX", .zeroPageY, 4)
        add(0xAE, "LDX", .absolute, 4)
        add(0xBE, "LDX", .absoluteY, 4, pageCross: true)

        // LDY - Load Y Register
        add(0xA0, "LDY", .immediate, 2)
        add(0xA4, "LDY", .zeroPage, 3)
        add(0xB4, "LDY", .zeroPageX, 4)
        add(0xAC, "LDY", .absolute, 4)
        add(0xBC, "LDY", .absoluteX, 4, pageCross: true)

        // STA - Store Accumulator
        add(0x85, "STA", .zeroPage, 3)
        add(0x95, "STA", .zeroPageX, 4)
        add(0x8D, "STA", .absolute, 4)
        add(0x9D, "STA", .absoluteX, 5)
        add(0x99, "STA", .absoluteY, 5)
        add(0x81, "STA", .indexedIndirect, 6)
        add(0x91, "STA", .indirectIndexed, 6)

        // STX - Store X Register
        add(0x86, "STX", .zeroPage, 3)
        add(0x96, "STX", .zeroPageY, 4)
        add(0x8E, "STX", .absolute, 4)

        // STY - Store Y Register
        add(0x84, "STY", .zeroPage, 3)
        add(0x94, "STY", .zeroPageX, 4)
        add(0x8C, "STY", .absolute, 4)

        // =====================================================================
        // Transfer Operations
        // =====================================================================

        add(0xAA, "TAX", .implied, 2)  // Transfer A to X
        add(0xA8, "TAY", .implied, 2)  // Transfer A to Y
        add(0xBA, "TSX", .implied, 2)  // Transfer Stack ptr to X
        add(0x8A, "TXA", .implied, 2)  // Transfer X to A
        add(0x9A, "TXS", .implied, 2)  // Transfer X to Stack ptr
        add(0x98, "TYA", .implied, 2)  // Transfer Y to A

        // =====================================================================
        // Arithmetic Operations
        // =====================================================================

        // ADC - Add with Carry
        add(0x69, "ADC", .immediate, 2)
        add(0x65, "ADC", .zeroPage, 3)
        add(0x75, "ADC", .zeroPageX, 4)
        add(0x6D, "ADC", .absolute, 4)
        add(0x7D, "ADC", .absoluteX, 4, pageCross: true)
        add(0x79, "ADC", .absoluteY, 4, pageCross: true)
        add(0x61, "ADC", .indexedIndirect, 6)
        add(0x71, "ADC", .indirectIndexed, 5, pageCross: true)

        // SBC - Subtract with Carry
        add(0xE9, "SBC", .immediate, 2)
        add(0xE5, "SBC", .zeroPage, 3)
        add(0xF5, "SBC", .zeroPageX, 4)
        add(0xED, "SBC", .absolute, 4)
        add(0xFD, "SBC", .absoluteX, 4, pageCross: true)
        add(0xF9, "SBC", .absoluteY, 4, pageCross: true)
        add(0xE1, "SBC", .indexedIndirect, 6)
        add(0xF1, "SBC", .indirectIndexed, 5, pageCross: true)

        // =====================================================================
        // Increment/Decrement
        // =====================================================================

        // INC - Increment Memory
        add(0xE6, "INC", .zeroPage, 5)
        add(0xF6, "INC", .zeroPageX, 6)
        add(0xEE, "INC", .absolute, 6)
        add(0xFE, "INC", .absoluteX, 7)

        // INX/INY - Increment Registers
        add(0xE8, "INX", .implied, 2)
        add(0xC8, "INY", .implied, 2)

        // DEC - Decrement Memory
        add(0xC6, "DEC", .zeroPage, 5)
        add(0xD6, "DEC", .zeroPageX, 6)
        add(0xCE, "DEC", .absolute, 6)
        add(0xDE, "DEC", .absoluteX, 7)

        // DEX/DEY - Decrement Registers
        add(0xCA, "DEX", .implied, 2)
        add(0x88, "DEY", .implied, 2)

        // =====================================================================
        // Logical Operations
        // =====================================================================

        // AND - Logical AND
        add(0x29, "AND", .immediate, 2)
        add(0x25, "AND", .zeroPage, 3)
        add(0x35, "AND", .zeroPageX, 4)
        add(0x2D, "AND", .absolute, 4)
        add(0x3D, "AND", .absoluteX, 4, pageCross: true)
        add(0x39, "AND", .absoluteY, 4, pageCross: true)
        add(0x21, "AND", .indexedIndirect, 6)
        add(0x31, "AND", .indirectIndexed, 5, pageCross: true)

        // ORA - Logical OR
        add(0x09, "ORA", .immediate, 2)
        add(0x05, "ORA", .zeroPage, 3)
        add(0x15, "ORA", .zeroPageX, 4)
        add(0x0D, "ORA", .absolute, 4)
        add(0x1D, "ORA", .absoluteX, 4, pageCross: true)
        add(0x19, "ORA", .absoluteY, 4, pageCross: true)
        add(0x01, "ORA", .indexedIndirect, 6)
        add(0x11, "ORA", .indirectIndexed, 5, pageCross: true)

        // EOR - Exclusive OR
        add(0x49, "EOR", .immediate, 2)
        add(0x45, "EOR", .zeroPage, 3)
        add(0x55, "EOR", .zeroPageX, 4)
        add(0x4D, "EOR", .absolute, 4)
        add(0x5D, "EOR", .absoluteX, 4, pageCross: true)
        add(0x59, "EOR", .absoluteY, 4, pageCross: true)
        add(0x41, "EOR", .indexedIndirect, 6)
        add(0x51, "EOR", .indirectIndexed, 5, pageCross: true)

        // =====================================================================
        // Shift/Rotate Operations
        // =====================================================================

        // ASL - Arithmetic Shift Left
        add(0x0A, "ASL", .accumulator, 2)
        add(0x06, "ASL", .zeroPage, 5)
        add(0x16, "ASL", .zeroPageX, 6)
        add(0x0E, "ASL", .absolute, 6)
        add(0x1E, "ASL", .absoluteX, 7)

        // LSR - Logical Shift Right
        add(0x4A, "LSR", .accumulator, 2)
        add(0x46, "LSR", .zeroPage, 5)
        add(0x56, "LSR", .zeroPageX, 6)
        add(0x4E, "LSR", .absolute, 6)
        add(0x5E, "LSR", .absoluteX, 7)

        // ROL - Rotate Left
        add(0x2A, "ROL", .accumulator, 2)
        add(0x26, "ROL", .zeroPage, 5)
        add(0x36, "ROL", .zeroPageX, 6)
        add(0x2E, "ROL", .absolute, 6)
        add(0x3E, "ROL", .absoluteX, 7)

        // ROR - Rotate Right
        add(0x6A, "ROR", .accumulator, 2)
        add(0x66, "ROR", .zeroPage, 5)
        add(0x76, "ROR", .zeroPageX, 6)
        add(0x6E, "ROR", .absolute, 6)
        add(0x7E, "ROR", .absoluteX, 7)

        // =====================================================================
        // Compare Operations
        // =====================================================================

        // CMP - Compare Accumulator
        add(0xC9, "CMP", .immediate, 2)
        add(0xC5, "CMP", .zeroPage, 3)
        add(0xD5, "CMP", .zeroPageX, 4)
        add(0xCD, "CMP", .absolute, 4)
        add(0xDD, "CMP", .absoluteX, 4, pageCross: true)
        add(0xD9, "CMP", .absoluteY, 4, pageCross: true)
        add(0xC1, "CMP", .indexedIndirect, 6)
        add(0xD1, "CMP", .indirectIndexed, 5, pageCross: true)

        // CPX - Compare X Register
        add(0xE0, "CPX", .immediate, 2)
        add(0xE4, "CPX", .zeroPage, 3)
        add(0xEC, "CPX", .absolute, 4)

        // CPY - Compare Y Register
        add(0xC0, "CPY", .immediate, 2)
        add(0xC4, "CPY", .zeroPage, 3)
        add(0xCC, "CPY", .absolute, 4)

        // BIT - Bit Test
        add(0x24, "BIT", .zeroPage, 3)
        add(0x2C, "BIT", .absolute, 4)

        // =====================================================================
        // Branch Operations (all relative addressing)
        // =====================================================================

        add(0x90, "BCC", .relative, 2)  // Branch if Carry Clear
        add(0xB0, "BCS", .relative, 2)  // Branch if Carry Set
        add(0xF0, "BEQ", .relative, 2)  // Branch if Equal (Z=1)
        add(0x30, "BMI", .relative, 2)  // Branch if Minus (N=1)
        add(0xD0, "BNE", .relative, 2)  // Branch if Not Equal (Z=0)
        add(0x10, "BPL", .relative, 2)  // Branch if Plus (N=0)
        add(0x50, "BVC", .relative, 2)  // Branch if Overflow Clear
        add(0x70, "BVS", .relative, 2)  // Branch if Overflow Set

        // =====================================================================
        // Jump/Call Operations
        // =====================================================================

        add(0x4C, "JMP", .absolute, 3)   // Jump
        add(0x6C, "JMP", .indirect, 5)   // Jump Indirect
        add(0x20, "JSR", .absolute, 6)   // Jump to Subroutine
        add(0x60, "RTS", .implied, 6)    // Return from Subroutine
        add(0x40, "RTI", .implied, 6)    // Return from Interrupt

        // =====================================================================
        // Stack Operations
        // =====================================================================

        add(0x48, "PHA", .implied, 3)    // Push Accumulator
        add(0x08, "PHP", .implied, 3)    // Push Processor Status
        add(0x68, "PLA", .implied, 4)    // Pull Accumulator
        add(0x28, "PLP", .implied, 4)    // Pull Processor Status

        // =====================================================================
        // Flag Operations
        // =====================================================================

        add(0x18, "CLC", .implied, 2)    // Clear Carry
        add(0xD8, "CLD", .implied, 2)    // Clear Decimal
        add(0x58, "CLI", .implied, 2)    // Clear Interrupt Disable
        add(0xB8, "CLV", .implied, 2)    // Clear Overflow
        add(0x38, "SEC", .implied, 2)    // Set Carry
        add(0xF8, "SED", .implied, 2)    // Set Decimal
        add(0x78, "SEI", .implied, 2)    // Set Interrupt Disable

        // =====================================================================
        // System Operations
        // =====================================================================

        add(0x00, "BRK", .implied, 7)    // Break (software interrupt)
        add(0xEA, "NOP", .implied, 2)    // No Operation

        return t
    }
}

// =============================================================================
// MARK: - Branch Instruction Helpers
// =============================================================================

extension OpcodeTable {
    /// Set of branch instruction mnemonics.
    public static let branchMnemonics: Set<String> = [
        "BCC", "BCS", "BEQ", "BMI", "BNE", "BPL", "BVC", "BVS"
    ]

    /// Returns true if the mnemonic is a branch instruction.
    public static func isBranch(_ mnemonic: String) -> Bool {
        branchMnemonics.contains(mnemonic.uppercased())
    }

    /// Returns true if the mnemonic is a jump instruction (JMP, JSR).
    public static func isJump(_ mnemonic: String) -> Bool {
        let upper = mnemonic.uppercased()
        return upper == "JMP" || upper == "JSR"
    }

    /// Returns true if the mnemonic is a return instruction (RTS, RTI).
    public static func isReturn(_ mnemonic: String) -> Bool {
        let upper = mnemonic.uppercased()
        return upper == "RTS" || upper == "RTI"
    }

    /// Returns true if the mnemonic is a subroutine call (JSR).
    public static func isSubroutineCall(_ mnemonic: String) -> Bool {
        mnemonic.uppercased() == "JSR"
    }

    /// Calculates the branch target address from PC and signed offset.
    ///
    /// - Parameters:
    ///   - pc: The program counter after fetching the branch instruction.
    ///   - offset: The signed 8-bit offset (as Int8).
    /// - Returns: The target address.
    public static func branchTarget(from pc: UInt16, offset: Int8) -> UInt16 {
        // PC points to byte after branch instruction (PC + 2 from start)
        // Branch offset is relative to that position
        let target = Int(pc) + Int(offset)
        return UInt16(truncatingIfNeeded: target)
    }
}
