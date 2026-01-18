// =============================================================================
// DiskTypeTests.swift - Unit Tests for Disk Type Definitions
// =============================================================================
//
// Tests for the DiskType enum and DOSLayout constants.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class DiskTypeTests: XCTestCase {

    // =========================================================================
    // MARK: - Disk Type Properties
    // =========================================================================

    func testSingleDensityProperties() {
        let diskType = DiskType.singleDensity

        XCTAssertEqual(diskType.sectorSize, 128)
        XCTAssertEqual(diskType.sectorCount, 720)
        XCTAssertEqual(diskType.totalSize, 720 * 128)
        XCTAssertEqual(diskType.paragraphs, (720 * 128) / 16)
        XCTAssertEqual(diskType.bytesPerSectorForData, 125)
        XCTAssertTrue(diskType.isCreatable)
        XCTAssertFalse(diskType.usesExtendedVTOC)
    }

    func testEnhancedDensityProperties() {
        let diskType = DiskType.enhancedDensity

        XCTAssertEqual(diskType.sectorSize, 128)
        XCTAssertEqual(diskType.sectorCount, 1040)
        XCTAssertEqual(diskType.totalSize, 1040 * 128)
        XCTAssertEqual(diskType.paragraphs, (1040 * 128) / 16)
        XCTAssertEqual(diskType.bytesPerSectorForData, 125)
        XCTAssertTrue(diskType.isCreatable)
        XCTAssertTrue(diskType.usesExtendedVTOC)
    }

    func testDoubleDensityProperties() {
        let diskType = DiskType.doubleDensity

        XCTAssertEqual(diskType.sectorSize, 256)
        XCTAssertEqual(diskType.sectorCount, 720)
        // First 3 sectors are 128 bytes, rest are 256
        let expectedSize = 3 * 128 + 717 * 256
        XCTAssertEqual(diskType.totalSize, expectedSize)
        XCTAssertEqual(diskType.paragraphs, expectedSize / 16)
        XCTAssertEqual(diskType.bytesPerSectorForData, 253)
        XCTAssertTrue(diskType.isCreatable)
        XCTAssertFalse(diskType.usesExtendedVTOC)
    }

    func testQuadDensityProperties() {
        let diskType = DiskType.quadDensity

        XCTAssertEqual(diskType.sectorSize, 256)
        XCTAssertEqual(diskType.sectorCount, 1440)
        XCTAssertFalse(diskType.isCreatable)  // Read-only support
        XCTAssertFalse(diskType.usesExtendedVTOC)
    }

    // =========================================================================
    // MARK: - Detection
    // =========================================================================

    func testDetectSingleDensity() {
        let detected = DiskType.detect(sectorSize: 128, sectorCount: 720)
        XCTAssertEqual(detected, .singleDensity)
    }

    func testDetectEnhancedDensity() {
        let detected = DiskType.detect(sectorSize: 128, sectorCount: 1040)
        XCTAssertEqual(detected, .enhancedDensity)
    }

    func testDetectDoubleDensity() {
        let detected = DiskType.detect(sectorSize: 256, sectorCount: 720)
        XCTAssertEqual(detected, .doubleDensity)
    }

    func testDetectQuadDensity() {
        let detected = DiskType.detect(sectorSize: 256, sectorCount: 1440)
        XCTAssertEqual(detected, .quadDensity)
    }

    func testDetectUnknown() {
        let detected = DiskType.detect(sectorSize: 512, sectorCount: 720)
        XCTAssertNil(detected)
    }

    // =========================================================================
    // MARK: - String Parsing
    // =========================================================================

    func testFromStringSingleDensity() {
        XCTAssertEqual(DiskType.fromString("ss/sd"), .singleDensity)
        XCTAssertEqual(DiskType.fromString("SD"), .singleDensity)
        XCTAssertEqual(DiskType.fromString("single"), .singleDensity)
        XCTAssertEqual(DiskType.fromString("90k"), .singleDensity)
    }

    func testFromStringEnhancedDensity() {
        XCTAssertEqual(DiskType.fromString("ss/ed"), .enhancedDensity)
        XCTAssertEqual(DiskType.fromString("ED"), .enhancedDensity)
        XCTAssertEqual(DiskType.fromString("enhanced"), .enhancedDensity)
        XCTAssertEqual(DiskType.fromString("130k"), .enhancedDensity)
    }

    func testFromStringDoubleDensity() {
        XCTAssertEqual(DiskType.fromString("ss/dd"), .doubleDensity)
        XCTAssertEqual(DiskType.fromString("DD"), .doubleDensity)
        XCTAssertEqual(DiskType.fromString("double"), .doubleDensity)
        XCTAssertEqual(DiskType.fromString("180k"), .doubleDensity)
    }

    func testFromStringQuadDensity() {
        XCTAssertEqual(DiskType.fromString("ds/dd"), .quadDensity)
        XCTAssertEqual(DiskType.fromString("QD"), .quadDensity)
        XCTAssertEqual(DiskType.fromString("quad"), .quadDensity)
        XCTAssertEqual(DiskType.fromString("360k"), .quadDensity)
    }

    func testFromStringInvalid() {
        XCTAssertNil(DiskType.fromString("invalid"))
        XCTAssertNil(DiskType.fromString(""))
        XCTAssertNil(DiskType.fromString("hd"))
    }

    // =========================================================================
    // MARK: - DOS Layout Constants
    // =========================================================================

    func testDOSLayoutConstants() {
        XCTAssertEqual(DOSLayout.bootSectorCount, 3)
        XCTAssertEqual(DOSLayout.firstDataSector, 4)
        XCTAssertEqual(DOSLayout.vtocSector, 360)
        XCTAssertEqual(DOSLayout.firstDirectorySector, 361)
        XCTAssertEqual(DOSLayout.lastDirectorySector, 368)
        XCTAssertEqual(DOSLayout.directorySectorCount, 8)
        XCTAssertEqual(DOSLayout.entriesPerSector, 8)
        XCTAssertEqual(DOSLayout.maxFiles, 64)
    }

    func testSectorTypeChecks() {
        XCTAssertTrue(DOSLayout.isBootSector(1))
        XCTAssertTrue(DOSLayout.isBootSector(3))
        XCTAssertFalse(DOSLayout.isBootSector(4))

        XCTAssertTrue(DOSLayout.isVTOCSector(360))
        XCTAssertFalse(DOSLayout.isVTOCSector(361))

        XCTAssertTrue(DOSLayout.isDirectorySector(361))
        XCTAssertTrue(DOSLayout.isDirectorySector(368))
        XCTAssertFalse(DOSLayout.isDirectorySector(360))
        XCTAssertFalse(DOSLayout.isDirectorySector(369))

        XCTAssertTrue(DOSLayout.isDataSector(4, totalSectors: 720))
        XCTAssertTrue(DOSLayout.isDataSector(369, totalSectors: 720))
        XCTAssertFalse(DOSLayout.isDataSector(1, totalSectors: 720))
        XCTAssertFalse(DOSLayout.isDataSector(360, totalSectors: 720))
        XCTAssertFalse(DOSLayout.isDataSector(361, totalSectors: 720))
    }

    func testEnhancedSectorChecks() {
        XCTAssertTrue(DOSLayout.isEnhancedSector(721))
        XCTAssertTrue(DOSLayout.isEnhancedSector(1040))
        XCTAssertFalse(DOSLayout.isEnhancedSector(720))
        XCTAssertFalse(DOSLayout.isEnhancedSector(1041))
    }
}
