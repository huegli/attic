// =============================================================================
// OpcodeInfo.swift - 6502 Opcode Information and Lookup Table
// =============================================================================
//
// This file contains the complete opcode table for the 6502 processor,
// including both documented opcodes and the "illegal" (undocumented) opcodes
// that are known to work on the 6502C (SALLY) chip used in the Atari 800 XL.
//
// The 6502 has 256 possible opcodes (8-bit opcode byte), but only about 151
// are officially documented. The remaining opcodes exhibit various behaviors:
// - Some are useful "illegal" instructions used by games and demos
// - Some halt the CPU (JAM/KIL)
// - Some have unstable or unpredictable behavior
//
// The SALLY (6502C) chip in the Atari 800 XL is an NMOS 6502 variant with
// additional HALT and RDY signal handling for DMA. The illegal opcodes
// behave the same as on a standard NMOS 6502.
//
// Reference: https://www.masswerk.at/6502/6502_instruction_set.html
// Reference: https://www.oxyron.de/html/opcodes02.html
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - CPU Status Flags
// =============================================================================

/// The 6502 processor status flags.
///
/// These flags are stored in the P (Processor Status) register and are
/// affected by various instructions. The disassembler tracks which flags
/// each instruction can modify.
public struct CPUFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Carry flag (C) - bit 0
    /// Set when arithmetic overflow occurs in the low bit, or by SEC/CLC.
    public static let carry = CPUFlags(rawValue: 1 << 0)

    /// Zero flag (Z) - bit 1
    /// Set when the result of an operation is zero.
    public static let zero = CPUFlags(rawValue: 1 << 1)

    /// Interrupt disable flag (I) - bit 2
    /// When set, IRQ interrupts are disabled. Set by SEI, cleared by CLI.
    public static let interrupt = CPUFlags(rawValue: 1 << 2)

    /// Decimal mode flag (D) - bit 3
    /// When set, ADC and SBC use BCD arithmetic. Set by SED, cleared by CLD.
    /// Note: The NES 6502 (2A03) ignores this flag.
    public static let decimal = CPUFlags(rawValue: 1 << 3)

    /// Break flag (B) - bit 4
    /// Set when BRK instruction is executed (in the stacked P value).
    /// This flag doesn't actually exist in the P register - it's only
    /// present in the value pushed to the stack.
    public static let breakFlag = CPUFlags(rawValue: 1 << 4)

    /// Unused flag - bit 5
    /// Always reads as 1.
    public static let unused = CPUFlags(rawValue: 1 << 5)

    /// Overflow flag (V) - bit 6
    /// Set when signed arithmetic overflow occurs. Also affected by BIT.
    public static let overflow = CPUFlags(rawValue: 1 << 6)

    /// Negative flag (N) - bit 7
    /// Set when the result has bit 7 set (negative in signed arithmetic).
    public static let negative = CPUFlags(rawValue: 1 << 7)

    /// Common flag combinations
    public static let nz: CPUFlags = [.negative, .zero]
    public static let nzc: CPUFlags = [.negative, .zero, .carry]
    public static let nvzc: CPUFlags = [.negative, .overflow, .zero, .carry]
    public static let all: CPUFlags = [.negative, .overflow, .zero, .carry, .interrupt, .decimal]

    /// Format flags as a string like "NZ" or "NZC"
    public var description: String {
        var result = ""
        if contains(.negative) { result += "N" }
        if contains(.overflow) { result += "V" }
        if contains(.breakFlag) { result += "B" }
        if contains(.decimal) { result += "D" }
        if contains(.interrupt) { result += "I" }
        if contains(.zero) { result += "Z" }
        if contains(.carry) { result += "C" }
        return result.isEmpty ? "-" : result
    }
}

// =============================================================================
// MARK: - Opcode Info Structure
// =============================================================================

/// Information about a single 6502 opcode.
///
/// This structure contains everything needed to disassemble an instruction:
/// - The mnemonic (e.g., "LDA", "STA")
/// - The addressing mode (determines operand format)
/// - The number of bytes (1-3)
/// - The base cycle count
/// - Flags that may be affected
/// - Whether it's an illegal/undocumented opcode
///
/// Example:
/// ```swift
/// let info = OpcodeTable.lookup(0xA9)  // LDA #imm
/// print(info.mnemonic)      // "LDA"
/// print(info.mode)          // .immediate
/// print(info.byteCount)     // 2
/// ```
public struct OpcodeInfo: Sendable {
    /// The instruction mnemonic (e.g., "LDA", "JMP", "BRK").
    /// For illegal opcodes, uses common names like "LAX", "SAX", etc.
    /// For unknown opcodes, uses "???".
    public let mnemonic: String

    /// The addressing mode determines how the operand is interpreted.
    public let mode: AddressingMode

    /// Number of bytes the instruction occupies (1-3).
    /// This is determined by the addressing mode.
    public let byteCount: Int

    /// Base number of CPU cycles to execute this instruction.
    /// Some instructions take extra cycles for page boundary crossing
    /// or when a branch is taken.
    public let cycles: Int

    /// Additional cycles when page boundary is crossed.
    /// Only applies to certain addressing modes (absolute,X/Y, indirect,Y).
    public let pageCrossCycles: Int

    /// Which CPU flags this instruction may affect.
    public let affectedFlags: CPUFlags

