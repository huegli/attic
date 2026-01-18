// =============================================================================
// ATRFileSystemTests.swift - Unit Tests for ATR Parsing and DOS File System
// =============================================================================
//
// This file contains unit tests for the Phase 13 DOS mode implementation:
// - ATRImage: ATR container format parsing and manipulation
// - AtariFileSystem: DOS 2.x file system operations
// - DiskManager: Mounted disk management
// - Command parsing: DOS mode REPL commands
//
// Running tests:
//   swift test --filter ATR       Run ATR-related tests
//   swift test --filter FileSystem  Run file system tests
//   swift test --filter DiskManager Run disk manager tests
//
// Test Categories:
// 1. ATRImage Tests - Header parsing, sector access, creation
// 2. Directory Entry Tests - Parsing and encoding directory entries
// 3. VTOC Tests - Volume Table of Contents operations
// 4. AtariFileSystem Tests - File system operations
// 5. DiskManager Tests - Mount/unmount and file operations
// 6. DOS Command Parser Tests - Command parsing validation
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - ATR Disk Type Tests
// =============================================================================

/// Tests for the ATRDiskType enumeration.
final class ATRDiskTypeTests: XCTestCase {

    /// Test single density parameters.
    func test_singleDensity_parameters() {
        let type = ATRDiskType.singleDensity

        XCTAssertEqual(type.sectorCount, 720)
        XCTAssertEqual(type.sectorSize, 128)
        XCTAssertEqual(type.capacity, 92160)
        XCTAssertEqual(type.paragraphs, 5760)
    }

    /// Test enhanced density parameters.
    func test_enhancedDensity_parameters() {
        let type = ATRDiskType.enhancedDensity

        XCTAssertEqual(type.sectorCount, 1040)
        XCTAssertEqual(type.sectorSize, 128)
        XCTAssertEqual(type.capacity, 133120)
    }

    /// Test double density parameters.
    func test_doubleDensity_parameters() {
        let type = ATRDiskType.doubleDensity

        XCTAssertEqual(type.sectorCount, 720)
        XCTAssertEqual(type.sectorSize, 256)
    }

    /// Test disk type descriptions.
    func test_descriptions() {
        XCTAssertEqual(ATRDiskType.singleDensity.shortDescription, "SS/SD")
        XCTAssertEqual(ATRDiskType.enhancedDensity.shortDescription, "SS/ED")
        XCTAssertEqual(ATRDiskType.doubleDensity.shortDescription, "SS/DD")
    }

    /// Test disk type initialization from string.
    func test_initFromString() {
        XCTAssertEqual(ATRDiskType(from: "ss/sd"), .singleDensity)
        XCTAssertEqual(ATRDiskType(from: "SS/SD"), .singleDensity)
        XCTAssertEqual(ATRDiskType(from: "ss/ed"), .enhancedDensity)
        XCTAssertEqual(ATRDiskType(from: "ss/dd"), .doubleDensity)
        XCTAssertNil(ATRDiskType(from: "invalid"))
    }
}

// =============================================================================
// MARK: - ATR Error Tests
// =============================================================================

/// Tests for ATRError types.
final class ATRErrorTests: XCTestCase {

