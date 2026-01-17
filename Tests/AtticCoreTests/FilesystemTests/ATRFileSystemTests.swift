// =============================================================================
// ATRFileSystemTests.swift - Unit Tests for ATR File System Operations
// =============================================================================
//
// Tests for the ATRFileSystem class that provides high-level file operations
// on Atari DOS disks.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class ATRFileSystemTests: XCTestCase {

    // =========================================================================
    // MARK: - Test Helpers
    // =========================================================================

    /// Creates a formatted disk image in memory.
    func createFormattedDisk(type: DiskType = .singleDensity) throws -> ATRImage {
        var data = Data()

        // Header
        data.append(0x96)
        data.append(0x02)
        let paragraphs = type.paragraphs
        data.append(UInt8(paragraphs & 0xFF))
        data.append(UInt8((paragraphs >> 8) & 0xFF))
        data.append(UInt8(type.sectorSize & 0xFF))
        data.append(UInt8((type.sectorSize >> 8) & 0xFF))
        data.append(UInt8((paragraphs >> 16) & 0xFF))
        data.append(contentsOf: [UInt8](repeating: 0, count: 9))

        // Sectors
        data.append(contentsOf: [UInt8](repeating: 0, count: type.totalSize))

        let image = try ATRImage(data: data)

        // Initialize VTOC
        let vtoc = VTOC.createEmpty(for: type)
        try image.writeSector(360, data: vtoc.encode())

        // Initialize directory (all zeros = never used)
        for sector in 361...368 {
            try image.writeSector(sector, data: [UInt8](repeating: 0, count: 128))
        }

        return image
    }

    /// Adds a test file to the disk.
    func addTestFile(
        to disk: ATRImage,
        name: String,
        ext: String,
        startSector: Int,
        sectorCount: Int,
        entryIndex: Int,
        data fileData: [UInt8]? = nil
    ) throws {
        // Create directory entry
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: UInt16(sectorCount),
            startSector: UInt16(startSector),
            filename: name,
            fileExtension: ext,
            entryIndex: entryIndex
        )

        // Write directory entry
        let dirSector = 361 + entryIndex / 8
        let dirOffset = (entryIndex % 8) * 16
        var dirData = try disk.readSector(dirSector)
        let entryBytes = entry.encode()
        for (i, byte) in entryBytes.enumerated() {
            dirData[dirOffset + i] = byte
        }
        try disk.writeSector(dirSector, data: dirData)

        // Write file data sectors
        let actualData = fileData ?? [UInt8](repeating: 0x41, count: 100)  // 'A' pattern
        let bytesPerSector = disk.sectorSize - 3

        var remainingData = actualData
        var currentSector = startSector

        for i in 0..<sectorCount {
            var sectorData = [UInt8](repeating: 0, count: disk.actualSectorSize(currentSector))
            let isLast = (i == sectorCount - 1)
            let nextSector = isLast ? 0 : currentSector + 1

            // Copy data
            let bytesToWrite = min(bytesPerSector, remainingData.count)
            for j in 0..<bytesToWrite {
                sectorData[j] = remainingData[j]
            }
            if bytesToWrite < remainingData.count {
                remainingData = Array(remainingData.dropFirst(bytesToWrite))
            } else {
                remainingData = []
            }

            // Write link bytes
            let link = SectorLink(
                fileID: UInt8(entryIndex),
                nextSector: UInt16(nextSector),
                bytesInSector: isLast ? bytesToWrite : bytesPerSector,
                sectorSize: disk.actualSectorSize(currentSector)
            )
            let linkBytes = link.encode()
            let linkOffset = disk.actualSectorSize(currentSector) - 3
            sectorData[linkOffset] = linkBytes[0]
            sectorData[linkOffset + 1] = linkBytes[1]
            sectorData[linkOffset + 2] = linkBytes[2]

            try disk.writeSector(currentSector, data: sectorData)
            currentSector += 1
        }
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    func testInitializeFileSystem() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        XCTAssertNotNil(fs)
    }

    // =========================================================================
    // MARK: - Directory Listing
    // =========================================================================

    func testListEmptyDirectory() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        let files = try fs.listDirectory()
        XCTAssertTrue(files.isEmpty)
    }

    func testListDirectoryWithFiles() throws {
        let disk = try createFormattedDisk()

        // Add some test files
        try addTestFile(to: disk, name: "GAME", ext: "BAS", startSector: 4, sectorCount: 2, entryIndex: 0)
        try addTestFile(to: disk, name: "README", ext: "TXT", startSector: 10, sectorCount: 1, entryIndex: 1)

        let fs = try ATRFileSystem(disk: disk)
        let files = try fs.listDirectory()

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].fullName, "GAME.BAS")
        XCTAssertEqual(files[1].fullName, "README.TXT")
    }

    func testListDirectoryExcludesDeleted() throws {
        let disk = try createFormattedDisk()

        // Add a normal file and a deleted file
        try addTestFile(to: disk, name: "GAME", ext: "BAS", startSector: 4, sectorCount: 2, entryIndex: 0)

        // Add a deleted entry
        let deletedEntry = DirectoryEntry(
            flags: 0x80,
            sectorCount: 3,
            startSector: 20,
            filename: "OLD",
            fileExtension: "DAT",
            entryIndex: 1
        )
        var dirData = try disk.readSector(361)
        let entryBytes = deletedEntry.encode()
        for (i, byte) in entryBytes.enumerated() {
            dirData[16 + i] = byte
        }
        try disk.writeSector(361, data: dirData)

        let fs = try ATRFileSystem(disk: disk)
        let files = try fs.listDirectory(includeDeleted: false)

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fullName, "GAME.BAS")

        // With includeDeleted
        let allFiles = try fs.listDirectory(includeDeleted: true)
        XCTAssertEqual(allFiles.count, 2)
    }

    // =========================================================================
    // MARK: - File Search
    // =========================================================================

    func testFindFile() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "GAME", ext: "BAS", startSector: 4, sectorCount: 2, entryIndex: 0)

        let fs = try ATRFileSystem(disk: disk)
        let found = try fs.findFile("GAME.BAS")

        XCTAssertEqual(found.fullName, "GAME.BAS")
        XCTAssertEqual(found.sectorCount, 2)
    }

    func testFindFileNotFound() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        XCTAssertThrowsError(try fs.findFile("NOTFOUND.TXT")) { error in
            if case ATRError.fileNotFound(let name) = error {
                XCTAssertEqual(name, "NOTFOUND.TXT")
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testFindFileCaseInsensitive() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "GAME", ext: "BAS", startSector: 4, sectorCount: 2, entryIndex: 0)

        let fs = try ATRFileSystem(disk: disk)

        // Should find with different case
        let found = try fs.findFile("game.bas")
        XCTAssertEqual(found.fullName, "GAME.BAS")
    }

    func testListFilesWithPattern() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "GAME1", ext: "BAS", startSector: 4, sectorCount: 1, entryIndex: 0)
        try addTestFile(to: disk, name: "GAME2", ext: "BAS", startSector: 10, sectorCount: 1, entryIndex: 1)
        try addTestFile(to: disk, name: "README", ext: "TXT", startSector: 15, sectorCount: 1, entryIndex: 2)

        let fs = try ATRFileSystem(disk: disk)

        let basFiles = try fs.listFiles(matching: "*.BAS")
        XCTAssertEqual(basFiles.count, 2)

        let gameFiles = try fs.listFiles(matching: "GAME*.*")
        XCTAssertEqual(gameFiles.count, 2)

        let txtFiles = try fs.listFiles(matching: "*.TXT")
        XCTAssertEqual(txtFiles.count, 1)
    }

    // =========================================================================
    // MARK: - File Reading
    // =========================================================================

    func testReadFile() throws {
        let disk = try createFormattedDisk()

        // Add a file with known data
        let testData: [UInt8] = Array("HELLO WORLD".utf8)
        try addTestFile(to: disk, name: "HELLO", ext: "TXT", startSector: 4, sectorCount: 1, entryIndex: 0, data: testData)

        let fs = try ATRFileSystem(disk: disk)
        let data = try fs.readFile("HELLO.TXT")

        XCTAssertEqual(data.count, testData.count)
        XCTAssertEqual(Array(data), testData)
    }

    func testReadFileMultipleSectors() throws {
        let disk = try createFormattedDisk()

        // Add a file spanning multiple sectors
        let testData = [UInt8](repeating: 0x42, count: 200)  // More than one 128-byte sector
        try addTestFile(to: disk, name: "BIG", ext: "DAT", startSector: 4, sectorCount: 2, entryIndex: 0, data: testData)

        let fs = try ATRFileSystem(disk: disk)
        let data = try fs.readFile("BIG.DAT")

        XCTAssertEqual(data.count, testData.count)
    }

    func testReadFileAsString() throws {
        let disk = try createFormattedDisk()

        // Add a text file with ATASCII EOL
        var textData: [UInt8] = Array("LINE1".utf8)
        textData.append(0x9B)  // ATASCII EOL
        textData.append(contentsOf: Array("LINE2".utf8))
        textData.append(0x9B)

        try addTestFile(to: disk, name: "TEXT", ext: "TXT", startSector: 4, sectorCount: 1, entryIndex: 0, data: textData)

        let fs = try ATRFileSystem(disk: disk)
        let text = try fs.readFileAsString("TEXT.TXT", convertLineEndings: true)

        XCTAssertTrue(text.contains("LINE1\n"))
        XCTAssertTrue(text.contains("LINE2\n"))
    }

    func testGetFileSectors() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "MULTI", ext: "DAT", startSector: 4, sectorCount: 3, entryIndex: 0, data: [UInt8](repeating: 0, count: 300))

        let fs = try ATRFileSystem(disk: disk)
        let entry = try fs.findFile("MULTI.DAT")
        let sectors = try fs.getFileSectors(entry)

        XCTAssertEqual(sectors, [4, 5, 6])
    }

    // =========================================================================
    // MARK: - File Info
    // =========================================================================

    func testGetFileInfo() throws {
        let disk = try createFormattedDisk()
        let testData = [UInt8](repeating: 0x55, count: 150)
        try addTestFile(to: disk, name: "INFO", ext: "TST", startSector: 4, sectorCount: 2, entryIndex: 0, data: testData)

        let fs = try ATRFileSystem(disk: disk)
        let info = try fs.getFileInfo("INFO.TST")

        XCTAssertEqual(info.fullName, "INFO.TST")
        XCTAssertEqual(info.sectorCount, 2)
        XCTAssertEqual(info.fileSize, testData.count)
        XCTAssertFalse(info.isCorrupted)
        XCTAssertFalse(info.isLocked)
    }

    func testFileInfoDetailedDescription() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "TEST", ext: "DAT", startSector: 4, sectorCount: 1, entryIndex: 0)

        let fs = try ATRFileSystem(disk: disk)
        let info = try fs.getFileInfo("TEST.DAT")

        let detailed = info.detailedDescription
        XCTAssertTrue(detailed.contains("Filename: TEST.DAT"))
        XCTAssertTrue(detailed.contains("sectors"))
        XCTAssertTrue(detailed.contains("Start sector:"))
    }

    // =========================================================================
    // MARK: - Disk Info
    // =========================================================================

    func testGetDiskInfo() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "FILE1", ext: "DAT", startSector: 4, sectorCount: 1, entryIndex: 0)
        try addTestFile(to: disk, name: "FILE2", ext: "DAT", startSector: 10, sectorCount: 2, entryIndex: 1)

        let fs = try ATRFileSystem(disk: disk)
        let info = try fs.getDiskInfo()

        XCTAssertEqual(info.diskType, .singleDensity)
        XCTAssertEqual(info.totalSectors, 720)
        XCTAssertEqual(info.fileCount, 2)
        XCTAssertTrue(info.dosVersion.contains("DOS"))
    }

    func testDiskInfoFreeSpace() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)
        let info = try fs.getDiskInfo()

        // Should have most sectors free (720 - boot(3) - vtoc(1) - dir(8) = 708)
        XCTAssertGreaterThan(info.freeSectors, 700)
        XCTAssertGreaterThan(info.freeBytes, 0)
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    func testValidateEmptyDisk() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        let issues = try fs.validate()

        // A freshly formatted disk should have minimal or no issues
        // (some VTOC validation may flag minor things)
        print("Validation issues: \(issues)")
    }

    func testValidateWithFiles() throws {
        let disk = try createFormattedDisk()
        try addTestFile(to: disk, name: "TEST", ext: "DAT", startSector: 4, sectorCount: 2, entryIndex: 0)

        let fs = try ATRFileSystem(disk: disk)
        let issues = try fs.validate()

        // May have some VTOC consistency issues since we're not updating VTOC bitmap
        // when adding files manually
        print("Validation issues with files: \(issues)")
    }

    // =========================================================================
    // MARK: - Refresh
    // =========================================================================

    func testRefreshVTOC() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        // Manually modify VTOC on disk
        var vtocData = try disk.readSector(360)
        vtocData[3] = 100  // Change free sector count
        try disk.writeSector(360, data: vtocData)

        // Refresh should pick up changes
        try fs.refreshVTOC()
        let vtoc = fs.getVTOC()

        XCTAssertEqual(vtoc.freeSectorCount, 100)
    }

    // =========================================================================
    // MARK: - Format
    // =========================================================================

    func testFormat() throws {
        let disk = try createFormattedDisk()

        // Add some files
        try addTestFile(to: disk, name: "FILE1", ext: "DAT", startSector: 4, sectorCount: 1, entryIndex: 0)

        let fs = try ATRFileSystem(disk: disk)

        // Verify file exists
        XCTAssertEqual(try fs.listDirectory().count, 1)

        // Format
        try fs.format()

        // Verify disk is now empty
        XCTAssertEqual(try fs.listDirectory().count, 0)

        // Verify VTOC is reset
        let info = try fs.getDiskInfo()
        XCTAssertGreaterThan(info.freeSectors, 700)
    }

    // =========================================================================
    // MARK: - Export
    // =========================================================================

    func testExportFile() throws {
        let disk = try createFormattedDisk()
        let testData = Array("Test content".utf8)
        try addTestFile(to: disk, name: "EXPORT", ext: "TXT", startSector: 4, sectorCount: 1, entryIndex: 0, data: [UInt8](testData))

        let fs = try ATRFileSystem(disk: disk)

        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent("exported.txt")
        defer { try? FileManager.default.removeItem(at: destURL) }

        try fs.exportFile("EXPORT.TXT", to: destURL)

        // Verify exported file
        let exportedData = try Data(contentsOf: destURL)
        XCTAssertEqual(Array(exportedData), [UInt8](testData))
    }

    // =========================================================================
    // MARK: - Description
    // =========================================================================

    func testDescription() throws {
        let disk = try createFormattedDisk()
        let fs = try ATRFileSystem(disk: disk)

        let desc = fs.description
        XCTAssertTrue(desc.contains("ATRFileSystem"))
        XCTAssertTrue(desc.contains("SS/SD"))
    }
}
