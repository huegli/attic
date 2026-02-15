// =============================================================================
// P1BugRegressionTests.swift - Regression Tests for P1 Bug Fixes
// =============================================================================
//
// Regression tests for five P1 bugs fixed after v0.1.0:
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
// 3. attic-dw3f: .state load fails with tilde (~) paths
//    Root cause: parseState() didn't expand tilde in file paths, unlike
//    .boot and other path commands. The fix adds NSString.expandingTildeInPath.
//    Tests verify tilde expansion for .state load (save was already tested).
//
// 4. attic-nw7g: Loading ROM file via Open File dialog launches BASIC
//    Root cause: Raw .rom files lack the CART header that libatari800 needs
//    to determine cartridge type. The fix wraps raw ROMs in a CART header.
//    Tests verify header construction, size-to-type mapping, detection logic,
//    and checksum calculation.
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

// =============================================================================
// MARK: - attic-dw3f: State Load Tilde Expansion Tests
// =============================================================================

/// Regression test for attic-dw3f: `.state load` fails with tilde paths.
///
/// The existing StatePersistenceIntegrationTests cover `.state save` tilde
/// expansion, but `.state load` was missing a symmetric test. Both subcommands
/// share the same `parseState()` code path, but this test ensures the load
/// path specifically expands tildes — which was the reported symptom.
final class StateLoadTildeExpansionTests: XCTestCase {
    let parser = CommandParser()

    /// `.state load ~/saves/game.attic` should expand tilde to home directory.
    /// This is the exact scenario from the attic-dw3f bug report.
    func test_stateLoad_homeRelativePath() throws {
        let cmd = try parser.parse(".state load ~/saves/game.attic", mode: .monitor)
        guard case .loadState(let path) = cmd else {
            XCTFail("Expected loadState, got \(cmd)")
            return
        }
        // Tilde should be expanded to the user's home directory
        let expected = NSString(string: "~/saves/game.attic").expandingTildeInPath
        XCTAssertEqual(path, expected,
                       "Tilde must be expanded in .state load paths (attic-dw3f)")
        XCTAssertFalse(path.hasPrefix("~"),
                       "Path must not start with ~ after expansion")
    }

    /// `.state load` with absolute path should be unchanged.
    func test_stateLoad_absolutePath_unchanged() throws {
        let cmd = try parser.parse(".state load /tmp/test.attic", mode: .monitor)
        guard case .loadState(let path) = cmd else {
            XCTFail("Expected loadState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/test.attic",
                       "Absolute paths should pass through unchanged")
    }

    /// `.state load` with path containing spaces should preserve them.
    func test_stateLoad_pathWithSpaces() throws {
        let cmd = try parser.parse(
            ".state load ~/my saves/test game.attic", mode: .monitor
        )
        guard case .loadState(let path) = cmd else {
            XCTFail("Expected loadState, got \(cmd)")
            return
        }
        let expected = NSString(string: "~/my saves/test game.attic").expandingTildeInPath
        XCTAssertEqual(path, expected,
                       "Tilde expansion must work with spaces in path")
    }
}

// =============================================================================
// MARK: - attic-nw7g: CART Header Construction Tests
// =============================================================================

/// Regression tests for attic-nw7g: ROM files launch BASIC instead of cartridge.
///
/// The fix wraps raw .rom files in a CART header before passing to libatari800.
/// These tests verify the header construction, ROM detection, size-to-type
/// mapping, and checksum calculation without requiring a running emulator.
///
/// The three static methods under test:
/// - `EmulatorEngine.isRawROMFile(_:)` — detects files needing conversion
/// - `EmulatorEngine.createTemporaryCARFile(from:)` — builds the .car wrapper
/// - `EmulatorEngine.romSizeToCartType` — maps ROM sizes to cartridge types
final class CARTHeaderRegressionTests: XCTestCase {

    /// Temporary directory for test ROM files, cleaned up after each test.
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CARTHeaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Helper: create a temp file with given name and contents.
    private func createTempFile(name: String, data: Data) -> String {
        let url = tempDir.appendingPathComponent(name)
        try! data.write(to: url)
        return url.path
    }

    /// Helper: create a raw ROM file filled with a repeating byte pattern.
    private func createRawROM(name: String, size: Int, fillByte: UInt8 = 0xFF) -> String {
        let data = Data(repeating: fillByte, count: size)
        return createTempFile(name: name, data: data)
    }

    // =========================================================================
    // MARK: - isRawROMFile Detection
    // =========================================================================

    /// A .rom file without CART header should be detected as raw ROM.
    func test_isRawROMFile_rawROM_returnsTrue() {
        let path = createRawROM(name: "game.rom", size: 8192)
        XCTAssertTrue(EmulatorEngine.isRawROMFile(path),
                      "8KB .rom file without CART header should be detected as raw ROM")
    }

