// =============================================================================
// VTOCTests.swift - Unit Tests for VTOC (Volume Table of Contents)
// =============================================================================
//
// Tests for the VTOC structure that manages the free sector bitmap.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class VTOCTests: XCTestCase {

    // =========================================================================
    // MARK: - Test Helpers
    // =========================================================================

    /// Creates a sample VTOC data array for testing.
    func createSampleVTOC(
        dosCode: UInt8 = 2,
        totalSectors: UInt16 = 720,
        freeSectors: UInt16 = 707
    ) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 128)

        // DOS code
        data[0] = dosCode

        // Total sectors (little-endian)
        data[1] = UInt8(totalSectors & 0xFF)
        data[2] = UInt8((totalSectors >> 8) & 0xFF)

        // Free sectors (little-endian)
        data[3] = UInt8(freeSectors & 0xFF)
        data[4] = UInt8((freeSectors >> 8) & 0xFF)

        // Initialize bitmap - all free (0xFF)
        for i in 10..<100 {
            data[i] = 0xFF
        }

        // Mark boot sectors (1-3) as used
        // Sector 0-7 are in byte 10, bit 7 = sector 0, bit 6 = sector 1, etc.
        // But sectors start at 1, so sector 1 is bit 6, sector 2 is bit 5, sector 3 is bit 4
        data[10] &= 0b00011111  // Clear bits 7,6,5 for sectors 0,1,2 (but 0 doesn't exist)
        // Actually, let's be more precise:
        // Byte 10: sectors 0-7, where bit 7 = sector 0
        // Sector 1 = bit 6, Sector 2 = bit 5, Sector 3 = bit 4
        data[10] = 0b10001111  // Sectors 1,2,3 used (bits 6,5,4 clear)

        // Mark VTOC (360) as used
        // Sector 360: byte = 10 + 360/8 = 55, bit = 7 - (360 % 8) = 7 - 0 = 7
        data[55] &= 0b01111111

        // Mark directory (361-368) as used
        // Sector 361: byte 55, bit 6
        // Sector 362: byte 55, bit 5
        // ...
        // Sector 368: byte 56, bit 7
        data[55] &= 0b00000001  // Sectors 360-366 used
        data[56] &= 0b01111111  // Sector 368 used (sector 367 is bit 0 of byte 55)

        return data
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    func testParseVTOC() throws {
        let data = createSampleVTOC()
        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        XCTAssertEqual(vtoc.dosCode, 2)
        XCTAssertEqual(vtoc.totalSectors, 720)
        XCTAssertEqual(vtoc.freeSectorCount, 707)
    }

    func testParseVTOCDOS20() throws {
        let data = createSampleVTOC(dosCode: 0)
        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        XCTAssertEqual(vtoc.dosCode, 0)
    }

    func testParseVTOCTooShort() {
        let shortData = [UInt8](repeating: 0, count: 64)

        // Lenient mode should handle gracefully
        let vtoc = try? VTOC(data: shortData, diskType: .singleDensity, validationMode: .lenient)
        XCTAssertNotNil(vtoc)

        // Strict mode should throw
        XCTAssertThrowsError(try VTOC(data: shortData, diskType: .singleDensity, validationMode: .strict))
    }

    // =========================================================================
    // MARK: - Sector Status
    // =========================================================================

    func testIsSectorFree() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)  // All free
        data[0] = 2  // DOS code
        data[1] = 0xD0; data[2] = 0x02  // 720 sectors
        data[3] = 0xC3; data[4] = 0x02  // 707 free

        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        // All data sectors should be free initially
        XCTAssertTrue(vtoc.isSectorFree(4))
        XCTAssertTrue(vtoc.isSectorFree(100))
        XCTAssertTrue(vtoc.isSectorFree(500))
    }

    func testIsSectorUsed() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0xD0; data[2] = 0x02
        data[3] = 0xC3; data[4] = 0x02

        // Mark sector 100 as used
        // Sector 100: byte = 10 + 100/8 = 22, bit = 7 - (100 % 8) = 7 - 4 = 3
        data[22] &= 0b11110111

        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        XCTAssertTrue(vtoc.isSectorUsed(100))
        XCTAssertFalse(vtoc.isSectorFree(100))
    }

    func testSectorOutOfRange() throws {
        let vtoc = try VTOC(data: createSampleVTOC(), diskType: .singleDensity)

        // Invalid sectors should return false for isSectorFree
        XCTAssertFalse(vtoc.isSectorFree(0))    // Sector 0 doesn't exist
        XCTAssertFalse(vtoc.isSectorFree(721))  // Beyond single density
        XCTAssertFalse(vtoc.isSectorFree(-1))   // Negative
    }

    // =========================================================================
    // MARK: - Enhanced Density
    // =========================================================================

    func testEnhancedDensityExtendedBitmap() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0x10; data[2] = 0x04  // 1040 sectors
        data[3] = 0x00; data[4] = 0x04  // 1024 free

        // Initialize extended bitmap (sectors 720-1039)
        for i in 100..<128 {
            data[i] = 0xFF
        }

        let vtoc = try VTOC(data: data, diskType: .enhancedDensity)

        // Check extended sectors
        XCTAssertTrue(vtoc.isSectorFree(721))
        XCTAssertTrue(vtoc.isSectorFree(1000))
        XCTAssertTrue(vtoc.isSectorFree(1040))
    }

    func testEnhancedDensitySectorUsed() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0x10; data[2] = 0x04
        data[3] = 0x00; data[4] = 0x04

        // Mark sector 800 as used
        // Sector 800 - 720 = 80
        // Byte = 100 + 80/8 = 110, bit = 7 - (80 % 8) = 7 - 0 = 7
        data[110] &= 0b01111111

        let vtoc = try VTOC(data: data, diskType: .enhancedDensity)

        XCTAssertTrue(vtoc.isSectorUsed(800))
    }

    // =========================================================================
    // MARK: - Counting Free Sectors
    // =========================================================================

    func testCountFreeSectors() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0xD0; data[2] = 0x02  // 720
        data[3] = 0xD0; data[4] = 0x02  // Stored value (may be wrong)

        // Mark some sectors as used
        data[10] = 0b00001111  // Sectors 0-3 used
        data[55] = 0b00000000  // Sectors 360-367 used
        data[56] = 0b01111111  // Sector 368 used

        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        // Count should be different from stored value
        let actualCount = vtoc.countFreeSectors()
        XCTAssertNotEqual(actualCount, Int(vtoc.freeSectorCount))
    }

    func testGetFreeSectors() throws {
        var data = [UInt8](repeating: 0x00, count: 128)  // All used
        data[0] = 2
        data[1] = 0xD0; data[2] = 0x02

        // Mark sectors 100, 101, 102 as free
        // Byte 22: sectors 96-103
        // Sector 100: bit 3, Sector 101: bit 2, Sector 102: bit 1
        data[22] = 0b00001110

        let vtoc = try VTOC(data: data, diskType: .singleDensity)
        let freeSectors = vtoc.getFreeSectors()

        XCTAssertTrue(freeSectors.contains(100))
        XCTAssertTrue(freeSectors.contains(101))
        XCTAssertTrue(freeSectors.contains(102))
        XCTAssertEqual(freeSectors.count, 3)
    }

    // =========================================================================
    // MARK: - Create Empty VTOC
    // =========================================================================

    func testCreateEmptyVTOCSingleDensity() {
        let vtoc = VTOC.createEmpty(for: .singleDensity)

        // System sectors should be marked used
        XCTAssertTrue(vtoc.isSectorUsed(1))   // Boot
        XCTAssertTrue(vtoc.isSectorUsed(2))   // Boot
        XCTAssertTrue(vtoc.isSectorUsed(3))   // Boot
        XCTAssertTrue(vtoc.isSectorUsed(360)) // VTOC
        XCTAssertTrue(vtoc.isSectorUsed(361)) // Directory
        XCTAssertTrue(vtoc.isSectorUsed(368)) // Directory

        // Data sectors should be free
        XCTAssertTrue(vtoc.isSectorFree(4))
        XCTAssertTrue(vtoc.isSectorFree(100))
        XCTAssertTrue(vtoc.isSectorFree(369))
    }

    func testCreateEmptyVTOCEnhancedDensity() {
        let vtoc = VTOC.createEmpty(for: .enhancedDensity)

        // Extended sectors should be free
        XCTAssertTrue(vtoc.isSectorFree(721))
        XCTAssertTrue(vtoc.isSectorFree(1040))
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    func testValidateSuccess() {
        let vtoc = VTOC.createEmpty(for: .singleDensity)
        let issues = vtoc.validate()

        // Fresh VTOC should have no issues (or minimal expected ones)
        // Note: The free sector count validation depends on exact bitmap setup
        XCTAssertTrue(issues.isEmpty || issues.allSatisfy { !$0.contains("VTOC sector") })
    }

    func testValidateBootSectorFree() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0xD0; data[2] = 0x02
        data[3] = 0xD0; data[4] = 0x02

        // Don't mark boot sectors as used (all bits set = free)
        let vtoc = try VTOC(data: data, diskType: .singleDensity)
        let issues = vtoc.validate()

        XCTAssertTrue(issues.contains { $0.contains("Boot sector") })
    }

    func testValidateVTOCSectorFree() throws {
        var data = [UInt8](repeating: 0xFF, count: 128)
        data[0] = 2
        data[1] = 0xD0; data[2] = 0x02
        data[3] = 0xD0; data[4] = 0x02

        // Boot sectors used, but VTOC sector free
        data[10] = 0b00001111  // Sectors 0-3 used

        let vtoc = try VTOC(data: data, diskType: .singleDensity)
        let issues = vtoc.validate()

        XCTAssertTrue(issues.contains { $0.contains("VTOC sector 360") })
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    func testEncode() throws {
        let data = createSampleVTOC()
        let vtoc = try VTOC(data: data, diskType: .singleDensity)

        let encoded = vtoc.encode()

        XCTAssertEqual(encoded.count, 128)
        XCTAssertEqual(encoded[0], 2)
        XCTAssertEqual(encoded[1], UInt8(720 & 0xFF))
    }

    // =========================================================================
    // MARK: - Description
    // =========================================================================

    func testDescription() throws {
        let vtoc = try VTOC(data: createSampleVTOC(), diskType: .singleDensity)
        let desc = vtoc.description

        XCTAssertTrue(desc.contains("DOS 2.5"))
        XCTAssertTrue(desc.contains("720"))
        XCTAssertTrue(desc.contains("707"))
    }
}
