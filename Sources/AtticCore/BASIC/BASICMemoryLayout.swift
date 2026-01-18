// =============================================================================
// BASICMemoryLayout.swift - Atari BASIC Memory Layout Constants
// =============================================================================
//
// This file defines the memory addresses and structures used by Atari BASIC.
// BASIC programs are stored in a specific memory layout with pointers in
// zero page that define the boundaries of each section.
//
// Memory Layout (typical):
// ```
// $0700 (LOMEM) ─────────────────────────────
//               │ Variable Name Table (VNT) │
// VNTP ─────────┼───────────────────────────┤
//               │ $00 (separator byte)      │
// VNTD ─────────┼───────────────────────────┤
//               │ Variable Value Table      │
//               │ (8 bytes per variable)    │
// VVTP ─────────┼───────────────────────────┤
//               │ Statement Table           │
//               │ (tokenized program lines) │
// STMTAB ───────┼───────────────────────────┤
//               │ $00 $00 $00 (end marker)  │
//               │                           │
// STARP ────────┼───────────────────────────┤
//               │ String/Array Storage      │
//               │ (grows upward)            │
//               │                           │
//               │ (free memory)             │
//               │                           │
// RUNSTK ───────┼───────────────────────────┤
//               │ Runtime Stack             │
//               │ (grows downward)          │
// MEMTOP ───────┴───────────────────────────┘
// ```
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Zero Page Pointers
// =============================================================================

/// Zero page addresses for BASIC memory management pointers.
///
/// These addresses contain 16-bit little-endian pointers that define the
/// boundaries of BASIC's memory regions. Reading and updating these pointers
/// is essential for injecting tokenized programs.
public enum BASICPointers {
    /// LOMEM ($80-$81): Start of BASIC memory.
    /// Typically $0700 on a standard Atari 800 XL.
    public static let lomem: UInt16 = 0x0080

    /// VNTP ($82-$83): Variable Name Table Pointer.
    /// Points to the start of the VNT (same as LOMEM initially).
    public static let vntp: UInt16 = 0x0082

    /// VNTD ($84-$85): Variable Name Table Dummy End.
    /// Points to the $00 byte that marks the end of VNT.
    public static let vntd: UInt16 = 0x0084

    /// VVTP ($86-$87): Variable Value Table Pointer.
    /// Points to the start of the VVT (8 bytes per variable).
    public static let vvtp: UInt16 = 0x0086

    /// STMTAB ($88-$89): Statement Table.
    /// Points to the start of the tokenized program.
    public static let stmtab: UInt16 = 0x0088

    /// STMCUR ($8A-$8B): Current Statement Pointer.
    /// Points to the currently executing statement during RUN.
    public static let stmcur: UInt16 = 0x008A

    /// STARP ($8C-$8D): String/Array Table Pointer.
    /// Points to the start of string and array storage.
    public static let starp: UInt16 = 0x008C

    /// RUNSTK ($8E-$8F): Runtime Stack Pointer.
    /// Points to the top of the runtime stack (grows downward).
    public static let runstk: UInt16 = 0x008E

    /// MEMTOP ($90-$91): Top of BASIC memory.
    /// The highest address BASIC can use.
    public static let memtop: UInt16 = 0x0090
}

// =============================================================================
// MARK: - Default Memory Values
// =============================================================================

/// Default memory configuration values for Atari BASIC.
public enum BASICMemoryDefaults {
    /// Default start of BASIC memory.
    public static let defaultLOMEM: UInt16 = 0x0700

    /// Default top of memory for 48K/64K systems.
    public static let defaultMEMTOP: UInt16 = 0x9FFF

    /// Extended memory top for systems with BASIC under ROM.
    public static let extendedMEMTOP: UInt16 = 0xBFFF

    /// Size of each entry in the Variable Value Table.
    public static let vvtEntrySize: Int = 8

    /// Maximum number of variables (indices $80-$FF).
    public static let maxVariables: Int = 128

    /// Maximum line number allowed in BASIC.
    public static let maxLineNumber: Int = 32767

    /// Maximum tokenized line length.
    public static let maxLineLength: Int = 256
}

// =============================================================================
// MARK: - Line Format
// =============================================================================