    /// Test error descriptions are non-empty.
    func test_errorDescriptions_nonEmpty() {
        let errors: [ATRError] = [
            .invalidMagic,
            .fileTooSmall,
            .unsupportedSectorSize(512),
            .sectorOutOfRange(1000),
            .readError("test error"),
            .writeError("test error"),
            .readOnly
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    /// Test sector out of range includes sector number.
    func test_sectorOutOfRange_includesSector() {
        let error = ATRError.sectorOutOfRange(999)
        XCTAssertTrue(error.errorDescription?.contains("999") ?? false)
    }
}

// =============================================================================
// MARK: - ATR Image Creation Tests
// =============================================================================

/// Tests for ATRImage creation and basic operations.
final class ATRImageCreationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Test creating a new single density ATR.
    func test_create_singleDensity() throws {
        let url = tempDir.appendingPathComponent("test_sd.atr")
        let disk = try ATRImage.create(at: url, type: .singleDensity)

        XCTAssertEqual(disk.sectorSize, 128)
        XCTAssertEqual(disk.sectorCount, 720)
        XCTAssertEqual(disk.diskType, .singleDensity)
        XCTAssertFalse(disk.isReadOnly)
    }

    /// Test creating a new enhanced density ATR.
    func test_create_enhancedDensity() throws {
        let url = tempDir.appendingPathComponent("test_ed.atr")
        let disk = try ATRImage.create(at: url, type: .enhancedDensity)

        XCTAssertEqual(disk.sectorSize, 128)
        XCTAssertEqual(disk.sectorCount, 1040)
        XCTAssertEqual(disk.diskType, .enhancedDensity)
    }

    /// Test creating a new double density ATR.
    func test_create_doubleDensity() throws {
        let url = tempDir.appendingPathComponent("test_dd.atr")
        let disk = try ATRImage.create(at: url, type: .doubleDensity)

        XCTAssertEqual(disk.sectorSize, 256)
        XCTAssertEqual(disk.sectorCount, 720)
        XCTAssertEqual(disk.diskType, .doubleDensity)
    }

    /// Test reading a created ATR back.
    func test_createAndReload() throws {
        let url = tempDir.appendingPathComponent("test_reload.atr")
        _ = try ATRImage.create(at: url, type: .singleDensity)

        // Load it back
        let loaded = try ATRImage(url: url)
        XCTAssertEqual(loaded.sectorCount, 720)
        XCTAssertEqual(loaded.sectorSize, 128)
    }

    /// Test ATR magic number validation.
    func test_invalidMagic_throws() throws {
        let url = tempDir.appendingPathComponent("invalid.atr")
        let invalidData = Data([0x00, 0x00, 0x00, 0x00]) // No magic
        try invalidData.write(to: url)

        XCTAssertThrowsError(try ATRImage(url: url)) { error in
            guard case ATRError.invalidMagic = error else {
                XCTFail("Expected invalidMagic error")
                return
            }
        }
    }

    /// Test file too small throws.
    func test_fileTooSmall_throws() throws {
        let url = tempDir.appendingPathComponent("small.atr")
        let tooSmall = Data([0x96, 0x02]) // Just magic, not enough
        try tooSmall.write(to: url)

        XCTAssertThrowsError(try ATRImage(url: url)) { error in
            guard case ATRError.fileTooSmall = error else {
                XCTFail("Expected fileTooSmall error")
                return
            }
        }
    }

    /// Test nonexistent file throws.
    func test_nonexistentFile_throws() {
        let url = tempDir.appendingPathComponent("nonexistent.atr")

        XCTAssertThrowsError(try ATRImage(url: url)) { error in
            guard case ATRError.readError = error else {
                XCTFail("Expected readError")
                return
            }
        }
    }
}

// =============================================================================
// MARK: - ATR Sector Access Tests
// =============================================================================

/// Tests for ATR sector read/write operations.
final class ATRSectorAccessTests: XCTestCase {
    var tempDir: URL!
    var disk: ATRImage!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("test.atr")
        disk = try? ATRImage.create(at: url, type: .singleDensity)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Test reading a valid sector.
    func test_readSector_valid() throws {
        let data = try disk.readSector(1)
        XCTAssertEqual(data.count, 128)
    }

    /// Test sector out of range - low.
    func test_readSector_outOfRange_low() {
        XCTAssertThrowsError(try disk.readSector(0)) { error in
            guard case ATRError.sectorOutOfRange = error else {
                XCTFail("Expected sectorOutOfRange")
                return
            }
        }
    }

    /// Test sector out of range - high.
    func test_readSector_outOfRange_high() {
        XCTAssertThrowsError(try disk.readSector(721)) { error in
            guard case ATRError.sectorOutOfRange = error else {
                XCTFail("Expected sectorOutOfRange")
                return
            }
        }
    }

    /// Test writing a sector.
    func test_writeSector() throws {
        var testData = [UInt8](repeating: 0, count: 128)
        testData[0] = 0x42
        testData[127] = 0xFF

        try disk.writeSector(1, data: testData)
        XCTAssertTrue(disk.isModified)

        let readBack = try disk.readSector(1)
        XCTAssertEqual(readBack[0], 0x42)
        XCTAssertEqual(readBack[127], 0xFF)
    }

    /// Test writing pads short data.
    func test_writeSector_padsShortData() throws {
        let shortData: [UInt8] = [0x01, 0x02, 0x03]
        try disk.writeSector(1, data: shortData)

        let readBack = try disk.readSector(1)
        XCTAssertEqual(readBack[0], 0x01)
        XCTAssertEqual(readBack[1], 0x02)
        XCTAssertEqual(readBack[2], 0x03)
        XCTAssertEqual(readBack[3], 0x00) // Padded
    }

    /// Test writing truncates long data.
    func test_writeSector_truncatesLongData() throws {
        let longData = [UInt8](repeating: 0x42, count: 200)
        try disk.writeSector(1, data: longData)

        let readBack = try disk.readSector(1)
        XCTAssertEqual(readBack.count, 128)
    }

    /// Test actualSectorSize for single density.
    func test_actualSectorSize_singleDensity() {
        XCTAssertEqual(disk.actualSectorSize(1), 128)
        XCTAssertEqual(disk.actualSectorSize(3), 128)
        XCTAssertEqual(disk.actualSectorSize(720), 128)
    }