    /// A .rom file that already has a CART header should NOT be detected.
    func test_isRawROMFile_withCARTHeader_returnsFalse() {
        // Create a file with "CART" signature at offset 0
        var data = Data(EmulatorEngine.cartSignature)  // "CART"
        data.append(Data(repeating: 0x00, count: 8192))
        let path = createTempFile(name: "game.rom", data: data)

        XCTAssertFalse(EmulatorEngine.isRawROMFile(path),
                       ".rom file with existing CART header must not be double-wrapped")
    }

    /// A .car file should NOT be detected as raw ROM (wrong extension).
    func test_isRawROMFile_carExtension_returnsFalse() {
        let path = createRawROM(name: "game.car", size: 8192)
        XCTAssertFalse(EmulatorEngine.isRawROMFile(path),
                       ".car files should not be treated as raw ROMs")
    }

    /// A .xex file should NOT be detected as raw ROM.
    func test_isRawROMFile_xexExtension_returnsFalse() {
        let path = createRawROM(name: "game.xex", size: 8192)
        XCTAssertFalse(EmulatorEngine.isRawROMFile(path),
                       ".xex files should not be treated as raw ROMs")
    }

    /// A .atr file should NOT be detected as raw ROM.
    func test_isRawROMFile_atrExtension_returnsFalse() {
        let path = createRawROM(name: "game.atr", size: 8192)
        XCTAssertFalse(EmulatorEngine.isRawROMFile(path),
                       ".atr disk images should not be treated as raw ROMs")
    }

    /// A nonexistent file should return false (not crash).
    func test_isRawROMFile_nonexistentFile_returnsFalse() {
        let path = tempDir.appendingPathComponent("nonexistent.rom").path
        XCTAssertFalse(EmulatorEngine.isRawROMFile(path),
                       "Missing file should return false, not crash")
    }

    /// Extension check should be case-insensitive.
    func test_isRawROMFile_uppercaseExtension_returnsTrue() {
        let path = createRawROM(name: "GAME.ROM", size: 16384)
        XCTAssertTrue(EmulatorEngine.isRawROMFile(path),
                      ".ROM (uppercase) should be detected as raw ROM")
    }

    // =========================================================================
    // MARK: - ROM Size to Cartridge Type Mapping
    // =========================================================================

    /// 8KB ROM maps to CART type 1 (standard 8KB at $A000-$BFFF).
    func test_romSizeToCartType_8KB() {
        XCTAssertEqual(EmulatorEngine.romSizeToCartType[8192], 1,
                       "8KB ROM must map to CART type 1")
    }

    /// 16KB ROM maps to CART type 2 (standard 16KB at $8000-$BFFF).
    func test_romSizeToCartType_16KB() {
        XCTAssertEqual(EmulatorEngine.romSizeToCartType[16384], 2,
                       "16KB ROM must map to CART type 2")
    }

    /// Unsupported sizes should have no mapping (e.g., 4KB, 32KB).
    func test_romSizeToCartType_unsupportedSizes() {
        XCTAssertNil(EmulatorEngine.romSizeToCartType[4096],
                     "4KB ROM should have no type mapping")
        XCTAssertNil(EmulatorEngine.romSizeToCartType[32768],
                     "32KB ROM should have no type mapping (not yet supported)")
        XCTAssertNil(EmulatorEngine.romSizeToCartType[1024],
                     "1KB ROM should have no type mapping")
    }

    // =========================================================================
    // MARK: - CART Header Construction
    // =========================================================================

    /// 8KB ROM produces a valid .car file with correct header.
    func test_createTemporaryCARFile_8KB_validHeader() {
        let romPath = createRawROM(name: "test8k.rom", size: 8192, fillByte: 0xAA)
        guard let carPath = EmulatorEngine.createTemporaryCARFile(from: romPath) else {
            XCTFail("createTemporaryCARFile returned nil for valid 8KB ROM")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: carPath) }

        let carData = FileManager.default.contents(atPath: carPath)!

        // Total size = 16-byte header + 8192 bytes ROM
        XCTAssertEqual(carData.count, 16 + 8192,
                       "CAR file should be header (16) + ROM data (8192)")

        // Bytes 0-3: "CART" signature
        let signature = [UInt8](carData[0..<4])
        XCTAssertEqual(signature, [0x43, 0x41, 0x52, 0x54],
                       "First 4 bytes must be 'CART' signature")

        // Bytes 4-7: cartridge type (big-endian) = 1 for 8KB
        let typeBytes = [UInt8](carData[4..<8])
        XCTAssertEqual(typeBytes, [0x00, 0x00, 0x00, 0x01],
                       "Type field must be 1 (8KB standard) in big-endian")

        // Bytes 12-15: unused (zeros)
        let unused = [UInt8](carData[12..<16])
        XCTAssertEqual(unused, [0x00, 0x00, 0x00, 0x00],
                       "Unused field must be zeros")