/// Constants for the tokenized line format.
///
/// Each line in the Statement Table has this structure:
/// ```
/// Offset  Size  Description
/// 0       2     Line number (little-endian)
/// 2       1     Line length (total bytes including this header)
/// 3       n     Tokenized statement data
/// n+3     1     End of line marker ($16)
/// ```
public enum BASICLineFormat {
    /// Offset of line number in a tokenized line.
    public static let lineNumberOffset: Int = 0

    /// Offset of line length byte.
    public static let lineLengthOffset: Int = 2

    /// Offset where tokenized content begins.
    public static let contentOffset: Int = 3

    /// Size of the line header (line number + length byte).
    public static let headerSize: Int = 3

    /// End of line marker byte.
    public static let endOfLineMarker: UInt8 = 0x16

    /// End of program marker (three zero bytes: line number 0, length 0).
    public static let endOfProgramMarker: [UInt8] = [0x00, 0x00, 0x00]
}

// =============================================================================
// MARK: - Memory State
// =============================================================================

/// Represents the current state of BASIC memory pointers.
///
/// This struct captures a snapshot of all relevant BASIC pointers,
/// useful for reading current state before making modifications.
public struct BASICMemoryState: Sendable {
    /// Start of BASIC memory.
    public let lomem: UInt16

    /// Variable Name Table pointer.
    public let vntp: UInt16

    /// Variable Name Table dummy end.
    public let vntd: UInt16

    /// Variable Value Table pointer.
    public let vvtp: UInt16

    /// Statement Table pointer.
    public let stmtab: UInt16

    /// Current statement pointer.
    public let stmcur: UInt16

    /// String/Array table pointer.
    public let starp: UInt16

    /// Runtime stack pointer.
    public let runstk: UInt16

    /// Top of memory.
    public let memtop: UInt16

    /// Creates a memory state with the given pointer values.
    public init(
        lomem: UInt16,
        vntp: UInt16,
        vntd: UInt16,
        vvtp: UInt16,
        stmtab: UInt16,
        stmcur: UInt16,
        starp: UInt16,
        runstk: UInt16,
        memtop: UInt16
    ) {
        self.lomem = lomem
        self.vntp = vntp
        self.vntd = vntd
        self.vvtp = vvtp
        self.stmtab = stmtab
        self.stmcur = stmcur
        self.starp = starp
        self.runstk = runstk
        self.memtop = memtop
    }

    /// The number of variables currently defined.
    ///
    /// Calculated from the size of the Variable Value Table.
    public var variableCount: Int {
        Int(stmtab - vvtp) / BASICMemoryDefaults.vvtEntrySize
    }

    /// The size of the Variable Name Table in bytes.
    public var vntSize: Int {
        Int(vntd - vntp)
    }

    /// The size of the Variable Value Table in bytes.
    public var vvtSize: Int {
        Int(stmtab - vvtp)
    }

    /// The size of the Statement Table (program) in bytes.
    public var programSize: Int {
        Int(starp - stmtab)
    }

    /// Available free memory between STARP and RUNSTK.
    public var freeMemory: Int {
        Int(runstk - starp)
    }

    /// Creates a fresh memory state for an empty BASIC program.
    ///
    /// - Parameters:
    ///   - lomem: Start of BASIC memory.
    ///   - memtop: Top of BASIC memory.
    /// - Returns: A clean memory state ready for a new program.
    public static func empty(
        lomem: UInt16 = BASICMemoryDefaults.defaultLOMEM,
        memtop: UInt16 = BASICMemoryDefaults.defaultMEMTOP
    ) -> BASICMemoryState {
        // Empty program: VNT is empty, VVT is empty, STMTAB points to end marker
        let stmtab = lomem + 1  // After the $00 VNT terminator
        let starp = stmtab + 3  // After the end-of-program marker

        return BASICMemoryState(
            lomem: lomem,
            vntp: lomem,
            vntd: lomem,        // Empty VNT
            vvtp: lomem + 1,    // After VNT terminator
            stmtab: stmtab,
            stmcur: stmtab,
            starp: starp,
            runstk: memtop,
            memtop: memtop
        )
    }
}

// =============================================================================
// MARK: - Memory Reader Protocol
// =============================================================================