    /// Whether this is an illegal/undocumented opcode.
    /// Illegal opcodes work on NMOS 6502 variants but aren't in the
    /// official MOS documentation.
    public let isIllegal: Bool

    /// Whether this opcode halts the CPU (JAM/KIL instructions).
    /// After executing, the CPU is stuck and requires a reset.
    public let halts: Bool

    /// Creates an opcode info entry.
    public init(
        mnemonic: String,
        mode: AddressingMode,
        cycles: Int,
        pageCrossCycles: Int = 0,
        affectedFlags: CPUFlags = [],
        isIllegal: Bool = false,
        halts: Bool = false
    ) {
        self.mnemonic = mnemonic
        self.mode = mode
        self.byteCount = mode.byteCount
        self.cycles = cycles
        self.pageCrossCycles = pageCrossCycles
        self.affectedFlags = affectedFlags
        self.isIllegal = isIllegal
        self.halts = halts
    }
}

// =============================================================================
// MARK: - Opcode Table
// =============================================================================

/// Lookup table for all 256 6502 opcodes.
///
/// This enum provides a single static method to look up opcode information
/// by opcode byte. The table includes all documented opcodes and the
/// common illegal opcodes that work reliably on the 6502C.
///
/// Usage:
/// ```swift
/// let info = OpcodeTable.lookup(0xA9)
/// print("\(info.mnemonic) - \(info.mode.description)")
/// // Output: "LDA - Immediate"
/// ```
public enum OpcodeTable {
    /// Looks up information for the given opcode byte.
    ///
    /// - Parameter opcode: The opcode byte (0x00-0xFF).
    /// - Returns: OpcodeInfo describing the instruction.
    public static func lookup(_ opcode: UInt8) -> OpcodeInfo {
        opcodeTable[Int(opcode)]
    }

    /// The complete opcode table indexed by opcode value.
    /// This is a 256-element array covering all possible opcode bytes.
    private static let opcodeTable: [OpcodeInfo] = buildOpcodeTable()

