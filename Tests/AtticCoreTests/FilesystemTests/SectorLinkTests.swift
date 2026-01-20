// =============================================================================
// SectorLinkTests.swift - Unit Tests for Sector Link Parsing
// =============================================================================
//
// Tests for the SectorLink structure that parses file chain links
// from the last 3 bytes of each data sector.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class SectorLinkTests: XCTestCase {

    // =========================================================================
    // MARK: - 128-Byte Sector Format
    // =========================================================================

    func testParse128ByteIntermediateSector() {
        // Create a 128-byte sector with link bytes at the end
        // File ID = 5 (0x14 >> 2 = 5), Next sector = 47 (0x002F)
        var sectorData = [UInt8](repeating: 0, count: 128)

        // Byte 125: File ID (bits 7-2) | Next sector high (bits 1-0)
        // File ID 5 = 0b00010100 (5 << 2 = 0x14)
        // Next sector 47 = 0x002F, high bits = 0
        sectorData[125] = 0x14  // (5 << 2) | 0
        sectorData[126] = 0x2F  // 47 low byte
        sectorData[127] = 0x00  // Unused

        // Use isKnownLastSector: false because 47 is ambiguous (could be byte count)
        let link = SectorLink(sectorData: sectorData, sectorSize: 128, isKnownLastSector: false)

        XCTAssertEqual(link.fileID, 5)
        XCTAssertEqual(link.nextSector, 47)
        XCTAssertFalse(link.isLastSector)
        XCTAssertEqual(link.bytesInSector, 125)
        XCTAssertEqual(link.sectorSize, 128)
    }

    func testParse128ByteLastSector() {
        // Last sector: next sector = 0, byte 126 contains data count
        var sectorData = [UInt8](repeating: 0, count: 128)

        // File ID = 10, Last sector with 100 bytes of data
        sectorData[125] = 0x28  // (10 << 2)
        sectorData[126] = 100   // Byte count in last sector
        sectorData[127] = 0x00

        let link = SectorLink(sectorData: sectorData, sectorSize: 128)

        XCTAssertEqual(link.fileID, 10)
        XCTAssertEqual(link.nextSector, 0)
        XCTAssertTrue(link.isLastSector)
        XCTAssertEqual(link.bytesInSector, 100)
    }

    func testParse128ByteHighSectorNumber() {
        // Test sector number > 255 (requires high bits)
        // Sector 300 = 0x012C
        var sectorData = [UInt8](repeating: 0, count: 128)

        // File ID = 3, Next sector = 300
        // High bits of 300: 0x01 (goes in bits 1-0 of byte 125)
        // Low byte: 0x2C
        sectorData[125] = (3 << 2) | 0x01  // 0x0D
        sectorData[126] = 0x2C             // 300 low byte
        sectorData[127] = 0x00

        let link = SectorLink(sectorData: sectorData, sectorSize: 128)

        XCTAssertEqual(link.fileID, 3)
        XCTAssertEqual(link.nextSector, 300)
        XCTAssertFalse(link.isLastSector)
    }

    // =========================================================================
    // MARK: - 256-Byte Sector Format
    // =========================================================================

    func testParse256ByteIntermediateSector() {
        // Create a 256-byte sector with link bytes at the end
        var sectorData = [UInt8](repeating: 0, count: 256)

        // File ID = 7, Next sector = 150
        sectorData[253] = 7      // File ID (full byte)
        sectorData[254] = 150    // Next sector low byte
        sectorData[255] = 0      // Next sector high (bits 1-0)

        // Use isKnownLastSector: false because 150 is ambiguous (could be byte count)
        let link = SectorLink(sectorData: sectorData, sectorSize: 256, isKnownLastSector: false)

        XCTAssertEqual(link.fileID, 7)
        XCTAssertEqual(link.nextSector, 150)
        XCTAssertFalse(link.isLastSector)
        XCTAssertEqual(link.bytesInSector, 253)
        XCTAssertEqual(link.sectorSize, 256)
    }

    func testParse256ByteLastSector() {
        var sectorData = [UInt8](repeating: 0, count: 256)

        // File ID = 15, Last sector with 200 bytes
        sectorData[253] = 15     // File ID
        sectorData[254] = 200    // Byte count
        sectorData[255] = 0      // Must be 0 for last sector

        let link = SectorLink(sectorData: sectorData, sectorSize: 256)

        XCTAssertEqual(link.fileID, 15)
        XCTAssertEqual(link.nextSector, 0)
        XCTAssertTrue(link.isLastSector)
        XCTAssertEqual(link.bytesInSector, 200)
    }

    func testParse256ByteHighSectorNumber() {
        var sectorData = [UInt8](repeating: 0, count: 256)

        // File ID = 20, Next sector = 500 (0x01F4)
        sectorData[253] = 20     // File ID
        sectorData[254] = 0xF4   // 500 low byte
        sectorData[255] = 0x01   // 500 high (bits 1-0)

        let link = SectorLink(sectorData: sectorData, sectorSize: 256)

        XCTAssertEqual(link.fileID, 20)
        XCTAssertEqual(link.nextSector, 500)
        XCTAssertFalse(link.isLastSector)
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    func testEncode128ByteIntermediateSector() {
        let link = SectorLink(fileID: 5, nextSector: 47, bytesInSector: 125, sectorSize: 128)
        let encoded = link.encode()

        XCTAssertEqual(encoded.count, 3)
        XCTAssertEqual(encoded[0], 0x14)  // (5 << 2) | 0
        XCTAssertEqual(encoded[1], 0x2F)  // 47
        XCTAssertEqual(encoded[2], 0x00)
    }

    func testEncode128ByteLastSector() {
        let link = SectorLink(fileID: 10, nextSector: 0, bytesInSector: 100, sectorSize: 128)
        let encoded = link.encode()

        XCTAssertEqual(encoded.count, 3)
        XCTAssertEqual(encoded[0], 0x28)  // (10 << 2)
        XCTAssertEqual(encoded[1], 100)   // Byte count
        XCTAssertEqual(encoded[2], 0x00)
    }

    func testEncode128ByteHighSectorNumber() {
        let link = SectorLink(fileID: 3, nextSector: 300, bytesInSector: 125, sectorSize: 128)
        let encoded = link.encode()

        XCTAssertEqual(encoded[0], 0x0D)  // (3 << 2) | 1
        XCTAssertEqual(encoded[1], 0x2C)  // 300 & 0xFF
    }

    func testEncode256ByteSector() {
        let link = SectorLink(fileID: 7, nextSector: 150, bytesInSector: 253, sectorSize: 256)
        let encoded = link.encode()

        XCTAssertEqual(encoded.count, 3)
        XCTAssertEqual(encoded[0], 7)    // File ID
        XCTAssertEqual(encoded[1], 150)  // Next sector low
        XCTAssertEqual(encoded[2], 0)    // Next sector high
    }

    // =========================================================================
    // MARK: - Round-Trip Tests
    // =========================================================================

    func testRoundTrip128Byte() {
        let original = SectorLink(fileID: 12, nextSector: 500, bytesInSector: 125, sectorSize: 128)
        let encoded = original.encode()

        var sectorData = [UInt8](repeating: 0, count: 128)
        sectorData[125] = encoded[0]
        sectorData[126] = encoded[1]
        sectorData[127] = encoded[2]

        let parsed = SectorLink(sectorData: sectorData, sectorSize: 128)

        XCTAssertEqual(parsed.fileID, original.fileID)
        XCTAssertEqual(parsed.nextSector, original.nextSector)
        XCTAssertEqual(parsed.isLastSector, original.isLastSector)
    }

    func testRoundTrip256Byte() {
        let original = SectorLink(fileID: 25, nextSector: 800, bytesInSector: 253, sectorSize: 256)
        let encoded = original.encode()

        var sectorData = [UInt8](repeating: 0, count: 256)
        sectorData[253] = encoded[0]
        sectorData[254] = encoded[1]
        sectorData[255] = encoded[2]

        let parsed = SectorLink(sectorData: sectorData, sectorSize: 256)

        XCTAssertEqual(parsed.fileID, original.fileID)
        XCTAssertEqual(parsed.nextSector, original.nextSector)
        XCTAssertEqual(parsed.isLastSector, original.isLastSector)
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    func testValidationSuccess() {
        let link = SectorLink(fileID: 5, nextSector: 100, bytesInSector: 125, sectorSize: 128)
        let error = link.validate(expectedFileID: 5, maxSector: 720)
        XCTAssertNil(error)
    }

    func testValidationWrongFileID() {
        let link = SectorLink(fileID: 5, nextSector: 100, bytesInSector: 125, sectorSize: 128)
        let error = link.validate(expectedFileID: 10, maxSector: 720)
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("belongs to file 5"))
    }

    func testValidationSectorOutOfRange() {
        let link = SectorLink(fileID: 5, nextSector: 800, bytesInSector: 125, sectorSize: 128)
        let error = link.validate(expectedFileID: 5, maxSector: 720)
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("exceeds disk size"))
    }

    // =========================================================================
    // MARK: - Edge Cases
    // =========================================================================

    func testEmptySectorData() {
        let sectorData: [UInt8] = []
        let link = SectorLink(sectorData: sectorData, sectorSize: 128)

        // Should handle gracefully
        XCTAssertEqual(link.fileID, 0)
        XCTAssertTrue(link.isLastSector)
    }

    func testShortSectorData() {
        let sectorData = [UInt8](repeating: 0, count: 64)  // Too short
        let link = SectorLink(sectorData: sectorData, sectorSize: 128)

        // Should handle gracefully
        XCTAssertEqual(link.fileID, 0)
        XCTAssertTrue(link.isLastSector)
    }

    func testDescription() {
        let intermediateLink = SectorLink(fileID: 5, nextSector: 100, bytesInSector: 125, sectorSize: 128)
        XCTAssertTrue(intermediateLink.description.contains("next: 100"))

        let lastLink = SectorLink(fileID: 5, nextSector: 0, bytesInSector: 80, sectorSize: 128)
        XCTAssertTrue(lastLink.description.contains("LAST"))
        XCTAssertTrue(lastLink.description.contains("bytes: 80"))
    }
}