    /// Test save and revert.
    func test_saveAndRevert() throws {
        // Write data
        var testData = [UInt8](repeating: 0x42, count: 128)
        try disk.writeSector(1, data: testData)
        try disk.save()

        // Modify again
        testData = [UInt8](repeating: 0xFF, count: 128)
        try disk.writeSector(1, data: testData)

        // Revert should restore saved state
        try disk.revert()
        let readBack = try disk.readSector(1)
        XCTAssertEqual(readBack[0], 0x42)
    }
}

// =============================================================================
// MARK: - Directory Entry Tests
// =============================================================================

/// Tests for DirectoryEntry parsing and encoding.
final class DirectoryEntryTests: XCTestCase {

    /// Test parsing a normal file entry.
    func test_parse_normalFile() {
        // Flags: 0x42 (in use), Sectors: 28, Start: 45, Name: "GAME    ", Ext: "COM"
        let bytes: [UInt8] = [
            0x42,       // Flags: in use
            0x1C, 0x00, // Sector count: 28
            0x2D, 0x00, // Start sector: 45
            0x47, 0x41, 0x4D, 0x45, 0x20, 0x20, 0x20, 0x20, // "GAME    "
            0x43, 0x4F, 0x4D // "COM"
        ]

        let entry = DirectoryEntry(bytes: bytes, index: 0)

        XCTAssertEqual(entry.flags, 0x42)
        XCTAssertTrue(entry.isInUse)
        XCTAssertFalse(entry.isLocked)
        XCTAssertFalse(entry.isDeleted)
        XCTAssertEqual(entry.sectorCount, 28)
        XCTAssertEqual(entry.startSector, 45)
        XCTAssertEqual(entry.fullName, "GAME.COM")
    }

    /// Test parsing a locked file.
    func test_parse_lockedFile() {
        let bytes: [UInt8] = [
            0x43,       // Flags: in use + locked
            0x10, 0x00, // Sector count: 16
            0x64, 0x00, // Start sector: 100
            0x54, 0x45, 0x53, 0x54, 0x20, 0x20, 0x20, 0x20, // "TEST    "
            0x44, 0x41, 0x54 // "DAT"
        ]

        let entry = DirectoryEntry(bytes: bytes)

        XCTAssertTrue(entry.isInUse)
        XCTAssertTrue(entry.isLocked)
        XCTAssertEqual(entry.fullName, "TEST.DAT")
    }

    /// Test parsing a deleted file.
    func test_parse_deletedFile() {
        let bytes: [UInt8] = [
            0x80,       // Flags: deleted
            0x0A, 0x00,
            0x50, 0x00,
            0x4F, 0x4C, 0x44, 0x20, 0x20, 0x20, 0x20, 0x20,
            0x54, 0x58, 0x54
        ]

        let entry = DirectoryEntry(bytes: bytes)

        XCTAssertTrue(entry.isDeleted)
        XCTAssertFalse(entry.isInUse)
    }

    /// Test parsing never-used entry.
    func test_parse_neverUsed() {
        let bytes = [UInt8](repeating: 0, count: 16)
        let entry = DirectoryEntry(bytes: bytes)

        XCTAssertTrue(entry.neverUsed)
        XCTAssertFalse(entry.isInUse)
    }

    /// Test creating a new entry.
    func test_create_newEntry() {
        let entry = DirectoryEntry(
            filename: "MYFILE",
            ext: "BAS",
            startSector: 100,
            sectorCount: 25,
            locked: false
        )

        XCTAssertEqual(entry.fullName, "MYFILE.BAS")
        XCTAssertEqual(entry.sectorCount, 25)
        XCTAssertEqual(entry.startSector, 100)
        XCTAssertFalse(entry.isLocked)
        XCTAssertTrue(entry.isInUse)
    }

    /// Test creating a locked entry.
    func test_create_lockedEntry() {
        let entry = DirectoryEntry(
            filename: "LOCKED",
            ext: "COM",
            startSector: 50,
            sectorCount: 10,
            locked: true
        )

        XCTAssertTrue(entry.isLocked)
    }

    /// Test encoding and decoding roundtrip.
    func test_encodeAndDecode_roundtrip() {
        let original = DirectoryEntry(
            filename: "ROUNDTRP",
            ext: "TST",
            startSector: 123,
            sectorCount: 45,
            locked: true
        )

        let encoded = original.encode()
        XCTAssertEqual(encoded.count, 16)

        let decoded = DirectoryEntry(bytes: encoded)

        XCTAssertEqual(decoded.fullName, original.fullName)
        XCTAssertEqual(decoded.sectorCount, original.sectorCount)
        XCTAssertEqual(decoded.startSector, original.startSector)
        XCTAssertEqual(decoded.isLocked, original.isLocked)
    }

