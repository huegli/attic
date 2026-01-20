// =============================================================================
// CPURegisters.swift - 6502 CPU Register State
// =============================================================================
//
// This file defines the CPURegisters struct that represents the complete state
// of the 6502 CPU's registers. The Atari 800 XL uses a 6502C processor (a
// variant of the MOS 6502) which has a simple register set:
//
// - A (Accumulator): 8-bit register for arithmetic and logic operations
// - X (Index X): 8-bit index register, often used for loop counters
// - Y (Index Y): 8-bit index register, similar to X but with different uses
// - S (Stack Pointer): 8-bit pointer to the current stack position ($0100-$01FF)
// - P (Processor Status): 8-bit flags register
// - PC (Program Counter): 16-bit address of the next instruction
//
// The P (status) register contains these flags (bits 7-0):
//   N V - B D I Z C
//   │ │   │ │ │ │ └─ Carry
//   │ │   │ │ │ └─── Zero
//   │ │   │ │ └───── Interrupt Disable
//   │ │   │ └─────── Decimal Mode
//   │ │   └───────── Break Command
//   │ └───────────── Overflow
//   └─────────────── Negative
//
// Bit 5 is unused and always reads as 1.
//
// =============================================================================

import Foundation

/// Represents the complete state of the 6502 CPU registers.
///
/// This struct is used to read and modify CPU state during debugging.
/// It provides formatted output for REPL display and individual flag access.
///
/// Example usage:
///
///     var regs = CPURegisters()
///     regs.a = 0x42
///     regs.pc = 0x0600
///     print(regs.formatted)  // "A=$42 X=$00 Y=$00 S=$FF P=$32 PC=$0600"
///
public struct CPURegisters: Equatable, Sendable {
    // =========================================================================
    // MARK: - Register Values
    // =========================================================================

    /// Accumulator (A) - Primary register for arithmetic operations.
    public var a: UInt8

    /// Index register X - Used for indexing and loop counters.
    public var x: UInt8

    /// Index register Y - Similar to X with different addressing modes.
    public var y: UInt8

    /// Stack pointer (S) - Points to next free location on stack ($0100-$01FF).
    /// Note: The actual stack address is $0100 + S.
    public var s: UInt8

    /// Processor status (P) - Contains CPU flags.
    public var p: UInt8

    /// Program counter (PC) - Address of the next instruction to execute.
    public var pc: UInt16

    // =========================================================================
    // MARK: - Status Flag Constants
    // =========================================================================

    /// Bit positions for status flags in the P register.
    public enum Flag {
        /// Carry flag (bit 0) - Set when arithmetic produces a carry/borrow.
        public static let carry: UInt8 = 0x01

        /// Zero flag (bit 1) - Set when result is zero.
        public static let zero: UInt8 = 0x02

        /// Interrupt disable (bit 2) - When set, IRQ interrupts are disabled.
        public static let interrupt: UInt8 = 0x04

        /// Decimal mode (bit 3) - When set, arithmetic uses BCD encoding.
        public static let decimal: UInt8 = 0x08

        /// Break command (bit 4) - Set by BRK instruction.
        public static let breakCmd: UInt8 = 0x10

        /// Unused (bit 5) - Always reads as 1.
        public static let unused: UInt8 = 0x20

        /// Overflow flag (bit 6) - Set on signed arithmetic overflow.
        public static let overflow: UInt8 = 0x40

        /// Negative flag (bit 7) - Set when result has bit 7 set.
        public static let negative: UInt8 = 0x80
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a CPURegisters instance with specified values.
    ///
    /// - Parameters:
    ///   - a: Accumulator value (default 0)
    ///   - x: Index X value (default 0)
    ///   - y: Index Y value (default 0)
    ///   - s: Stack pointer (default 0xFF, top of stack)
    ///   - p: Processor status (default 0x24, interrupt disable + unused bit)
    ///   - pc: Program counter (default 0x0000)
    public init(
        a: UInt8 = 0,
        x: UInt8 = 0,
        y: UInt8 = 0,
        s: UInt8 = 0xFF,
        p: UInt8 = 0x24,
        pc: UInt16 = 0x0000
    ) {
        self.a = a
        self.x = x
        self.y = y
        self.s = s
        self.p = p
        self.pc = pc
    }

    // =========================================================================
    // MARK: - Flag Accessors
    // =========================================================================

    /// Returns true if the specified flag is set in the status register.
    public func isFlagSet(_ flag: UInt8) -> Bool {
        (p & flag) != 0
    }

    /// Sets or clears the specified flag in the status register.
    public mutating func setFlag(_ flag: UInt8, value: Bool) {
        if value {
            p |= flag
        } else {
            p &= ~flag
        }
    }

    /// Carry flag state.
    public var carry: Bool {
        get { isFlagSet(Flag.carry) }
        set { setFlag(Flag.carry, value: newValue) }
    }

    /// Zero flag state.
    public var zero: Bool {
        get { isFlagSet(Flag.zero) }
        set { setFlag(Flag.zero, value: newValue) }
    }

    /// Interrupt disable flag state.
    public var interruptDisable: Bool {
        get { isFlagSet(Flag.interrupt) }
        set { setFlag(Flag.interrupt, value: newValue) }
    }

    /// Decimal mode flag state.
    public var decimalMode: Bool {
        get { isFlagSet(Flag.decimal) }
        set { setFlag(Flag.decimal, value: newValue) }
    }

    /// Break command flag state.
    public var breakCommand: Bool {
        get { isFlagSet(Flag.breakCmd) }
        set { setFlag(Flag.breakCmd, value: newValue) }
    }

    /// Overflow flag state.
    public var overflow: Bool {
        get { isFlagSet(Flag.overflow) }
        set { setFlag(Flag.overflow, value: newValue) }
    }

    /// Negative flag state.
    public var negative: Bool {
        get { isFlagSet(Flag.negative) }
        set { setFlag(Flag.negative, value: newValue) }
    }

    // =========================================================================
    // MARK: - Formatting
    // =========================================================================

    /// Returns a formatted string of all registers for display.
    ///
    /// Format: "A=$XX X=$XX Y=$XX S=$XX P=$XX PC=$XXXX"
    public var formatted: String {
        String(format: "A=$%02X X=$%02X Y=$%02X S=$%02X P=$%02X PC=$%04X",
               a, x, y, s, p, pc)
    }

    /// Returns a formatted string of the flags.
    ///
    /// Format: "NV.BDIZC" where each position shows the flag letter if set,
    /// or '.' if clear. Bit 5 (unused) is always shown as '.'.
    public var flagsFormatted: String {
        var result = ""
        result += negative ? "N" : "."
        result += overflow ? "V" : "."
        result += "."  // Unused bit, always show as '.'
        result += breakCommand ? "B" : "."
        result += decimalMode ? "D" : "."
        result += interruptDisable ? "I" : "."
        result += zero ? "Z" : "."
        result += carry ? "C" : "."
        return result
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension CPURegisters: CustomStringConvertible {
    /// Returns the formatted register string when converted to String.
    public var description: String {
        formatted
    }
}
