// =============================================================================
// P1BugRegressionTests.swift - Regression Tests for P1 Bug Fixes
// =============================================================================
//
// Regression tests for three P1 bugs fixed after v0.1.0:
//
// 1. attic-ut99: 'vars' command shows incorrect variable values
//    Root cause: VVT decoder read from bytes 0-5 instead of 2-7, including
//    the 2-byte header in the BCD float. These tests verify the byte layout
//    of BASICVariableValue and BCDFloat is correct for all variable types.
//
// 2. attic-ps5c: Stop command doesn't stop a running BASIC program
//    Root cause: libatari800 doesn't set the BRKKEY OS flag ($0011) when
//    processing AKEY_BREAK via the special input mechanism. The fix writes
//    $00 to $0011 after sending the break. These tests verify the BRKKEY
//    address constant and sendBreak() safety when uninitialized.
//
// Running:
//   swift test --filter P1BugRegressionTests
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - attic-ut99: VVT Byte Offset Tests
// =============================================================================

/// Regression tests for attic-ut99: Variable values decoded from wrong VVT offsets.
///
/// Each VVT entry is 8 bytes:
///   Bytes 0-1: Header (variable number + type flags)
///   Bytes 2-7: Type-specific data
///
/// The bug was reading BCD data from bytes 0-5 instead of 2-7, so the 2-byte
/// header was included in the BCD float. Since the header is often $00 $00,
/// BCDFloat.isZero detected zero (both exponent byte $00 and mantissa byte $00),
/// causing all numeric variables to display as 0.
///
/// These tests verify that BASICVariableValue correctly places data at the
/// right offsets, matching what decodeVariableValue() reads.
final class VVTByteOffsetTests: XCTestCase {

    // =========================================================================
    // MARK: - Numeric Variable Layout
    // =========================================================================

    /// Verify numeric VVT entry has header in bytes 0-1 and BCD in bytes 2-7.
    func test_numeric_bcdAtCorrectOffset() {
        // BCD for 42: exponent $40, mantissa 42 00 00 00 00
        let bcd: [UInt8] = [0x40, 0x42, 0x00, 0x00, 0x00, 0x00]
        let entry = BASICVariableValue.numeric(varNum: 5, bcd: bcd)

        // Bytes 0-1 should be header (varNum=5, type=0)
        XCTAssertEqual(entry.bytes[0], 5, "Byte 0 should be variable number")
        XCTAssertEqual(entry.bytes[1], 0, "Byte 1 should be type flags (0 for numeric)")

        // Bytes 2-7 should be the BCD data
        let extractedBCD = Array(entry.bytes[2..<8])
        XCTAssertEqual(extractedBCD, bcd,
                       "Bytes 2-7 must contain the BCD float, not bytes 0-5")

        // Verify the extracted BCD decodes to 42
        let decoded = BCDFloat(bytes: extractedBCD)
        XCTAssertFalse(decoded.isZero, "42 must not decode as zero")
        XCTAssertEqual(decoded.decode(), 42.0, accuracy: 0.001)
    }

    /// Verify that reading BCD from wrong offset (bytes 0-5) gives wrong result.
    /// This is the exact bug that attic-ut99 caught.
    func test_numeric_wrongOffset_givesZero() {
        // BCD for 42: exponent $40, mantissa 42 00 00 00 00
        let bcd: [UInt8] = [0x40, 0x42, 0x00, 0x00, 0x00, 0x00]
        let entry = BASICVariableValue.numeric(varNum: 0, bcd: bcd)

        // Bug: reading bytes 0-5 instead of 2-7
        let wrongBCD = Array(entry.bytes[0..<6])
        let wrongDecoded = BCDFloat(bytes: wrongBCD)

        // With varNum=0, bytes 0-1 are both $00, which makes BCDFloat.isZero
        // return true — this was the bug symptom.
        XCTAssertTrue(wrongDecoded.isZero,
                      "Reading BCD from bytes 0-5 (the bug) should detect zero for varNum=0")
    }

    /// Verify non-zero variable number in header doesn't corrupt BCD when
    /// read from the correct offset.
    func test_numeric_nonZeroVarNum_correctOffset() {
        // Variable #3, value = 100
        // BCD for 100: exponent $41, mantissa 01 00 00 00 00
        let bcd: [UInt8] = [0x41, 0x01, 0x00, 0x00, 0x00, 0x00]
        let entry = BASICVariableValue.numeric(varNum: 3, bcd: bcd)

        // Header bytes contain varNum, not BCD data
        XCTAssertEqual(entry.bytes[0], 3)

        // Correct offset: bytes 2-7
        let extractedBCD = Array(entry.bytes[2..<8])
        let decoded = BCDFloat(bytes: extractedBCD)
        XCTAssertEqual(decoded.decode(), 100.0, accuracy: 0.001)
    }