    /// Test filename without extension.
    func test_fullName_noExtension() {
        let bytes: [UInt8] = [
            0x42,
            0x05, 0x00,
            0x10, 0x00,
            0x4D, 0x41, 0x4B, 0x45, 0x46, 0x49, 0x4C, 0x45, // "MAKEFILE"
            0x20, 0x20, 0x20 // "   " (empty extension)
        ]

        let entry = DirectoryEntry(bytes: bytes)
        XCTAssertEqual(entry.fullName, "MAKEFILE")
    }
}

// =============================================================================
// MARK: - Sector Link Tests
// =============================================================================

/// Tests for SectorLink parsing.
final class SectorLinkTests: XCTestCase {

    /// Test parsing a link to next sector.
    func test_parse_notLastSector() {
        // Create sector data with link to sector 100
        var sectorData = [UInt8](repeating: 0, count: 128)
        // File ID 5, next sector 100
        // Byte 125: (5 << 2) | (100 >> 8) = 20 | 0 = 20
        // Byte 126: 100 & 0xFF = 100
        sectorData[125] = 0x14 // File ID 5
        sectorData[126] = 0x64 // Next sector 100
        sectorData[127] = 0x00

        let link = SectorLink(bytes: sectorData, sectorSize: 128)

        XCTAssertEqual(link.fileID, 5)
        XCTAssertEqual(link.nextSector, 100)
        XCTAssertFalse(link.isLast)
        XCTAssertEqual(link.bytesInSector, 125) // 128 - 3
    }

    /// Test parsing last sector link.
    func test_parse_lastSector() {
        var sectorData = [UInt8](repeating: 0, count: 128)
        // File ID 3, last sector with 50 bytes
        sectorData[125] = 0x0C // File ID 3, next sector high = 0
        sectorData[126] = 0x32 // 50 bytes in sector
        sectorData[127] = 0x00

        let link = SectorLink(bytes: sectorData, sectorSize: 128)

        XCTAssertEqual(link.fileID, 3)
        XCTAssertTrue(link.isLast)
        XCTAssertEqual(link.bytesInSector, 50)
    }

    /// Test encoding sector link.
    func test_encode_notLastSector() {
        let encoded = SectorLink.encode(fileID: 5, nextSector: 100)

        XCTAssertEqual(encoded.count, 3)
        XCTAssertEqual(encoded[0], 0x14) // File ID 5 << 2
        XCTAssertEqual(encoded[1], 0x64) // 100
        XCTAssertEqual(encoded[2], 0x00)
    }

    /// Test encoding last sector link.
    func test_encode_lastSector() {
        let encoded = SectorLink.encode(fileID: 3, nextSector: 0, bytesInLastSector: 50)

        XCTAssertEqual(encoded[0], 0x0C) // File ID 3 << 2
        XCTAssertEqual(encoded[1], 50)   // Bytes in sector
        XCTAssertEqual(encoded[2], 0x00)
    }
}

// =============================================================================
// MARK: - VTOC Tests
// =============================================================================

/// Tests for VTOC (Volume Table of Contents) operations.
final class VTOCTests: XCTestCase {

    /// Test creating an empty VTOC for single density.
    func test_createEmpty_singleDensity() {
        let vtoc = VTOC.createEmpty(for: .singleDensity)

        XCTAssertEqual(vtoc.dosCode, 2) // DOS 2.5
        XCTAssertEqual(vtoc.totalSectors, 720)
        // Free = 720 - 3 (boot) - 1 (vtoc) - 8 (directory) = 708
        XCTAssertEqual(vtoc.freeSectors, 708)
    }

    /// Test sector allocation tracking.
    func test_sectorAllocation() {
        var vtoc = VTOC.createEmpty(for: .singleDensity)

        // Boot sectors (1-3), VTOC (360), and directory (361-368) should be used
        XCTAssertFalse(vtoc.isSectorFree(1))
        XCTAssertFalse(vtoc.isSectorFree(2))
        XCTAssertFalse(vtoc.isSectorFree(3))
        XCTAssertFalse(vtoc.isSectorFree(360))
        XCTAssertFalse(vtoc.isSectorFree(361))

        // Data sectors should be free
        XCTAssertTrue(vtoc.isSectorFree(4))
        XCTAssertTrue(vtoc.isSectorFree(100))
        XCTAssertTrue(vtoc.isSectorFree(359))
        XCTAssertTrue(vtoc.isSectorFree(369))
    }

    /// Test marking sectors used/free.
    func test_setSectorUsedAndFree() {
        var vtoc = VTOC.createEmpty(for: .singleDensity)
        let initialFree = vtoc.freeSectors

        // Mark sector 100 as used
        vtoc.setSectorUsed(100)
        XCTAssertFalse(vtoc.isSectorFree(100))
        XCTAssertEqual(vtoc.freeSectors, initialFree - 1)

        // Mark it free again
        vtoc.setSectorFree(100)
        XCTAssertTrue(vtoc.isSectorFree(100))
        XCTAssertEqual(vtoc.freeSectors, initialFree)
    }