    /// Builds the complete opcode table.
    ///
    /// The table is organized to match the 6502's opcode encoding patterns.
    /// Opcodes are grouped by their low nibble, which often correlates with
    /// the addressing mode.
    private static func buildOpcodeTable() -> [OpcodeInfo] {
        var table = [OpcodeInfo](repeating: unknown(), count: 256)

        // =====================================================================
        // Documented Instructions
        // =====================================================================

        // ----- BRK (Break) -----
        table[0x00] = OpcodeInfo(mnemonic: "BRK", mode: .implied, cycles: 7,
                                  affectedFlags: [.interrupt, .breakFlag])

        // ----- ORA (OR with Accumulator) -----
        table[0x01] = OpcodeInfo(mnemonic: "ORA", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nz)
        table[0x05] = OpcodeInfo(mnemonic: "ORA", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0x09] = OpcodeInfo(mnemonic: "ORA", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0x0D] = OpcodeInfo(mnemonic: "ORA", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0x11] = OpcodeInfo(mnemonic: "ORA", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x15] = OpcodeInfo(mnemonic: "ORA", mode: .zeroPageX, cycles: 4, affectedFlags: .nz)
        table[0x19] = OpcodeInfo(mnemonic: "ORA", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x1D] = OpcodeInfo(mnemonic: "ORA", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- ASL (Arithmetic Shift Left) -----
        table[0x06] = OpcodeInfo(mnemonic: "ASL", mode: .zeroPage, cycles: 5, affectedFlags: .nzc)
        table[0x0A] = OpcodeInfo(mnemonic: "ASL", mode: .accumulator, cycles: 2, affectedFlags: .nzc)
        table[0x0E] = OpcodeInfo(mnemonic: "ASL", mode: .absolute, cycles: 6, affectedFlags: .nzc)
        table[0x16] = OpcodeInfo(mnemonic: "ASL", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc)
        table[0x1E] = OpcodeInfo(mnemonic: "ASL", mode: .absoluteX, cycles: 7, affectedFlags: .nzc)

        // ----- PHP (Push Processor Status) -----
        table[0x08] = OpcodeInfo(mnemonic: "PHP", mode: .implied, cycles: 3)

        // ----- BPL (Branch if Plus) -----
        table[0x10] = OpcodeInfo(mnemonic: "BPL", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- CLC (Clear Carry) -----
        table[0x18] = OpcodeInfo(mnemonic: "CLC", mode: .implied, cycles: 2, affectedFlags: .carry)

        // ----- JSR (Jump to Subroutine) -----
        table[0x20] = OpcodeInfo(mnemonic: "JSR", mode: .absolute, cycles: 6)

        // ----- AND (AND with Accumulator) -----
        table[0x21] = OpcodeInfo(mnemonic: "AND", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nz)
        table[0x25] = OpcodeInfo(mnemonic: "AND", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0x29] = OpcodeInfo(mnemonic: "AND", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0x2D] = OpcodeInfo(mnemonic: "AND", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0x31] = OpcodeInfo(mnemonic: "AND", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x35] = OpcodeInfo(mnemonic: "AND", mode: .zeroPageX, cycles: 4, affectedFlags: .nz)
        table[0x39] = OpcodeInfo(mnemonic: "AND", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x3D] = OpcodeInfo(mnemonic: "AND", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- BIT (Bit Test) -----
        table[0x24] = OpcodeInfo(mnemonic: "BIT", mode: .zeroPage, cycles: 3, affectedFlags: [.negative, .overflow, .zero])
        table[0x2C] = OpcodeInfo(mnemonic: "BIT", mode: .absolute, cycles: 4, affectedFlags: [.negative, .overflow, .zero])

        // ----- ROL (Rotate Left) -----
        table[0x26] = OpcodeInfo(mnemonic: "ROL", mode: .zeroPage, cycles: 5, affectedFlags: .nzc)
        table[0x2A] = OpcodeInfo(mnemonic: "ROL", mode: .accumulator, cycles: 2, affectedFlags: .nzc)
        table[0x2E] = OpcodeInfo(mnemonic: "ROL", mode: .absolute, cycles: 6, affectedFlags: .nzc)
        table[0x36] = OpcodeInfo(mnemonic: "ROL", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc)
        table[0x3E] = OpcodeInfo(mnemonic: "ROL", mode: .absoluteX, cycles: 7, affectedFlags: .nzc)

        // ----- PLP (Pull Processor Status) -----
        table[0x28] = OpcodeInfo(mnemonic: "PLP", mode: .implied, cycles: 4, affectedFlags: .all)

        // ----- BMI (Branch if Minus) -----
        table[0x30] = OpcodeInfo(mnemonic: "BMI", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- SEC (Set Carry) -----
        table[0x38] = OpcodeInfo(mnemonic: "SEC", mode: .implied, cycles: 2, affectedFlags: .carry)

        // ----- RTI (Return from Interrupt) -----
        table[0x40] = OpcodeInfo(mnemonic: "RTI", mode: .implied, cycles: 6, affectedFlags: .all)

        // ----- EOR (Exclusive OR with Accumulator) -----
        table[0x41] = OpcodeInfo(mnemonic: "EOR", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nz)
        table[0x45] = OpcodeInfo(mnemonic: "EOR", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0x49] = OpcodeInfo(mnemonic: "EOR", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0x4D] = OpcodeInfo(mnemonic: "EOR", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0x51] = OpcodeInfo(mnemonic: "EOR", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x55] = OpcodeInfo(mnemonic: "EOR", mode: .zeroPageX, cycles: 4, affectedFlags: .nz)
        table[0x59] = OpcodeInfo(mnemonic: "EOR", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)
        table[0x5D] = OpcodeInfo(mnemonic: "EOR", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- LSR (Logical Shift Right) -----
        table[0x46] = OpcodeInfo(mnemonic: "LSR", mode: .zeroPage, cycles: 5, affectedFlags: .nzc)
        table[0x4A] = OpcodeInfo(mnemonic: "LSR", mode: .accumulator, cycles: 2, affectedFlags: .nzc)
        table[0x4E] = OpcodeInfo(mnemonic: "LSR", mode: .absolute, cycles: 6, affectedFlags: .nzc)
        table[0x56] = OpcodeInfo(mnemonic: "LSR", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc)
        table[0x5E] = OpcodeInfo(mnemonic: "LSR", mode: .absoluteX, cycles: 7, affectedFlags: .nzc)

        // ----- PHA (Push Accumulator) -----
        table[0x48] = OpcodeInfo(mnemonic: "PHA", mode: .implied, cycles: 3)

        // ----- JMP (Jump) -----
        table[0x4C] = OpcodeInfo(mnemonic: "JMP", mode: .absolute, cycles: 3)
        table[0x6C] = OpcodeInfo(mnemonic: "JMP", mode: .indirect, cycles: 5)

        // ----- BVC (Branch if Overflow Clear) -----
        table[0x50] = OpcodeInfo(mnemonic: "BVC", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- CLI (Clear Interrupt Disable) -----
        table[0x58] = OpcodeInfo(mnemonic: "CLI", mode: .implied, cycles: 2, affectedFlags: .interrupt)

        // ----- RTS (Return from Subroutine) -----
        table[0x60] = OpcodeInfo(mnemonic: "RTS", mode: .implied, cycles: 6)

        // ----- ADC (Add with Carry) -----
        table[0x61] = OpcodeInfo(mnemonic: "ADC", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nvzc)
        table[0x65] = OpcodeInfo(mnemonic: "ADC", mode: .zeroPage, cycles: 3, affectedFlags: .nvzc)
        table[0x69] = OpcodeInfo(mnemonic: "ADC", mode: .immediate, cycles: 2, affectedFlags: .nvzc)
        table[0x6D] = OpcodeInfo(mnemonic: "ADC", mode: .absolute, cycles: 4, affectedFlags: .nvzc)
        table[0x71] = OpcodeInfo(mnemonic: "ADC", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nvzc)
        table[0x75] = OpcodeInfo(mnemonic: "ADC", mode: .zeroPageX, cycles: 4, affectedFlags: .nvzc)
        table[0x79] = OpcodeInfo(mnemonic: "ADC", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nvzc)
        table[0x7D] = OpcodeInfo(mnemonic: "ADC", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nvzc)

        // ----- ROR (Rotate Right) -----
        table[0x66] = OpcodeInfo(mnemonic: "ROR", mode: .zeroPage, cycles: 5, affectedFlags: .nzc)
        table[0x6A] = OpcodeInfo(mnemonic: "ROR", mode: .accumulator, cycles: 2, affectedFlags: .nzc)
        table[0x6E] = OpcodeInfo(mnemonic: "ROR", mode: .absolute, cycles: 6, affectedFlags: .nzc)
        table[0x76] = OpcodeInfo(mnemonic: "ROR", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc)
        table[0x7E] = OpcodeInfo(mnemonic: "ROR", mode: .absoluteX, cycles: 7, affectedFlags: .nzc)

        // ----- PLA (Pull Accumulator) -----
        table[0x68] = OpcodeInfo(mnemonic: "PLA", mode: .implied, cycles: 4, affectedFlags: .nz)

        // ----- BVS (Branch if Overflow Set) -----
        table[0x70] = OpcodeInfo(mnemonic: "BVS", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- SEI (Set Interrupt Disable) -----
        table[0x78] = OpcodeInfo(mnemonic: "SEI", mode: .implied, cycles: 2, affectedFlags: .interrupt)

        // ----- STA (Store Accumulator) -----
        table[0x81] = OpcodeInfo(mnemonic: "STA", mode: .indexedIndirectX, cycles: 6)
        table[0x85] = OpcodeInfo(mnemonic: "STA", mode: .zeroPage, cycles: 3)
        table[0x8D] = OpcodeInfo(mnemonic: "STA", mode: .absolute, cycles: 4)
        table[0x91] = OpcodeInfo(mnemonic: "STA", mode: .indirectIndexedY, cycles: 6)
        table[0x95] = OpcodeInfo(mnemonic: "STA", mode: .zeroPageX, cycles: 4)
        table[0x99] = OpcodeInfo(mnemonic: "STA", mode: .absoluteY, cycles: 5)
        table[0x9D] = OpcodeInfo(mnemonic: "STA", mode: .absoluteX, cycles: 5)

        // ----- STY (Store Y Register) -----
        table[0x84] = OpcodeInfo(mnemonic: "STY", mode: .zeroPage, cycles: 3)
        table[0x8C] = OpcodeInfo(mnemonic: "STY", mode: .absolute, cycles: 4)
        table[0x94] = OpcodeInfo(mnemonic: "STY", mode: .zeroPageX, cycles: 4)

        // ----- STX (Store X Register) -----
        table[0x86] = OpcodeInfo(mnemonic: "STX", mode: .zeroPage, cycles: 3)
        table[0x8E] = OpcodeInfo(mnemonic: "STX", mode: .absolute, cycles: 4)
        table[0x96] = OpcodeInfo(mnemonic: "STX", mode: .zeroPageY, cycles: 4)

        // ----- DEY (Decrement Y) -----
        table[0x88] = OpcodeInfo(mnemonic: "DEY", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- TXA (Transfer X to A) -----
        table[0x8A] = OpcodeInfo(mnemonic: "TXA", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- BCC (Branch if Carry Clear) -----
        table[0x90] = OpcodeInfo(mnemonic: "BCC", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- TYA (Transfer Y to A) -----
        table[0x98] = OpcodeInfo(mnemonic: "TYA", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- TXS (Transfer X to Stack Pointer) -----
        table[0x9A] = OpcodeInfo(mnemonic: "TXS", mode: .implied, cycles: 2)

        // ----- LDY (Load Y Register) -----
        table[0xA0] = OpcodeInfo(mnemonic: "LDY", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0xA4] = OpcodeInfo(mnemonic: "LDY", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0xAC] = OpcodeInfo(mnemonic: "LDY", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0xB4] = OpcodeInfo(mnemonic: "LDY", mode: .zeroPageX, cycles: 4, affectedFlags: .nz)
        table[0xBC] = OpcodeInfo(mnemonic: "LDY", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- LDA (Load Accumulator) -----
        table[0xA1] = OpcodeInfo(mnemonic: "LDA", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nz)
        table[0xA5] = OpcodeInfo(mnemonic: "LDA", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0xA9] = OpcodeInfo(mnemonic: "LDA", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0xAD] = OpcodeInfo(mnemonic: "LDA", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0xB1] = OpcodeInfo(mnemonic: "LDA", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nz)
        table[0xB5] = OpcodeInfo(mnemonic: "LDA", mode: .zeroPageX, cycles: 4, affectedFlags: .nz)
        table[0xB9] = OpcodeInfo(mnemonic: "LDA", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)
        table[0xBD] = OpcodeInfo(mnemonic: "LDA", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- LDX (Load X Register) -----
        table[0xA2] = OpcodeInfo(mnemonic: "LDX", mode: .immediate, cycles: 2, affectedFlags: .nz)
        table[0xA6] = OpcodeInfo(mnemonic: "LDX", mode: .zeroPage, cycles: 3, affectedFlags: .nz)
        table[0xAE] = OpcodeInfo(mnemonic: "LDX", mode: .absolute, cycles: 4, affectedFlags: .nz)
        table[0xB6] = OpcodeInfo(mnemonic: "LDX", mode: .zeroPageY, cycles: 4, affectedFlags: .nz)
        table[0xBE] = OpcodeInfo(mnemonic: "LDX", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz)

        // ----- TAY (Transfer A to Y) -----
        table[0xA8] = OpcodeInfo(mnemonic: "TAY", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- TAX (Transfer A to X) -----
        table[0xAA] = OpcodeInfo(mnemonic: "TAX", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- BCS (Branch if Carry Set) -----
        table[0xB0] = OpcodeInfo(mnemonic: "BCS", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- CLV (Clear Overflow) -----
        table[0xB8] = OpcodeInfo(mnemonic: "CLV", mode: .implied, cycles: 2, affectedFlags: .overflow)

        // ----- TSX (Transfer Stack Pointer to X) -----
        table[0xBA] = OpcodeInfo(mnemonic: "TSX", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- CPY (Compare Y Register) -----
        table[0xC0] = OpcodeInfo(mnemonic: "CPY", mode: .immediate, cycles: 2, affectedFlags: .nzc)
        table[0xC4] = OpcodeInfo(mnemonic: "CPY", mode: .zeroPage, cycles: 3, affectedFlags: .nzc)
        table[0xCC] = OpcodeInfo(mnemonic: "CPY", mode: .absolute, cycles: 4, affectedFlags: .nzc)

        // ----- CMP (Compare Accumulator) -----
        table[0xC1] = OpcodeInfo(mnemonic: "CMP", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nzc)
        table[0xC5] = OpcodeInfo(mnemonic: "CMP", mode: .zeroPage, cycles: 3, affectedFlags: .nzc)
        table[0xC9] = OpcodeInfo(mnemonic: "CMP", mode: .immediate, cycles: 2, affectedFlags: .nzc)
        table[0xCD] = OpcodeInfo(mnemonic: "CMP", mode: .absolute, cycles: 4, affectedFlags: .nzc)
        table[0xD1] = OpcodeInfo(mnemonic: "CMP", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nzc)
        table[0xD5] = OpcodeInfo(mnemonic: "CMP", mode: .zeroPageX, cycles: 4, affectedFlags: .nzc)
        table[0xD9] = OpcodeInfo(mnemonic: "CMP", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nzc)
        table[0xDD] = OpcodeInfo(mnemonic: "CMP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nzc)

        // ----- DEC (Decrement Memory) -----
        table[0xC6] = OpcodeInfo(mnemonic: "DEC", mode: .zeroPage, cycles: 5, affectedFlags: .nz)
        table[0xCE] = OpcodeInfo(mnemonic: "DEC", mode: .absolute, cycles: 6, affectedFlags: .nz)
        table[0xD6] = OpcodeInfo(mnemonic: "DEC", mode: .zeroPageX, cycles: 6, affectedFlags: .nz)
        table[0xDE] = OpcodeInfo(mnemonic: "DEC", mode: .absoluteX, cycles: 7, affectedFlags: .nz)

        // ----- INY (Increment Y) -----
        table[0xC8] = OpcodeInfo(mnemonic: "INY", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- DEX (Decrement X) -----
        table[0xCA] = OpcodeInfo(mnemonic: "DEX", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- BNE (Branch if Not Equal) -----
        table[0xD0] = OpcodeInfo(mnemonic: "BNE", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- CLD (Clear Decimal Mode) -----
        table[0xD8] = OpcodeInfo(mnemonic: "CLD", mode: .implied, cycles: 2, affectedFlags: .decimal)

        // ----- CPX (Compare X Register) -----
        table[0xE0] = OpcodeInfo(mnemonic: "CPX", mode: .immediate, cycles: 2, affectedFlags: .nzc)
        table[0xE4] = OpcodeInfo(mnemonic: "CPX", mode: .zeroPage, cycles: 3, affectedFlags: .nzc)
        table[0xEC] = OpcodeInfo(mnemonic: "CPX", mode: .absolute, cycles: 4, affectedFlags: .nzc)

        // ----- SBC (Subtract with Carry) -----
        table[0xE1] = OpcodeInfo(mnemonic: "SBC", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nvzc)
        table[0xE5] = OpcodeInfo(mnemonic: "SBC", mode: .zeroPage, cycles: 3, affectedFlags: .nvzc)
        table[0xE9] = OpcodeInfo(mnemonic: "SBC", mode: .immediate, cycles: 2, affectedFlags: .nvzc)
        table[0xED] = OpcodeInfo(mnemonic: "SBC", mode: .absolute, cycles: 4, affectedFlags: .nvzc)
        table[0xF1] = OpcodeInfo(mnemonic: "SBC", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nvzc)
        table[0xF5] = OpcodeInfo(mnemonic: "SBC", mode: .zeroPageX, cycles: 4, affectedFlags: .nvzc)
        table[0xF9] = OpcodeInfo(mnemonic: "SBC", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nvzc)
        table[0xFD] = OpcodeInfo(mnemonic: "SBC", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, affectedFlags: .nvzc)

        // ----- INC (Increment Memory) -----
        table[0xE6] = OpcodeInfo(mnemonic: "INC", mode: .zeroPage, cycles: 5, affectedFlags: .nz)
        table[0xEE] = OpcodeInfo(mnemonic: "INC", mode: .absolute, cycles: 6, affectedFlags: .nz)
        table[0xF6] = OpcodeInfo(mnemonic: "INC", mode: .zeroPageX, cycles: 6, affectedFlags: .nz)
        table[0xFE] = OpcodeInfo(mnemonic: "INC", mode: .absoluteX, cycles: 7, affectedFlags: .nz)

        // ----- INX (Increment X) -----
        table[0xE8] = OpcodeInfo(mnemonic: "INX", mode: .implied, cycles: 2, affectedFlags: .nz)

        // ----- NOP (No Operation) -----
        table[0xEA] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2)

        // ----- BEQ (Branch if Equal) -----
        table[0xF0] = OpcodeInfo(mnemonic: "BEQ", mode: .relative, cycles: 2, pageCrossCycles: 2)

        // ----- SED (Set Decimal Mode) -----
        table[0xF8] = OpcodeInfo(mnemonic: "SED", mode: .implied, cycles: 2, affectedFlags: .decimal)

        // =====================================================================
        // Illegal Instructions (Stable on 6502C/SALLY)
        // =====================================================================
        // These undocumented instructions work reliably on NMOS 6502 variants
        // and are sometimes used by Atari software for optimization.

        // ----- LAX (LDA + LDX combined) -----
        // Loads both A and X with the same value
        table[0xA3] = OpcodeInfo(mnemonic: "LAX", mode: .indexedIndirectX, cycles: 6, affectedFlags: .nz, isIllegal: true)
        table[0xA7] = OpcodeInfo(mnemonic: "LAX", mode: .zeroPage, cycles: 3, affectedFlags: .nz, isIllegal: true)
        table[0xAF] = OpcodeInfo(mnemonic: "LAX", mode: .absolute, cycles: 4, affectedFlags: .nz, isIllegal: true)
        table[0xB3] = OpcodeInfo(mnemonic: "LAX", mode: .indirectIndexedY, cycles: 5, pageCrossCycles: 1, affectedFlags: .nz, isIllegal: true)
        table[0xB7] = OpcodeInfo(mnemonic: "LAX", mode: .zeroPageY, cycles: 4, affectedFlags: .nz, isIllegal: true)
        table[0xBF] = OpcodeInfo(mnemonic: "LAX", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz, isIllegal: true)

        // ----- SAX (Store A AND X) -----
        // Stores (A & X) to memory
        table[0x83] = OpcodeInfo(mnemonic: "SAX", mode: .indexedIndirectX, cycles: 6, isIllegal: true)
        table[0x87] = OpcodeInfo(mnemonic: "SAX", mode: .zeroPage, cycles: 3, isIllegal: true)
        table[0x8F] = OpcodeInfo(mnemonic: "SAX", mode: .absolute, cycles: 4, isIllegal: true)
        table[0x97] = OpcodeInfo(mnemonic: "SAX", mode: .zeroPageY, cycles: 4, isIllegal: true)

        // ----- DCP (DEC + CMP) -----
        // Decrements memory, then compares with A
        table[0xC3] = OpcodeInfo(mnemonic: "DCP", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0xC7] = OpcodeInfo(mnemonic: "DCP", mode: .zeroPage, cycles: 5, affectedFlags: .nzc, isIllegal: true)
        table[0xCF] = OpcodeInfo(mnemonic: "DCP", mode: .absolute, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0xD3] = OpcodeInfo(mnemonic: "DCP", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0xD7] = OpcodeInfo(mnemonic: "DCP", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0xDB] = OpcodeInfo(mnemonic: "DCP", mode: .absoluteY, cycles: 7, affectedFlags: .nzc, isIllegal: true)
        table[0xDF] = OpcodeInfo(mnemonic: "DCP", mode: .absoluteX, cycles: 7, affectedFlags: .nzc, isIllegal: true)

        // ----- ISC/ISB (INC + SBC) -----
        // Increments memory, then subtracts from A
        table[0xE3] = OpcodeInfo(mnemonic: "ISC", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nvzc, isIllegal: true)
        table[0xE7] = OpcodeInfo(mnemonic: "ISC", mode: .zeroPage, cycles: 5, affectedFlags: .nvzc, isIllegal: true)
        table[0xEF] = OpcodeInfo(mnemonic: "ISC", mode: .absolute, cycles: 6, affectedFlags: .nvzc, isIllegal: true)
        table[0xF3] = OpcodeInfo(mnemonic: "ISC", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nvzc, isIllegal: true)
        table[0xF7] = OpcodeInfo(mnemonic: "ISC", mode: .zeroPageX, cycles: 6, affectedFlags: .nvzc, isIllegal: true)
        table[0xFB] = OpcodeInfo(mnemonic: "ISC", mode: .absoluteY, cycles: 7, affectedFlags: .nvzc, isIllegal: true)
        table[0xFF] = OpcodeInfo(mnemonic: "ISC", mode: .absoluteX, cycles: 7, affectedFlags: .nvzc, isIllegal: true)

        // ----- SLO (ASL + ORA) -----
        // Shifts memory left, then ORs with A
        table[0x03] = OpcodeInfo(mnemonic: "SLO", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x07] = OpcodeInfo(mnemonic: "SLO", mode: .zeroPage, cycles: 5, affectedFlags: .nzc, isIllegal: true)
        table[0x0F] = OpcodeInfo(mnemonic: "SLO", mode: .absolute, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x13] = OpcodeInfo(mnemonic: "SLO", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x17] = OpcodeInfo(mnemonic: "SLO", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x1B] = OpcodeInfo(mnemonic: "SLO", mode: .absoluteY, cycles: 7, affectedFlags: .nzc, isIllegal: true)
        table[0x1F] = OpcodeInfo(mnemonic: "SLO", mode: .absoluteX, cycles: 7, affectedFlags: .nzc, isIllegal: true)

        // ----- RLA (ROL + AND) -----
        // Rotates memory left, then ANDs with A
        table[0x23] = OpcodeInfo(mnemonic: "RLA", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x27] = OpcodeInfo(mnemonic: "RLA", mode: .zeroPage, cycles: 5, affectedFlags: .nzc, isIllegal: true)
        table[0x2F] = OpcodeInfo(mnemonic: "RLA", mode: .absolute, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x33] = OpcodeInfo(mnemonic: "RLA", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x37] = OpcodeInfo(mnemonic: "RLA", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x3B] = OpcodeInfo(mnemonic: "RLA", mode: .absoluteY, cycles: 7, affectedFlags: .nzc, isIllegal: true)
        table[0x3F] = OpcodeInfo(mnemonic: "RLA", mode: .absoluteX, cycles: 7, affectedFlags: .nzc, isIllegal: true)

        // ----- SRE (LSR + EOR) -----
        // Shifts memory right, then XORs with A
        table[0x43] = OpcodeInfo(mnemonic: "SRE", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x47] = OpcodeInfo(mnemonic: "SRE", mode: .zeroPage, cycles: 5, affectedFlags: .nzc, isIllegal: true)
        table[0x4F] = OpcodeInfo(mnemonic: "SRE", mode: .absolute, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x53] = OpcodeInfo(mnemonic: "SRE", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nzc, isIllegal: true)
        table[0x57] = OpcodeInfo(mnemonic: "SRE", mode: .zeroPageX, cycles: 6, affectedFlags: .nzc, isIllegal: true)
        table[0x5B] = OpcodeInfo(mnemonic: "SRE", mode: .absoluteY, cycles: 7, affectedFlags: .nzc, isIllegal: true)
        table[0x5F] = OpcodeInfo(mnemonic: "SRE", mode: .absoluteX, cycles: 7, affectedFlags: .nzc, isIllegal: true)

        // ----- RRA (ROR + ADC) -----
        // Rotates memory right, then adds to A
        table[0x63] = OpcodeInfo(mnemonic: "RRA", mode: .indexedIndirectX, cycles: 8, affectedFlags: .nvzc, isIllegal: true)
        table[0x67] = OpcodeInfo(mnemonic: "RRA", mode: .zeroPage, cycles: 5, affectedFlags: .nvzc, isIllegal: true)
        table[0x6F] = OpcodeInfo(mnemonic: "RRA", mode: .absolute, cycles: 6, affectedFlags: .nvzc, isIllegal: true)
        table[0x73] = OpcodeInfo(mnemonic: "RRA", mode: .indirectIndexedY, cycles: 8, affectedFlags: .nvzc, isIllegal: true)
        table[0x77] = OpcodeInfo(mnemonic: "RRA", mode: .zeroPageX, cycles: 6, affectedFlags: .nvzc, isIllegal: true)
        table[0x7B] = OpcodeInfo(mnemonic: "RRA", mode: .absoluteY, cycles: 7, affectedFlags: .nvzc, isIllegal: true)
        table[0x7F] = OpcodeInfo(mnemonic: "RRA", mode: .absoluteX, cycles: 7, affectedFlags: .nvzc, isIllegal: true)

        // ----- ANC (AND + set C from bit 7) -----
        // ANDs immediate with A, sets C from result bit 7
        table[0x0B] = OpcodeInfo(mnemonic: "ANC", mode: .immediate, cycles: 2, affectedFlags: .nzc, isIllegal: true)
        table[0x2B] = OpcodeInfo(mnemonic: "ANC", mode: .immediate, cycles: 2, affectedFlags: .nzc, isIllegal: true)

        // ----- ALR/ASR (AND + LSR) -----
        // ANDs immediate with A, then shifts right
        table[0x4B] = OpcodeInfo(mnemonic: "ALR", mode: .immediate, cycles: 2, affectedFlags: .nzc, isIllegal: true)

        // ----- ARR (AND + ROR with special flag behavior) -----
        // ANDs immediate with A, rotates right, special V and C handling
        table[0x6B] = OpcodeInfo(mnemonic: "ARR", mode: .immediate, cycles: 2, affectedFlags: .nvzc, isIllegal: true)

        // ----- XAA/ANE (unstable - (A | magic) & X & imm) -----
        // Highly unstable, magic constant varies by chip
        table[0x8B] = OpcodeInfo(mnemonic: "XAA", mode: .immediate, cycles: 2, affectedFlags: .nz, isIllegal: true)

        // ----- AHX/SHA (store A & X & (high byte + 1)) -----
        // Unstable - stores (A & X & (addr high byte + 1)) to memory
        table[0x93] = OpcodeInfo(mnemonic: "AHX", mode: .indirectIndexedY, cycles: 6, isIllegal: true)
        table[0x9F] = OpcodeInfo(mnemonic: "AHX", mode: .absoluteY, cycles: 5, isIllegal: true)

        // ----- TAS/SHS (transfer A & X to S, store A & X & (high + 1)) -----
        table[0x9B] = OpcodeInfo(mnemonic: "TAS", mode: .absoluteY, cycles: 5, isIllegal: true)

        // ----- SHY (store Y & (high byte + 1)) -----
        table[0x9C] = OpcodeInfo(mnemonic: "SHY", mode: .absoluteX, cycles: 5, isIllegal: true)

        // ----- SHX (store X & (high byte + 1)) -----
        table[0x9E] = OpcodeInfo(mnemonic: "SHX", mode: .absoluteY, cycles: 5, isIllegal: true)

        // ----- LAS (load A, X, S with (S & memory)) -----
        table[0xBB] = OpcodeInfo(mnemonic: "LAS", mode: .absoluteY, cycles: 4, pageCrossCycles: 1, affectedFlags: .nz, isIllegal: true)

        // ----- SBC (illegal duplicate) -----
        // Same as $E9 but undocumented
        table[0xEB] = OpcodeInfo(mnemonic: "SBC", mode: .immediate, cycles: 2, affectedFlags: .nvzc, isIllegal: true)

        // ----- NOP (illegal NOPs with various addressing modes) -----
        // These do nothing but consume cycles and bytes
        table[0x1A] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)
        table[0x3A] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)
        table[0x5A] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)
        table[0x7A] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)
        table[0xDA] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)
        table[0xFA] = OpcodeInfo(mnemonic: "NOP", mode: .implied, cycles: 2, isIllegal: true)

        // 2-byte NOPs (skip one byte)
        table[0x04] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPage, cycles: 3, isIllegal: true)
        table[0x14] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)
        table[0x34] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)
        table[0x44] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPage, cycles: 3, isIllegal: true)
        table[0x54] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)
        table[0x64] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPage, cycles: 3, isIllegal: true)
        table[0x74] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)
        table[0x80] = OpcodeInfo(mnemonic: "NOP", mode: .immediate, cycles: 2, isIllegal: true)
        table[0x82] = OpcodeInfo(mnemonic: "NOP", mode: .immediate, cycles: 2, isIllegal: true)
        table[0x89] = OpcodeInfo(mnemonic: "NOP", mode: .immediate, cycles: 2, isIllegal: true)
        table[0xC2] = OpcodeInfo(mnemonic: "NOP", mode: .immediate, cycles: 2, isIllegal: true)
        table[0xD4] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)
        table[0xE2] = OpcodeInfo(mnemonic: "NOP", mode: .immediate, cycles: 2, isIllegal: true)
        table[0xF4] = OpcodeInfo(mnemonic: "NOP", mode: .zeroPageX, cycles: 4, isIllegal: true)

        // 3-byte NOPs (skip two bytes)
        table[0x0C] = OpcodeInfo(mnemonic: "NOP", mode: .absolute, cycles: 4, isIllegal: true)
        table[0x1C] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)
        table[0x3C] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)
        table[0x5C] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)
        table[0x7C] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)
        table[0xDC] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)
        table[0xFC] = OpcodeInfo(mnemonic: "NOP", mode: .absoluteX, cycles: 4, pageCrossCycles: 1, isIllegal: true)

        // ----- JAM/KIL (halt CPU) -----
        // These opcodes freeze the CPU - only a reset can recover
        let jamOpcodes: [UInt8] = [0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72,
                                    0x92, 0xB2, 0xD2, 0xF2]
        for opcode in jamOpcodes {
            table[Int(opcode)] = OpcodeInfo(mnemonic: "JAM", mode: .implied, cycles: 0,
                                            isIllegal: true, halts: true)
        }

        return table
    }

    /// Creates an unknown/invalid opcode entry.
    private static func unknown() -> OpcodeInfo {
        OpcodeInfo(mnemonic: "???", mode: .unknown, cycles: 1, isIllegal: true)
    }
}

// =============================================================================
// MARK: - Monitor Mode Helper Extensions
// =============================================================================

extension OpcodeTable {
    /// Returns the instruction length in bytes for an opcode.
    ///
    /// - Parameter opcode: The opcode byte.
    /// - Returns: Length in bytes (1-3).
    public static func instructionLength(_ opcode: UInt8) -> Int {
        lookup(opcode).byteCount
    }

    /// Returns all opcodes for a given mnemonic.
    ///
    /// - Parameter mnemonic: The instruction mnemonic (case-insensitive).
    /// - Returns: Dictionary mapping AddressingMode to opcode byte.
    public static func opcodesFor(mnemonic: String) -> [AddressingMode: UInt8] {
        let upper = mnemonic.uppercased()
        var result: [AddressingMode: UInt8] = [:]

        for opcode in 0..<256 {
            let info = lookup(UInt8(opcode))
            if info.mnemonic == upper && !info.isIllegal {
                result[info.mode] = UInt8(opcode)
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

        for opcode in 0..<256 {
            let info = lookup(UInt8(opcode))
            if info.mnemonic == upper && info.mode == mode && !info.isIllegal {
                return UInt8(opcode)
            }
        }

        return nil
    }

    /// Returns all valid mnemonics.
    public static var allMnemonics: Set<String> {
        var mnemonics = Set<String>()
        for opcode in 0..<256 {
            let info = lookup(UInt8(opcode))
            if !info.isIllegal && info.mnemonic != "???" {
                mnemonics.insert(info.mnemonic)
            }
        }
        return mnemonics
    }

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
    ///   - pc: The program counter after fetching the branch instruction (PC + 2).
    ///   - offset: The signed 8-bit offset (as Int8).
    /// - Returns: The target address.
    public static func branchTarget(from pc: UInt16, offset: Int8) -> UInt16 {
        // Branch offset is relative to the PC after the branch instruction
        let target = Int(pc) + Int(offset)
        return UInt16(truncatingIfNeeded: target)
    }
}
