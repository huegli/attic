// =============================================================================
// ATRImageTests.swift - Unit Tests for ATR Disk Image Container
// =============================================================================
//
// Tests for the ATRImage class that handles reading ATR disk image files.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class ATRImageTests: XCTestCase {

    // =========================================================================
    // MARK: - Test Helpers
    // =========================================================================

    /// Creates a minimal valid ATR image in memory.
    func createTestATRData(diskType: DiskType = .singleDensity) -> Data {
        var data = Data()

        // Header (16 bytes)
        data.append(0x96)  // Magic byte 1
        data.append(0x02)  // Magic byte 2

        let paragraphs = diskType.paragraphs
        data.append(UInt8(paragraphs & 0xFF))
        data.append(UInt8((paragraphs >> 8) & 0xFF))

        let sectorSize = diskType.sectorSize
        data.append(UInt8(sectorSize & 0xFF))
        data.append(UInt8((sectorSize >> 8) & 0xFF))

        data.append(UInt8((paragraphs >> 16) & 0xFF))

        // CRC and unused (9 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 9))

        // Sectors
        data.append(contentsOf: [UInt8](repeating: 0, count: diskType.totalSize))

        return data
    }

    /// Creates a temporary file URL.
    func tempFileURL(name: String = "test.atr") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    /// Cleans up a temporary file.
    func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // =========================================================================
    // MARK: - Header Parsing
    // =========================================================================

    func testParseValidHeader() throws {
        let data = createTestATRData(diskType: .singleDensity)
        let header = try ATRHeader(data: data)

        XCTAssertEqual(header.sectorSize, 128)
        XCTAssertEqual(header.paragraphs, DiskType.singleDensity.paragraphs)
    }

    func testParseInvalidMagic() {
        var data = createTestATRData()
        data[0] = 0x00  // Wrong magic

        XCTAssertThrowsError(try ATRHeader(data: data)) { error in
            XCTAssertEqual(error as? ATRError, ATRError.invalidMagic)
        }
    }

    func testParseShortHeader() {
        let data = Data([0x96, 0x02, 0x00])  // Only 3 bytes

        XCTAssertThrowsError(try ATRHeader(data: data)) { error in
            XCTAssertEqual(error as? ATRError, ATRError.headerTooShort)
        }
    }

    func testParseInvalidSectorSize() {
        var data = createTestATRData()
        data[4] = 0x00
        data[5] = 0x02  // 512 byte sectors (invalid)

        XCTAssertThrowsError(try ATRHeader(data: data)) { error in
            if case ATRError.invalidSectorSize(let size) = error {
                XCTAssertEqual(size, 512)
            } else {
                XCTFail("Expected invalidSectorSize error")
            }
        }
    }

    // =========================================================================
    // MARK: - ATR Image Loading
    // =========================================================================

    func testLoadFromMemory() throws {
        let data = createTestATRData(diskType: .singleDensity)
        let image = try ATRImage(data: data)

        XCTAssertEqual(image.diskType, .singleDensity)
        XCTAssertEqual(image.sectorCount, 720)
        XCTAssertEqual(image.sectorSize, 128)
        XCTAssertNil(image.url)
    }

    func testLoadFromFile() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let data = createTestATRData(diskType: .singleDensity)
        try data.write(to: url)

        let image = try ATRImage(url: url)

        XCTAssertEqual(image.diskType, .singleDensity)
        XCTAssertEqual(image.url, url)
    }

    func testLoadEnhancedDensity() throws {
        let data = createTestATRData(diskType: .enhancedDensity)
        let image = try ATRImage(data: data)

        XCTAssertEqual(image.diskType, .enhancedDensity)
        XCTAssertEqual(image.sectorCount, 1040)
    }

    func testLoadDoubleDensity() throws {
        let data = createTestATRData(diskType: .doubleDensity)
        let image = try ATRImage(data: data)

        XCTAssertEqual(image.diskType, .doubleDensity)
        XCTAssertEqual(image.sectorCount, 720)
        XCTAssertEqual(image.sectorSize, 256)
    }

    // =========================================================================
    // MARK: - Sector Access
    // =========================================================================

    func testReadSector() throws {
        var data = createTestATRData(diskType: .singleDensity)

        // Write some data to sector 1
        let testPattern: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        let offset = 16  // After header
        for (i, byte) in testPattern.enumerated() {
            data[offset + i] = byte
        }

        let image = try ATRImage(data: data)
        let sector = try image.readSector(1)

        XCTAssertEqual(sector[0], 0xAA)
        XCTAssertEqual(sector[1], 0xBB)
        XCTAssertEqual(sector[2], 0xCC)
        XCTAssertEqual(sector[3], 0xDD)
    }

    func testReadSectorOutOfRange() throws {
        let image = try ATRImage(data: createTestATRData())

        XCTAssertThrowsError(try image.readSector(0)) { error in
            if case ATRError.sectorOutOfRange(let sector, _) = error {
                XCTAssertEqual(sector, 0)
            } else {
                XCTFail("Expected sectorOutOfRange error")
            }
        }

        XCTAssertThrowsError(try image.readSector(721))
    }

    func testActualSectorSizeDoubleDensity() throws {
        let data = createTestATRData(diskType: .doubleDensity)
        let image = try ATRImage(data: data)

        // First 3 sectors are 128 bytes
        XCTAssertEqual(image.actualSectorSize(1), 128)
        XCTAssertEqual(image.actualSectorSize(2), 128)
        XCTAssertEqual(image.actualSectorSize(3), 128)

        // Sector 4+ are 256 bytes
        XCTAssertEqual(image.actualSectorSize(4), 256)
        XCTAssertEqual(image.actualSectorSize(100), 256)
    }

    func testActualSectorSizeSingleDensity() throws {
        let data = createTestATRData(diskType: .singleDensity)
        let image = try ATRImage(data: data)

        // All sectors are 128 bytes
        XCTAssertEqual(image.actualSectorSize(1), 128)
        XCTAssertEqual(image.actualSectorSize(100), 128)
        XCTAssertEqual(image.actualSectorSize(720), 128)
    }

    // =========================================================================
    // MARK: - Writing Sectors
    // =========================================================================

    func testWriteSector() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let data = createTestATRData()
        try data.write(to: url)

        let image = try ATRImage(url: url, readOnly: false)

        let testData: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        try image.writeSector(1, data: testData)

        XCTAssertTrue(image.isModified)

        // Read back and verify
        let readBack = try image.readSector(1)
        XCTAssertEqual(readBack[0], 0x01)
        XCTAssertEqual(readBack[1], 0x02)
    }

    func testWriteSectorReadOnly() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let data = createTestATRData()
        try data.write(to: url)

        let image = try ATRImage(url: url, readOnly: true)

        XCTAssertThrowsError(try image.writeSector(1, data: [0x00])) { error in
            XCTAssertEqual(error as? ATRError, ATRError.readOnly)
        }
    }

    // =========================================================================
    // MARK: - Creating New Images
    // =========================================================================

    func testCreateSingleDensity() throws {
        let url = tempFileURL(name: "new_sd.atr")
        defer { cleanup(url) }

        let image = try ATRImage.create(at: url, type: .singleDensity)

        XCTAssertEqual(image.diskType, .singleDensity)
        XCTAssertEqual(image.sectorCount, 720)
        XCTAssertFalse(image.isModified)
    }

    func testCreateEnhancedDensity() throws {
        let url = tempFileURL(name: "new_ed.atr")
        defer { cleanup(url) }

        let image = try ATRImage.create(at: url, type: .enhancedDensity)

        XCTAssertEqual(image.diskType, .enhancedDensity)
        XCTAssertEqual(image.sectorCount, 1040)
    }

    func testCreateDoubleDensity() throws {
        let url = tempFileURL(name: "new_dd.atr")
        defer { cleanup(url) }

        let image = try ATRImage.create(at: url, type: .doubleDensity)

        XCTAssertEqual(image.diskType, .doubleDensity)
        XCTAssertEqual(image.sectorCount, 720)
        XCTAssertEqual(image.sectorSize, 256)
    }

    func testCreateQuadDensityFails() {
        let url = tempFileURL(name: "new_qd.atr")
        defer { cleanup(url) }

        XCTAssertThrowsError(try ATRImage.create(at: url, type: .quadDensity))
    }

    func testCreateFormatted() throws {
        let url = tempFileURL(name: "formatted.atr")
        defer { cleanup(url) }

        let image = try ATRImage.createFormatted(at: url, type: .singleDensity)

        // Read VTOC and verify it's initialized
        let vtocData = try image.readSector(360)
        let vtoc = try VTOC(data: vtocData, diskType: .singleDensity)

        XCTAssertEqual(vtoc.dosCode, 2)
        XCTAssertGreaterThan(vtoc.countFreeSectors(), 0)
    }

    // =========================================================================
    // MARK: - Saving
    // =========================================================================

    func testSave() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let data = createTestATRData()
        try data.write(to: url)

        let image = try ATRImage(url: url, readOnly: false)
        try image.writeSector(1, data: [0xFF, 0xFE, 0xFD])

        XCTAssertTrue(image.isModified)

        try image.save()

        XCTAssertFalse(image.isModified)

        // Reload and verify
        let reloaded = try ATRImage(url: url)
        let sector = try reloaded.readSector(1)
        XCTAssertEqual(sector[0], 0xFF)
        XCTAssertEqual(sector[1], 0xFE)
    }

    func testSaveAs() throws {
        let url1 = tempFileURL(name: "original.atr")
        let url2 = tempFileURL(name: "copy.atr")
        defer {
            cleanup(url1)
            cleanup(url2)
        }

        let original = try ATRImage.create(at: url1, type: .singleDensity)
        try original.writeSector(1, data: [0x12, 0x34])

        let copy = try original.saveAs(url2)

        XCTAssertEqual(copy.url, url2)

        let sector = try copy.readSector(1)
        XCTAssertEqual(sector[0], 0x12)
        XCTAssertEqual(sector[1], 0x34)
    }

    // =========================================================================
    // MARK: - Description
    // =========================================================================

    func testDescription() throws {
        let url = tempFileURL()
        defer { cleanup(url) }

        let data = createTestATRData()
        try data.write(to: url)

        let image = try ATRImage(url: url)
        let desc = image.description

        XCTAssertTrue(desc.contains("test.atr"))
        XCTAssertTrue(desc.contains("SS/SD"))
        XCTAssertTrue(desc.contains("720"))
    }

    func testSummary() throws {
        let data = createTestATRData()
        let image = try ATRImage(data: data)

        let summary = image.summary

        XCTAssertTrue(summary.contains("Single Density"))
        XCTAssertTrue(summary.contains("720"))
        XCTAssertTrue(summary.contains("128 bytes"))
    }

    // =========================================================================
    // MARK: - Lenient Validation
    // =========================================================================

    func testLenientModePadsTruncatedImage() throws {
        // Create a truncated image
        var data = createTestATRData(diskType: .singleDensity)
        data = data.prefix(1000)  // Truncate to 1000 bytes

        // Should succeed in lenient mode
        let image = try ATRImage(data: Data(data), validationMode: .lenient)
        XCTAssertEqual(image.diskType, .singleDensity)
    }

    func testStrictModeRejectsTruncatedImage() {
        var data = createTestATRData(diskType: .singleDensity)
        data = data.prefix(1000)

        XCTAssertThrowsError(try ATRImage(data: Data(data), validationMode: .strict))
    }
}