    /// Test allocating sectors.
    func test_allocateSectors() {
        var vtoc = VTOC.createEmpty(for: .singleDensity)
        let initialFree = vtoc.freeSectors

        let allocated = vtoc.allocateSectors(5)

        XCTAssertNotNil(allocated)
        XCTAssertEqual(allocated?.count, 5)
        XCTAssertEqual(vtoc.freeSectors, initialFree - 5)

        // All allocated sectors should be marked used
        for sector in allocated ?? [] {
            XCTAssertFalse(vtoc.isSectorFree(Int(sector)))
        }
    }

    /// Test allocating more sectors than available fails.
    func test_allocateSectors_insufficientSpace() {
        var vtoc = VTOC.createEmpty(for: .singleDensity)

        // Try to allocate more than available
        let allocated = vtoc.allocateSectors(1000)
        XCTAssertNil(allocated)
    }

    /// Test VTOC encode/decode roundtrip.
    func test_encodeAndDecode_roundtrip() {
        var original = VTOC.createEmpty(for: .singleDensity)
        _ = original.allocateSectors(10)

        let encoded = original.encode()
        XCTAssertEqual(encoded.count, 128)

        let decoded = VTOC(bytes: encoded)
        XCTAssertEqual(decoded.dosCode, original.dosCode)
        XCTAssertEqual(decoded.totalSectors, original.totalSectors)
        XCTAssertEqual(decoded.freeSectors, original.freeSectors)
    }
}

// =============================================================================
// MARK: - Atari File System Tests
// =============================================================================

/// Tests for AtariFileSystem operations.
final class AtariFileSystemTests: XCTestCase {
    var tempDir: URL!
    var disk: ATRImage!
    var fs: AtariFileSystem!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let url = tempDir.appendingPathComponent("test.atr")
        disk = try? ATRImage.create(at: url, type: .singleDensity)
        if let disk = disk {
            fs = AtariFileSystem(disk: disk)
            try? fs.format()
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Test reading VTOC from disk.
    func test_readVTOC() throws {
        let vtoc = try fs.readVTOC()

        XCTAssertEqual(vtoc.dosCode, 2)
        XCTAssertEqual(vtoc.totalSectors, 720)
    }

    /// Test reading empty directory.
    func test_readDirectory_empty() throws {
        let entries = try fs.readDirectory()
        XCTAssertTrue(entries.isEmpty)
    }

    /// Test finding free directory entry.
    func test_findFreeDirectoryEntry() throws {
        let freeIndex = try fs.findFreeDirectoryEntry()
        XCTAssertNotNil(freeIndex)
        XCTAssertEqual(freeIndex, 0)
    }

    /// Test file not found error.
    func test_findFile_notFound() throws {
        let file = try fs.findFile(named: "NOTEXIST.COM")
        XCTAssertNil(file)
    }

    /// Test reading file that doesn't exist.
    func test_readFile_notFound() {
        XCTAssertThrowsError(try fs.readFile(named: "MISSING.TXT")) { error in
            guard case FileSystemError.fileNotFound = error else {
                XCTFail("Expected fileNotFound error")
                return
            }
        }
    }

    /// Test getting disk stats.
    func test_getDiskStats() throws {
        let stats = try fs.getDiskStats()

        XCTAssertEqual(stats.totalSectors, 720)
        XCTAssertEqual(stats.fileCount, 0)
        XCTAssertEqual(stats.diskType, .singleDensity)
    }
}

// =============================================================================
// MARK: - File System Error Tests
// =============================================================================

/// Tests for FileSystemError types.
final class FileSystemErrorTests: XCTestCase {

    /// Test all error descriptions are non-empty.
    func test_errorDescriptions_nonEmpty() {
        let errors: [FileSystemError] = [
            .fileNotFound("TEST.COM"),
            .fileExists("EXISTING.COM"),
            .directoryFull,
            .diskFull(required: 100, available: 50),
            .fileLocked("LOCKED.COM"),
            .invalidFilename("reason"),
            .invalidVTOC,
            .corruptFileChain("CORRUPT.DAT"),
            .fileInUse("OPEN.DAT"),
            .invalidPattern("bad pattern")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }

    /// Test disk full error includes counts.
    func test_diskFull_includesCounts() {
        let error = FileSystemError.diskFull(required: 100, available: 50)
        let desc = error.errorDescription ?? ""

        XCTAssertTrue(desc.contains("100"))
        XCTAssertTrue(desc.contains("50"))
    }
}

// =============================================================================
// MARK: - Disk Manager Tests
// =============================================================================

/// Tests for DiskManager operations.
final class DiskManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: DiskManager!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = DiskManager()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    /// Test initial state.
    func test_initialState() async {
        let current = await manager.currentDrive
        XCTAssertEqual(current, 1)

        let mounted = await manager.isDriveMounted(1)
        XCTAssertFalse(mounted)
    }