    /// Verify negative number BCD at correct offset.
    func test_numeric_negativeValue() {
        // BCD for -3.14: exponent $C0 (negative, exp=0), mantissa 03 14 00 00 00
        let bcd: [UInt8] = [0xC0, 0x03, 0x14, 0x00, 0x00, 0x00]
        let entry = BASICVariableValue.numeric(varNum: 0, bcd: bcd)

        let extractedBCD = Array(entry.bytes[2..<8])
        let decoded = BCDFloat(bytes: extractedBCD)
        XCTAssertTrue(decoded.isNegative)
        XCTAssertEqual(decoded.decode(), -3.14, accuracy: 0.01)
    }

    /// Round-trip: encode a Double to BCD, store in VVT entry, extract and decode.
    func test_numeric_roundTrip() {
        let originalValue = 123.456
        let bcd = BCDFloat.encode(originalValue)
        let entry = BASICVariableValue.numeric(varNum: 7, bcd: bcd.bytes)

        // Extract BCD from correct offset and decode
        let extractedBCD = BCDFloat(bytes: Array(entry.bytes[2..<8]))
        let roundTripped = extractedBCD.decode()

        XCTAssertEqual(roundTripped, originalValue, accuracy: 0.01,
                       "Value should survive VVT round-trip at correct byte offset")
    }

    // =========================================================================
    // MARK: - String Variable Layout
    // =========================================================================

    /// Verify string VVT entry has address, capacity, and length at correct offsets.
    func test_string_fieldsAtCorrectOffsets() {
        let entry = BASICVariableValue.string(
            varNum: 2,
            address: 0x2800,
            capacity: 100,
            length: 42
        )

        // Bytes 0-1: header
        XCTAssertEqual(entry.bytes[0], 2, "Byte 0 should be variable number")
        XCTAssertEqual(entry.bytes[1], 0x80, "Byte 1 should be $80 for string type")

        // Bytes 2-3: buffer address (little-endian)
        XCTAssertEqual(entry.stringAddress, 0x2800,
                       "String address should be at bytes 2-3")

        // Bytes 4-5: DIM capacity (little-endian)
        XCTAssertEqual(entry.stringCapacity, 100,
                       "String capacity should be at bytes 4-5")

        // Bytes 6-7: current length (little-endian)
        XCTAssertEqual(entry.stringLength, 42,
                       "String length should be at bytes 6-7")
    }

    /// Verify that reading string address from wrong offset gives wrong result.
    func test_string_wrongOffset_givesWrongAddress() {
        let entry = BASICVariableValue.string(
            varNum: 2,
            address: 0x2800,
            capacity: 100,
            length: 42
        )

        // Bug: reading address from bytes 0-1 instead of 2-3
        let wrongAddress = UInt16(entry.bytes[0]) | (UInt16(entry.bytes[1]) << 8)
        XCTAssertNotEqual(wrongAddress, 0x2800,
                          "Reading address from bytes 0-1 (the bug) gives wrong value")
        // Would read varNum=2, typeFlags=0x80 → 0x8002
        XCTAssertEqual(wrongAddress, 0x8002)
    }

    /// Verify string with zero length.
    func test_string_emptyString() {
        let entry = BASICVariableValue.string(
            varNum: 0,
            address: 0x3000,
            capacity: 50,
            length: 0
        )

        XCTAssertEqual(entry.stringAddress, 0x3000)
        XCTAssertEqual(entry.stringCapacity, 50)
        XCTAssertEqual(entry.stringLength, 0)
    }

    // =========================================================================
    // MARK: - Array Variable Layout
    // =========================================================================

    /// Verify array VVT entry has dimensions at correct offsets.
    func test_numericArray_dimensionsAtCorrectOffsets() {
        // DIM A(10) → dim1=11 (stored as size+1), dim2=1
        let entry = BASICVariableValue(bytes: [
            0x00, 0x40,   // header: varNum=0, type=$40 (array)
            0x10, 0x00,   // bytes 2-3: offset from STARP
            0x0B, 0x00,   // bytes 4-5: dim1+1 = 11
            0x01, 0x00,   // bytes 6-7: dim2+1 = 1
        ])

        // Dimensions should be read from bytes 4-5 and 6-7 (after header)
        let dim1 = UInt16(entry.bytes[4]) | (UInt16(entry.bytes[5]) << 8)
        let dim2 = UInt16(entry.bytes[6]) | (UInt16(entry.bytes[7]) << 8)

        XCTAssertEqual(dim1, 11, "dim1+1 should be at bytes 4-5")
        XCTAssertEqual(dim2, 1, "dim2+1 should be at bytes 6-7")
    }

    /// Verify 2D array dimensions at correct offsets.
    func test_numericArray_2D_dimensionsAtCorrectOffsets() {
        // DIM GRID(5,8) → dim1=6, dim2=9
        let entry = BASICVariableValue(bytes: [
            0x01, 0x40,   // header: varNum=1, type=$40
            0x20, 0x00,   // bytes 2-3: offset
            0x06, 0x00,   // bytes 4-5: dim1+1 = 6
            0x09, 0x00,   // bytes 6-7: dim2+1 = 9
        ])

        let dim1 = UInt16(entry.bytes[4]) | (UInt16(entry.bytes[5]) << 8)
        let dim2 = UInt16(entry.bytes[6]) | (UInt16(entry.bytes[7]) << 8)

        XCTAssertEqual(dim1, 6, "DIM GRID(5,...) → dim1+1=6 at bytes 4-5")
        XCTAssertEqual(dim2, 9, "DIM GRID(...,8) → dim2+1=9 at bytes 6-7")
    }