/// Protocol for reading BASIC memory state from the emulator.
///
/// This protocol abstracts the memory access so the BASIC subsystem
/// can work with different emulator backends.
public protocol BASICMemoryReader: Sendable {
    /// Reads a 16-bit little-endian word from memory.
    func readWord(at address: UInt16) async -> UInt16

    /// Reads a block of bytes from memory.
    func readBlock(at address: UInt16, count: Int) async -> [UInt8]
}

/// Protocol for writing BASIC memory.
public protocol BASICMemoryWriter: Sendable {
    /// Writes a 16-bit little-endian word to memory.
    func writeWord(at address: UInt16, value: UInt16) async

    /// Writes a block of bytes to memory.
    func writeBlock(at address: UInt16, bytes: [UInt8]) async
}

// =============================================================================
// MARK: - Memory State Reader
// =============================================================================

/// Extension to read BASIC memory state using the memory reader protocol.
extension BASICMemoryState {
    /// Reads the current BASIC memory state from the emulator.
    ///
    /// - Parameter reader: A memory reader (typically the EmulatorEngine).
    /// - Returns: The current memory state.
    public static func read(from reader: BASICMemoryReader) async -> BASICMemoryState {
        async let lomem = reader.readWord(at: BASICPointers.lomem)
        async let vntp = reader.readWord(at: BASICPointers.vntp)
        async let vntd = reader.readWord(at: BASICPointers.vntd)
        async let vvtp = reader.readWord(at: BASICPointers.vvtp)
        async let stmtab = reader.readWord(at: BASICPointers.stmtab)
        async let stmcur = reader.readWord(at: BASICPointers.stmcur)
        async let starp = reader.readWord(at: BASICPointers.starp)
        async let runstk = reader.readWord(at: BASICPointers.runstk)
        async let memtop = reader.readWord(at: BASICPointers.memtop)

        return await BASICMemoryState(
            lomem: lomem,
            vntp: vntp,
            vntd: vntd,
            vvtp: vvtp,
            stmtab: stmtab,
            stmcur: stmcur,
            starp: starp,
            runstk: runstk,
            memtop: memtop
        )
    }
}

// =============================================================================
// MARK: - Memory Operations Helper
// =============================================================================

/// Helper functions for BASIC memory operations.
public enum BASICMemoryOps {
    /// Calculates where to insert a new line in the statement table.
    ///
    /// Lines are stored in ascending order by line number. This function
    /// finds the correct position for a new/replacement line.
    ///
    /// - Parameters:
    ///   - lineNumber: The line number to insert.
    ///   - stmtab: Start of statement table.
    ///   - starp: End of statement table.
    ///   - reader: Memory reader for accessing current program.
    /// - Returns: Tuple of (insertAddress, existingLineLength or 0).
    public static func findLinePosition(
        lineNumber: UInt16,
        stmtab: UInt16,
        starp: UInt16,
        reader: BASICMemoryReader
    ) async -> (address: UInt16, existingLength: Int) {
        var address = stmtab

        while address < starp {
            let currentLineNum = await reader.readWord(at: address)

            // End of program marker
            if currentLineNum == 0 {
                return (address, 0)
            }

            // Found the line
            if currentLineNum == lineNumber {
                let lineLength = Int(await reader.readBlock(at: address + 2, count: 1).first ?? 0)
                return (address, lineLength)
            }

            // Past where this line should go
            if currentLineNum > lineNumber {
                return (address, 0)
            }

            // Move to next line
            let lineLength = await reader.readBlock(at: address + 2, count: 1).first ?? 0
            address = address &+ UInt16(lineLength)
        }

        return (address, 0)
    }

    /// Calculates the bytes needed to shift when inserting/replacing a line.
    ///
    /// - Parameters:
    ///   - newLineLength: Length of the new line being inserted.
    ///   - existingLineLength: Length of existing line at same number (0 if none).
    /// - Returns: The number of bytes to shift (positive = grow, negative = shrink).
    public static func calculateShift(
        newLineLength: Int,
        existingLineLength: Int
    ) -> Int {
        if existingLineLength == 0 {
            // New line, need space for entire line
            return newLineLength
        } else {
            // Replacing existing line
            return newLineLength - existingLineLength
        }
    }
}