    /// Test listing empty drives.
    func test_listDrives_empty() async {
        let drives = await manager.listDrives()

        XCTAssertEqual(drives.count, 8)
        XCTAssertFalse(drives[0].mounted)
        XCTAssertEqual(drives[0].drive, 1)
    }

    /// Test invalid drive number.
    func test_mount_invalidDrive() async {
        do {
            _ = try await manager.mount(drive: 0, path: "/test.atr")
            XCTFail("Should throw for invalid drive")
        } catch {
            guard case DiskManagerError.invalidDrive = error else {
                XCTFail("Expected invalidDrive error")
                return
            }
        }

        do {
            _ = try await manager.mount(drive: 9, path: "/test.atr")
            XCTFail("Should throw for invalid drive")
        } catch {
            guard case DiskManagerError.invalidDrive = error else {
                XCTFail("Expected invalidDrive error")
                return
            }
        }
    }

    /// Test mounting nonexistent file.
    func test_mount_pathNotFound() async {
        do {
            _ = try await manager.mount(drive: 1, path: "/nonexistent/path/disk.atr")
            XCTFail("Should throw for missing file")
        } catch {
            guard case DiskManagerError.pathNotFound = error else {
                XCTFail("Expected pathNotFound error, got \(error)")
                return
            }
        }
    }

    /// Test mounting and unmounting.
    func test_mountAndUnmount() async throws {
        // Create a disk image
        let url = tempDir.appendingPathComponent("test.atr")
        _ = try ATRImage.create(at: url, type: .singleDensity)

        // Mount it
        let info = try await manager.mount(drive: 1, path: url.path)
        XCTAssertEqual(info.drive, 1)
        XCTAssertTrue(info.filename.contains("test.atr"))

        // Verify mounted
        let mounted = await manager.isDriveMounted(1)
        XCTAssertTrue(mounted)

        // Unmount
        try await manager.unmount(drive: 1)

        // Verify unmounted
        let stillMounted = await manager.isDriveMounted(1)
        XCTAssertFalse(stillMounted)
    }

    /// Test drive already in use.
    func test_mount_driveInUse() async throws {
        let url = tempDir.appendingPathComponent("test.atr")
        _ = try ATRImage.create(at: url, type: .singleDensity)

        // Mount first time
        _ = try await manager.mount(drive: 1, path: url.path)

        // Try to mount again
        do {
            _ = try await manager.mount(drive: 1, path: url.path)
            XCTFail("Should throw for drive in use")
        } catch {
            guard case DiskManagerError.driveInUse = error else {
                XCTFail("Expected driveInUse error")
                return
            }
        }
    }

    /// Test changing drive.
    func test_changeDrive() async throws {
        let url = tempDir.appendingPathComponent("test.atr")
        _ = try ATRImage.create(at: url, type: .singleDensity)
        _ = try await manager.mount(drive: 2, path: url.path)

        try await manager.changeDrive(to: 2)

        let current = await manager.currentDrive
        XCTAssertEqual(current, 2)
    }

    /// Test changing to empty drive fails.
    func test_changeDrive_empty() async {
        do {
            try await manager.changeDrive(to: 5)
            XCTFail("Should throw for empty drive")
        } catch {
            guard case DiskManagerError.driveEmpty = error else {
                XCTFail("Expected driveEmpty error")
                return
            }
        }
    }

    /// Test creating a new disk.
    func test_createDisk() async throws {
        let path = tempDir.appendingPathComponent("new.atr").path

        let url = try await manager.createDisk(at: path, type: .singleDensity)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Verify we can load it
        let disk = try ATRImage(url: url)
        XCTAssertEqual(disk.diskType, .singleDensity)
    }
}

// =============================================================================
// MARK: - Disk Manager Error Tests
// =============================================================================

/// Tests for DiskManagerError types.
final class DiskManagerErrorTests: XCTestCase {