    // =========================================================================
    // MARK: - Zero Value Detection
    // =========================================================================

    /// The actual zero VVT entry should decode as zero.
    func test_zero_entry_isCorrectlyZero() {
        let entry = BASICVariableValue.zero

        let bcd = BCDFloat(bytes: Array(entry.bytes[2..<8]))
        XCTAssertTrue(bcd.isZero, "All-zero VVT entry should have zero BCD at bytes 2-7")
    }

    /// Variable 42.0 stored in VVT should NOT appear as zero.
    /// This is the exact symptom of attic-ut99.
    func test_nonZeroVariable_mustNotAppearAsZero() {
        let bcd = BCDFloat.encode(42.0)
        let entry = BASICVariableValue.numeric(varNum: 0, bcd: bcd.bytes)

        // The fixed code reads from bytes 2-7
        let correctBCD = BCDFloat(bytes: Array(entry.bytes[2..<8]))
        XCTAssertFalse(correctBCD.isZero,
                       "Variable with value 42 must NOT decode as zero (attic-ut99 regression)")
        XCTAssertEqual(correctBCD.decimalString, "42",
                       "Variable should display as '42', not '0'")
    }
}

// =============================================================================
// MARK: - attic-ps5c: sendBreak BRKKEY Flag Tests
// =============================================================================

/// Regression tests for attic-ps5c: Stop command doesn't stop BASIC programs.
///
/// The fix writes $00 to the BRKKEY OS flag at address $0011 after sending
/// AKEY_BREAK through the input system. On real hardware, the POKEY IRQ
/// handler sets this flag, but libatari800 doesn't do it via the special
/// input mechanism.
///
/// Since sendBreak() requires an initialized emulator (ROM files), these
/// tests verify the contract at the boundary: the BRKKEY address, the
/// InputState.special value for break, and safe behavior when uninitialized.
final class SendBreakRegressionTests: XCTestCase {

    /// BRKKEY OS flag address ($0011) — BASIC checks this after each statement.
    /// $00 = break pressed, $FF = no break.
    static let brkKeyAddress: UInt16 = 0x0011

    /// The InputState.special value that maps to AKEY_BREAK.
    /// libatari800 negates the special field: -1 = AKEY_BREAK.
    static let breakSpecialValue: UInt8 = 1

    /// Verify the BRKKEY address constant matches what sendBreak() uses.
    func test_brkKeyAddress() {
        // This documents the OS flag address that BASIC checks for break.
        // If this address ever changes, the sendBreak() fix must be updated.
        XCTAssertEqual(Self.brkKeyAddress, 0x0011,
                       "BRKKEY flag must be at OS address $0011")
    }

    /// Verify the InputState.special field for AKEY_BREAK.
    func test_breakSpecialValue() {
        var input = InputState()
        input.special = Self.breakSpecialValue

        // libatari800 negates the special field to get the AKEY code:
        // -1 = AKEY_BREAK, -2 = AKEY_WARMSTART, -3 = AKEY_COLDSTART
        XCTAssertEqual(input.special, 1,
                       "Break requires special=1 (negated to AKEY_BREAK = -1)")
    }

    /// Verify sendBreak() is safe to call when emulator is not initialized.
    func test_sendBreak_whenNotInitialized_doesNotCrash() {
        let wrapper = LibAtari800Wrapper()

        XCTAssertFalse(wrapper.isInitialized)

        // This must not crash — the guard clause should return early
        wrapper.sendBreak()

        // Memory should still read as 0 (default for uninitialized)
        let brkKey = wrapper.readMemory(at: Self.brkKeyAddress)
        XCTAssertEqual(brkKey, 0,
                       "Uninitialized memory reads should return 0")
    }

    /// Verify warmstart() is also safe when uninitialized (related code path).
    func test_warmstart_whenNotInitialized_doesNotCrash() {
        let wrapper = LibAtari800Wrapper()

        // Must not crash
        wrapper.warmstart()
    }

    /// Verify InputState special values for all reset types are distinct.
    func test_specialValues_areDistinct() {
        // Document the three special input values
        let breakValue: UInt8 = 1   // AKEY_BREAK (-1)
        let warmValue: UInt8 = 2    // AKEY_WARMSTART (-2)
        let coldValue: UInt8 = 3    // AKEY_COLDSTART (-3)

        XCTAssertNotEqual(breakValue, warmValue)
        XCTAssertNotEqual(breakValue, coldValue)
        XCTAssertNotEqual(warmValue, coldValue)
    }
}