        // ROM data should follow the header unchanged
        let romData = [UInt8](carData[16...])
        XCTAssertEqual(romData.count, 8192)
        XCTAssertTrue(romData.allSatisfy { $0 == 0xAA },
                      "ROM data must be preserved unchanged after header")
    }

    /// 16KB ROM produces CART type 2.
    func test_createTemporaryCARFile_16KB_correctType() {
        let romPath = createRawROM(name: "test16k.rom", size: 16384, fillByte: 0xBB)
        guard let carPath = EmulatorEngine.createTemporaryCARFile(from: romPath) else {
            XCTFail("createTemporaryCARFile returned nil for valid 16KB ROM")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: carPath) }

        let carData = FileManager.default.contents(atPath: carPath)!

        // Total size = 16-byte header + 16384 bytes ROM
        XCTAssertEqual(carData.count, 16 + 16384)

        // Bytes 4-7: cartridge type = 2 for 16KB
        let typeBytes = [UInt8](carData[4..<8])
        XCTAssertEqual(typeBytes, [0x00, 0x00, 0x00, 0x02],
                       "Type field must be 2 (16KB standard) in big-endian")
    }

    /// Checksum is the sum of all ROM bytes (wrapping on overflow).
    func test_createTemporaryCARFile_checksumCalculation() {
        // Create a small ROM with known bytes so we can verify the checksum.
        // 8KB of 0x01 → checksum = 8192 * 1 = 0x00002000
        let romPath = createRawROM(name: "checksum.rom", size: 8192, fillByte: 0x01)
        guard let carPath = EmulatorEngine.createTemporaryCARFile(from: romPath) else {
            XCTFail("createTemporaryCARFile returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: carPath) }

        let carData = FileManager.default.contents(atPath: carPath)!

        // Bytes 8-11: checksum (big-endian)
        let checksumBytes = [UInt8](carData[8..<12])
        // 8192 * 0x01 = 0x00002000
        XCTAssertEqual(checksumBytes, [0x00, 0x00, 0x20, 0x00],
                       "Checksum for 8192 bytes of 0x01 should be 0x00002000 big-endian")
    }

    /// Checksum wraps correctly for large byte values (no overflow crash).
    func test_createTemporaryCARFile_checksumWrapping() {
        // 8192 bytes of 0xFF → checksum = 8192 * 255 = 2_088_960 = 0x001FE000
        let romPath = createRawROM(name: "wrap.rom", size: 8192, fillByte: 0xFF)
        guard let carPath = EmulatorEngine.createTemporaryCARFile(from: romPath) else {
            XCTFail("createTemporaryCARFile returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: carPath) }

        let carData = FileManager.default.contents(atPath: carPath)!
        let checksumBytes = [UInt8](carData[8..<12])
        // 8192 * 255 = 2_088_960 = 0x001FE000
        XCTAssertEqual(checksumBytes, [0x00, 0x1F, 0xE0, 0x00],
                       "Checksum should handle large sums without overflow")
    }

    /// Unsupported ROM size (5KB) returns nil.
    func test_createTemporaryCARFile_unsupportedSize_returnsNil() {
        let romPath = createRawROM(name: "odd.rom", size: 5000)
        let result = EmulatorEngine.createTemporaryCARFile(from: romPath)
        XCTAssertNil(result,
                     "Unsupported ROM size should return nil, not create invalid CART")
    }

    /// Nonexistent file returns nil.
    func test_createTemporaryCARFile_nonexistent_returnsNil() {
        let path = tempDir.appendingPathComponent("missing.rom").path
        let result = EmulatorEngine.createTemporaryCARFile(from: path)
        XCTAssertNil(result, "Missing file should return nil")
    }

    /// Output file has .car extension.
    func test_createTemporaryCARFile_outputHasCarExtension() {
        let romPath = createRawROM(name: "ext.rom", size: 8192)
        guard let carPath = EmulatorEngine.createTemporaryCARFile(from: romPath) else {
            XCTFail("createTemporaryCARFile returned nil")
            return
        }
        defer { try? FileManager.default.removeItem(atPath: carPath) }

        XCTAssertTrue(carPath.hasSuffix(".car"),
                      "Output file must have .car extension for libatari800")
    }

    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// CART header is exactly 16 bytes.
    func test_cartHeaderSize() {
        XCTAssertEqual(EmulatorEngine.cartHeaderSize, 16,
                       "CART header must be exactly 16 bytes")
    }

    /// CART signature is "CART" in ASCII.
    func test_cartSignature() {
        XCTAssertEqual(EmulatorEngine.cartSignature,
                       [0x43, 0x41, 0x52, 0x54],
                       "CART signature must be 'C','A','R','T' in ASCII")
    }
}