    /// Test all error descriptions are non-empty.
    func test_errorDescriptions_nonEmpty() {
        let errors: [DiskManagerError] = [
            .invalidDrive(0),
            .driveEmpty(1),
            .driveInUse(2),
            .mountFailed("reason"),
            .pathNotFound("/path"),
            .diskReadOnly(1)
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}

// =============================================================================
// MARK: - DOS Command Parser Tests
// =============================================================================

/// Tests for DOS mode command parsing.
final class DOSCommandParserTests: XCTestCase {
    var parser: CommandParser!

    override func setUp() {
        super.setUp()
        parser = CommandParser()
    }

    /// Test parsing mount command.
    func test_parse_mount() throws {
        let cmd = try parser.parse("mount 1 ~/disks/game.atr", mode: .dos)

        if case .dosMountDisk(let drive, let path) = cmd {
            XCTAssertEqual(drive, 1)
            XCTAssertEqual(path, "~/disks/game.atr")
        } else {
            XCTFail("Expected dosMountDisk command")
        }
    }

    /// Test parsing mount with missing path.
    func test_parse_mount_missingPath() {
        XCTAssertThrowsError(try parser.parse("mount 1", mode: .dos))
    }

    /// Test parsing mount with invalid drive.
    func test_parse_mount_invalidDrive() {
        XCTAssertThrowsError(try parser.parse("mount 0 /path.atr", mode: .dos))
        XCTAssertThrowsError(try parser.parse("mount 9 /path.atr", mode: .dos))
    }

    /// Test parsing unmount command.
    func test_parse_unmount() throws {
        let cmd = try parser.parse("unmount 2", mode: .dos)

        if case .dosUnmount(let drive) = cmd {
            XCTAssertEqual(drive, 2)
        } else {
            XCTFail("Expected dosUnmount command")
        }
    }

    /// Test parsing drives command.
    func test_parse_drives() throws {
        let cmd = try parser.parse("drives", mode: .dos)

        if case .dosDrives = cmd {
            // OK
        } else {
            XCTFail("Expected dosDrives command")
        }
    }

    /// Test parsing cd command.
    func test_parse_cd() throws {
        let cmd = try parser.parse("cd 3", mode: .dos)

        if case .dosChangeDrive(let drive) = cmd {
            XCTAssertEqual(drive, 3)
        } else {
            XCTFail("Expected dosChangeDrive command")
        }
    }

    /// Test parsing dir command.
    func test_parse_dir() throws {
        let cmd = try parser.parse("dir", mode: .dos)

        if case .dosDirectory(let pattern) = cmd {
            XCTAssertNil(pattern)
        } else {
            XCTFail("Expected dosDirectory command")
        }
    }

    /// Test parsing dir with pattern.
    func test_parse_dirWithPattern() throws {
        let cmd = try parser.parse("dir *.COM", mode: .dos)

        if case .dosDirectory(let pattern) = cmd {
            XCTAssertEqual(pattern, "*.COM")
        } else {
            XCTFail("Expected dosDirectory command")
        }
    }

    /// Test parsing info command.
    func test_parse_info() throws {
        let cmd = try parser.parse("info GAME.COM", mode: .dos)

        if case .dosFileInfo(let filename) = cmd {
            XCTAssertEqual(filename, "GAME.COM")
        } else {
            XCTFail("Expected dosFileInfo command")
        }
    }

    /// Test parsing type command.
    func test_parse_type() throws {
        let cmd = try parser.parse("type README.TXT", mode: .dos)

        if case .dosType(let filename) = cmd {
            XCTAssertEqual(filename, "README.TXT")
        } else {
            XCTFail("Expected dosType command")
        }
    }

    /// Test parsing dump command.
    func test_parse_dump() throws {
        let cmd = try parser.parse("dump GAME.COM", mode: .dos)

        if case .dosDump(let filename) = cmd {
            XCTAssertEqual(filename, "GAME.COM")
        } else {
            XCTFail("Expected dosDump command")
        }
    }

    /// Test parsing copy command.
    func test_parse_copy() throws {
        let cmd = try parser.parse("copy SRC.COM D2:DST.COM", mode: .dos)

        if case .dosCopy(let src, let dest) = cmd {
            XCTAssertEqual(src, "SRC.COM")
            XCTAssertEqual(dest, "D2:DST.COM")
        } else {
            XCTFail("Expected dosCopy command")
        }
    }

    /// Test parsing rename command.
    func test_parse_rename() throws {
        let cmd = try parser.parse("rename OLD.COM NEW.COM", mode: .dos)

        if case .dosRename(let old, let new) = cmd {
            XCTAssertEqual(old, "OLD.COM")
            XCTAssertEqual(new, "NEW.COM")
        } else {
            XCTFail("Expected dosRename command")
        }
    }

    /// Test parsing delete command.
    func test_parse_delete() throws {
        let cmd = try parser.parse("delete FILE.DAT", mode: .dos)

        if case .dosDelete(let filename) = cmd {
            XCTAssertEqual(filename, "FILE.DAT")
        } else {
            XCTFail("Expected dosDelete command")
        }
    }

    /// Test parsing del alias.
    func test_parse_del() throws {
        let cmd = try parser.parse("del FILE.DAT", mode: .dos)

        if case .dosDelete(let filename) = cmd {
            XCTAssertEqual(filename, "FILE.DAT")
        } else {
            XCTFail("Expected dosDelete command")
        }
    }

    /// Test parsing lock command.
    func test_parse_lock() throws {
        let cmd = try parser.parse("lock FILE.COM", mode: .dos)

        if case .dosLock(let filename) = cmd {
            XCTAssertEqual(filename, "FILE.COM")
        } else {
            XCTFail("Expected dosLock command")
        }
    }

    /// Test parsing unlock command.
    func test_parse_unlock() throws {
        let cmd = try parser.parse("unlock FILE.COM", mode: .dos)

        if case .dosUnlock(let filename) = cmd {
            XCTAssertEqual(filename, "FILE.COM")
        } else {
            XCTFail("Expected dosUnlock command")
        }
    }

    /// Test parsing export command.
    func test_parse_export() throws {
        let cmd = try parser.parse("export GAME.COM ~/Desktop/game.com", mode: .dos)

        if case .dosExport(let filename, let path) = cmd {
            XCTAssertEqual(filename, "GAME.COM")
            XCTAssertEqual(path, "~/Desktop/game.com")
        } else {
            XCTFail("Expected dosExport command")
        }
    }

    /// Test parsing import command.
    func test_parse_import() throws {
        let cmd = try parser.parse("import ~/Desktop/game.com GAME.COM", mode: .dos)

        if case .dosImport(let path, let filename) = cmd {
            XCTAssertEqual(path, "~/Desktop/game.com")
            XCTAssertEqual(filename, "GAME.COM")
        } else {
            XCTFail("Expected dosImport command")
        }
    }

    /// Test parsing newdisk command.
    func test_parse_newdisk() throws {
        let cmd = try parser.parse("newdisk ~/disks/new.atr ss/sd", mode: .dos)

        if case .dosNewDisk(let path, let type) = cmd {
            XCTAssertEqual(path, "~/disks/new.atr")
            XCTAssertEqual(type, "ss/sd")
        } else {
            XCTFail("Expected dosNewDisk command")
        }
    }

    /// Test parsing newdisk without type.
    func test_parse_newdisk_noType() throws {
        let cmd = try parser.parse("newdisk ~/disks/new.atr", mode: .dos)

        if case .dosNewDisk(let path, let type) = cmd {
            XCTAssertEqual(path, "~/disks/new.atr")
            XCTAssertNil(type)
        } else {
            XCTFail("Expected dosNewDisk command")
        }
    }

    /// Test parsing format command.
    func test_parse_format() throws {
        let cmd = try parser.parse("format", mode: .dos)

        if case .dosFormat = cmd {
            // OK
        } else {
            XCTFail("Expected dosFormat command")
        }
    }

    /// Test unknown command throws.
    func test_parse_unknownCommand() {
        XCTAssertThrowsError(try parser.parse("unknown", mode: .dos))
    }
}

// =============================================================================
// MARK: - Drive Status Tests
// =============================================================================

/// Tests for DriveStatus display formatting.
final class DriveStatusTests: XCTestCase {

    /// Test empty drive display.
    func test_displayString_empty() {
        let status = DriveStatus(
            drive: 1,
            mounted: false,
            path: nil,
            diskType: nil,
            freeSectors: 0,
            fileCount: 0,
            isReadOnly: false,
            isModified: false
        )

        XCTAssertEqual(status.displayString, "D1: (empty)")
    }

    /// Test mounted drive display.
    func test_displayString_mounted() {
        let status = DriveStatus(
            drive: 2,
            mounted: true,
            path: "/path/to/game.atr",
            diskType: .singleDensity,
            freeSectors: 500,
            fileCount: 10,
            isReadOnly: false,
            isModified: false
        )

        let display = status.displayString
        XCTAssertTrue(display.contains("D2:"))
        XCTAssertTrue(display.contains("game.atr"))
        XCTAssertTrue(display.contains("SS/SD"))
        XCTAssertTrue(display.contains("10 files"))
        XCTAssertTrue(display.contains("500 free"))
    }

    /// Test read-only indicator.
    func test_displayString_readOnly() {
        let status = DriveStatus(
            drive: 1,
            mounted: true,
            path: "/test.atr",
            diskType: .singleDensity,
            freeSectors: 100,
            fileCount: 5,
            isReadOnly: true,
            isModified: false
        )

        XCTAssertTrue(status.displayString.contains("[R/O]"))
    }

    /// Test modified indicator.
    func test_displayString_modified() {
        let status = DriveStatus(
            drive: 1,
            mounted: true,
            path: "/test.atr",
            diskType: .singleDensity,
            freeSectors: 100,
            fileCount: 5,
            isReadOnly: false,
            isModified: true
        )

        XCTAssertTrue(status.displayString.contains("*"))
    }
}
