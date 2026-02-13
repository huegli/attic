// =============================================================================
// DiskManagerTests.swift - Integration Tests for DiskManager Actor
// =============================================================================
//
// Tests the DiskManager actor which provides thread-safe management of mounted
// ATR disk images. DiskManager sits above ATRFileSystem and coordinates drive
// operations (mounting, unmounting, file I/O, disk creation).
//
// These tests run in standalone mode (no EmulatorEngine) so only Swift-side
// parsing is exercised. Emulator-coordinated mounting is tested separately
// in the CLI/Server integration tests.
//
// Test Categories (matching beads epic attic-0iv):
// - 9.1 Disk Mounting: mount, unmount, drive listing, density variants
// - 9.2 Directory Operations: list files, wildcard patterns, locked markers
// - 9.3 File Operations: read, write, delete, rename, lock/unlock, import/export
// - 9.4 Disk Creation: create new disks, format existing disks
//
// =============================================================================

import XCTest
@testable import AtticCore

final class DiskManagerTests: XCTestCase {

    // =========================================================================
    // MARK: - Test Fixtures
    // =========================================================================

    /// Temporary directory for test disk images. Cleaned up after each test.
    private var tempDir: URL!

    /// Sets up a fresh temporary directory before each test.
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    /// Removes the temporary directory and all test files after each test.
    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    /// Creates a formatted ATR disk image file on disk.
    ///
    /// This is needed because DiskManager.mount() reads from the filesystem,
    /// unlike ATRFileSystemTests which work with in-memory images.
    ///
    /// - Parameters:
    ///   - name: The filename for the ATR file (e.g., "test.atr").
    ///   - type: The disk density type.
    /// - Returns: The URL of the created disk image.
    private func createTestDisk(
        name: String = "test.atr",
        type: DiskType = .singleDensity
    ) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        _ = try ATRImage.createFormatted(at: url, type: type)
        return url
    }

    /// Creates a formatted ATR disk with some test files already on it.
    ///
    /// - Parameters:
    ///   - name: The ATR filename.
    ///   - type: The disk density type.
    ///   - files: Dictionary of filename -> data to write.
    /// - Returns: The URL of the created disk image.
    private func createTestDiskWithFiles(
        name: String = "test.atr",
        type: DiskType = .singleDensity,
        files: [(name: String, data: Data)]
    ) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let image = try ATRImage.createFormatted(at: url, type: type)
        let fs = try ATRFileSystem(disk: image)

        for file in files {
            try fs.writeFile(file.name, data: file.data)
        }

        try image.save()
        return url
    }

    // =========================================================================
    // MARK: - 9.1 Disk Mounting
    // =========================================================================

    // -------------------------------------------------------------------------
    // MARK: Mount Single Density
    // -------------------------------------------------------------------------

    /// Verifies that a single density (90K) ATR image can be mounted.
    func testMountSingleDensityDisk() async throws {
        let url = try createTestDisk(name: "sd.atr", type: .singleDensity)
        let manager = DiskManager()

        let info = try await manager.mount(drive: 1, path: url.path)

        XCTAssertEqual(info.drive, 1)
        XCTAssertEqual(info.diskType, .singleDensity)
        XCTAssertEqual(info.filename, "sd.atr")
        XCTAssertFalse(info.isReadOnly)
        XCTAssertFalse(info.isModified)
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Enhanced Density
    // -------------------------------------------------------------------------

    /// Verifies that an enhanced density (130K) ATR image can be mounted.
    func testMountEnhancedDensityDisk() async throws {
        let url = try createTestDisk(name: "ed.atr", type: .enhancedDensity)
        let manager = DiskManager()

        let info = try await manager.mount(drive: 1, path: url.path)

        XCTAssertEqual(info.diskType, .enhancedDensity)
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Double Density
    // -------------------------------------------------------------------------

    /// Verifies that a double density (180K) ATR image can be mounted.
    func testMountDoubleDensityDisk() async throws {
        let url = try createTestDisk(name: "dd.atr", type: .doubleDensity)
        let manager = DiskManager()

        let info = try await manager.mount(drive: 1, path: url.path)

        XCTAssertEqual(info.diskType, .doubleDensity)
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Read-Only
    // -------------------------------------------------------------------------

    /// Verifies that a disk can be mounted as read-only.
    func testMountReadOnly() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()

        let info = try await manager.mount(drive: 1, path: url.path, readOnly: true)

        XCTAssertTrue(info.isReadOnly)
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Invalid Path
    // -------------------------------------------------------------------------

    /// Verifies that mounting a non-existent file throws pathNotFound.
    func testMountInvalidPath() async throws {
        let manager = DiskManager()

        do {
            try await manager.mount(drive: 1, path: "/nonexistent/disk.atr")
            XCTFail("Expected pathNotFound error")
        } catch let error as DiskManagerError {
            guard case .pathNotFound = error else {
                XCTFail("Expected pathNotFound, got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Invalid Drive Number
    // -------------------------------------------------------------------------

    /// Verifies that mounting to an out-of-range drive throws invalidDrive.
    func testMountInvalidDrive() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()

        // Drive 0 (too low)
        do {
            try await manager.mount(drive: 0, path: url.path)
            XCTFail("Expected invalidDrive error")
        } catch let error as DiskManagerError {
            guard case .invalidDrive(0) = error else {
                XCTFail("Expected invalidDrive(0), got \(error)")
                return
            }
        }

        // Drive 9 (too high)
        do {
            try await manager.mount(drive: 9, path: url.path)
            XCTFail("Expected invalidDrive error")
        } catch let error as DiskManagerError {
            guard case .invalidDrive(9) = error else {
                XCTFail("Expected invalidDrive(9), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Mount Drive Already In Use
    // -------------------------------------------------------------------------

    /// Verifies that mounting to an occupied drive throws driveInUse.
    func testMountDriveAlreadyInUse() async throws {
        let url1 = try createTestDisk(name: "disk1.atr")
        let url2 = try createTestDisk(name: "disk2.atr")
        let manager = DiskManager()

        try await manager.mount(drive: 1, path: url1.path)

        do {
            try await manager.mount(drive: 1, path: url2.path)
            XCTFail("Expected driveInUse error")
        } catch let error as DiskManagerError {
            guard case .driveInUse(1) = error else {
                XCTFail("Expected driveInUse(1), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Unmount
    // -------------------------------------------------------------------------

    /// Verifies that a mounted disk can be unmounted.
    func testUnmount() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()

        try await manager.mount(drive: 1, path: url.path)
        let mounted = await manager.isDriveMounted(1)
        XCTAssertTrue(mounted)

        try await manager.unmount(drive: 1)
        let unmounted = await manager.isDriveMounted(1)
        XCTAssertFalse(unmounted)
    }

    /// Verifies that unmounting an empty drive throws driveEmpty.
    func testUnmountEmptyDrive() async throws {
        let manager = DiskManager()

        do {
            try await manager.unmount(drive: 1)
            XCTFail("Expected driveEmpty error")
        } catch let error as DiskManagerError {
            guard case .driveEmpty(1) = error else {
                XCTFail("Expected driveEmpty(1), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Multiple Drives
    // -------------------------------------------------------------------------

    /// Verifies that all 8 drives can be mounted simultaneously.
    func testMountAllEightDrives() async throws {
        let manager = DiskManager()

        for i in 1...8 {
            let url = try createTestDisk(name: "disk\(i).atr")
            try await manager.mount(drive: i, path: url.path)
        }

        let drives = await manager.listDrives()
        let mountedCount = drives.filter { $0.mounted }.count
        XCTAssertEqual(mountedCount, 8)
    }

    // -------------------------------------------------------------------------
    // MARK: List Drives
    // -------------------------------------------------------------------------

    /// Verifies that listDrives returns status for all 8 drives.
    func testListDrives() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()

        try await manager.mount(drive: 2, path: url.path)

        let drives = await manager.listDrives()
        XCTAssertEqual(drives.count, 8)

        // Drive 1 should be empty
        XCTAssertFalse(drives[0].mounted)
        XCTAssertNil(drives[0].path)

        // Drive 2 should be mounted
        XCTAssertTrue(drives[1].mounted)
        XCTAssertNotNil(drives[1].path)
        XCTAssertEqual(drives[1].diskType, .singleDensity)
    }

    /// Verifies that DriveStatus.displayString formats correctly.
    func testDriveStatusDisplayString() async throws {
        let url = try createTestDisk(name: "game.atr")
        let manager = DiskManager()

        try await manager.mount(drive: 3, path: url.path)

        let drives = await manager.listDrives()
        let d3 = drives[2]

        XCTAssertTrue(d3.displayString.contains("D3:"))
        XCTAssertTrue(d3.displayString.contains("game.atr"))
        XCTAssertTrue(d3.displayString.contains("SS/SD"))

        // Empty drive
        let d1 = drives[0]
        XCTAssertEqual(d1.displayString, "D1: (empty)")
    }

    // -------------------------------------------------------------------------
    // MARK: isDriveMounted
    // -------------------------------------------------------------------------

    /// Verifies the isDriveMounted convenience method.
    func testIsDriveMounted() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()

        // Invalid drives should return false, not throw
        let outOfRange = await manager.isDriveMounted(0)
        XCTAssertFalse(outOfRange)

        let empty = await manager.isDriveMounted(1)
        XCTAssertFalse(empty)

        try await manager.mount(drive: 1, path: url.path)
        let mounted = await manager.isDriveMounted(1)
        XCTAssertTrue(mounted)
    }

    // -------------------------------------------------------------------------
    // MARK: Track Booted Disk
    // -------------------------------------------------------------------------

    /// Verifies that trackBootedDisk registers an externally-mounted disk.
    func testTrackBootedDisk() async throws {
        let url = try createTestDisk(name: "boot.atr")
        let manager = DiskManager()

        await manager.trackBootedDisk(drive: 1, path: url.path)

        let mounted = await manager.isDriveMounted(1)
        XCTAssertTrue(mounted)

        let drives = await manager.listDrives()
        XCTAssertTrue(drives[0].mounted)
        XCTAssertTrue(drives[0].path?.hasSuffix("boot.atr") ?? false)
    }

    /// Verifies that trackBootedDisk silently ignores non-ATR files.
    func testTrackBootedDiskNonATRFile() async throws {
        // Create a random non-ATR file
        let url = tempDir.appendingPathComponent("game.xex")
        try Data([0xFF, 0xFF, 0x00, 0x06]).write(to: url)

        let manager = DiskManager()
        await manager.trackBootedDisk(drive: 1, path: url.path)

        // Should NOT be tracked (not a valid ATR)
        let mounted = await manager.isDriveMounted(1)
        XCTAssertFalse(mounted)
    }

    // -------------------------------------------------------------------------
    // MARK: Change Drive
    // -------------------------------------------------------------------------

    /// Verifies that the current drive can be changed.
    func testChangeDrive() async throws {
        let url1 = try createTestDisk(name: "d1.atr")
        let url2 = try createTestDisk(name: "d2.atr")
        let manager = DiskManager()

        try await manager.mount(drive: 1, path: url1.path)
        try await manager.mount(drive: 2, path: url2.path)

        let initial = await manager.currentDrive
        XCTAssertEqual(initial, 1)

        try await manager.changeDrive(to: 2)
        let current = await manager.currentDrive
        XCTAssertEqual(current, 2)
    }

    /// Verifies that changing to an empty drive throws driveEmpty.
    func testChangeDriveToEmpty() async throws {
        let manager = DiskManager()

        do {
            try await manager.changeDrive(to: 5)
            XCTFail("Expected driveEmpty error")
        } catch let error as DiskManagerError {
            guard case .driveEmpty(5) = error else {
                XCTFail("Expected driveEmpty(5), got \(error)")
                return
            }
        }
    }

    /// Verifies that unmounting the current drive resets it to drive 1.
    func testUnmountCurrentDriveResetsToDrive1() async throws {
        let url1 = try createTestDisk(name: "d1.atr")
        let url2 = try createTestDisk(name: "d2.atr")
        let manager = DiskManager()

        try await manager.mount(drive: 1, path: url1.path)
        try await manager.mount(drive: 2, path: url2.path)
        try await manager.changeDrive(to: 2)

        try await manager.unmount(drive: 2)

        let current = await manager.currentDrive
        XCTAssertEqual(current, 1)
    }

    // =========================================================================
    // MARK: - 9.2 Directory Operations
    // =========================================================================

    // -------------------------------------------------------------------------
    // MARK: List All Files
    // -------------------------------------------------------------------------

    /// Verifies listing all files on a mounted disk.
    func testListDirectory() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "GAME.BAS", data: Data("10 PRINT \"HELLO\"".utf8)),
            (name: "README.TXT", data: Data("Read me".utf8)),
            (name: "DATA.DAT", data: Data(repeating: 0x55, count: 50)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let files = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(files.count, 3)

        let names = files.map { $0.fullName }
        XCTAssertTrue(names.contains("GAME.BAS"))
        XCTAssertTrue(names.contains("README.TXT"))
        XCTAssertTrue(names.contains("DATA.DAT"))
    }

    /// Verifies listing files on the current drive (nil drive parameter).
    func testListDirectoryCurrentDrive() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "FILE.TXT", data: Data("content".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // nil drive should use currentDrive (default 1)
        let files = try await manager.listDirectory()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fullName, "FILE.TXT")
    }

    // -------------------------------------------------------------------------
    // MARK: Wildcard Patterns
    // -------------------------------------------------------------------------

    /// Verifies wildcard pattern filtering in directory listing.
    func testListDirectoryWithPattern() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "GAME1.BAS", data: Data("10 REM".utf8)),
            (name: "GAME2.BAS", data: Data("20 REM".utf8)),
            (name: "README.TXT", data: Data("info".utf8)),
            (name: "SCORES.DAT", data: Data(repeating: 0, count: 10)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // Match *.BAS
        let basFiles = try await manager.listDirectory(drive: 1, pattern: "*.BAS")
        XCTAssertEqual(basFiles.count, 2)

        // Match *.TXT
        let txtFiles = try await manager.listDirectory(drive: 1, pattern: "*.TXT")
        XCTAssertEqual(txtFiles.count, 1)
        XCTAssertEqual(txtFiles[0].fullName, "README.TXT")

        // Match GAME*.*
        let gameFiles = try await manager.listDirectory(drive: 1, pattern: "GAME*.*")
        XCTAssertEqual(gameFiles.count, 2)
    }

    // -------------------------------------------------------------------------
    // MARK: File Sizes in Listing
    // -------------------------------------------------------------------------

    /// Verifies that directory entries report correct sector counts.
    func testDirectoryShowsSectorCounts() async throws {
        let url = try createTestDiskWithFiles(files: [
            // Small file: 1 sector
            (name: "SMALL.TXT", data: Data("Hi".utf8)),
            // Larger file: multiple sectors (>125 bytes for SD)
            (name: "BIG.DAT", data: Data(repeating: 0xAA, count: 500)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let files = try await manager.listDirectory(drive: 1)
        let small = files.first { $0.fullName == "SMALL.TXT" }
        let big = files.first { $0.fullName == "BIG.DAT" }

        XCTAssertNotNil(small)
        XCTAssertNotNil(big)
        XCTAssertEqual(small?.sectorCount, 1)
        XCTAssertEqual(big?.sectorCount, 4)  // 500 / 125 = 4 sectors
    }

    // -------------------------------------------------------------------------
    // MARK: Locked Files Marked
    // -------------------------------------------------------------------------

    /// Verifies that locked files are identified in directory listings.
    func testDirectoryShowsLockedFiles() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "OPEN.TXT", data: Data("open".utf8)),
            (name: "LOCKED.TXT", data: Data("locked".utf8)),
        ])

        // Lock one file directly via ATRFileSystem before mounting in DiskManager
        let image = try ATRImage(url: url)
        let fs = try ATRFileSystem(disk: image)
        try fs.lockFile("LOCKED.TXT")
        try image.save()

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let files = try await manager.listDirectory(drive: 1)
        let open = files.first { $0.fullName == "OPEN.TXT" }
        let locked = files.first { $0.fullName == "LOCKED.TXT" }

        XCTAssertNotNil(open)
        XCTAssertNotNil(locked)
        XCTAssertFalse(open!.isLocked)
        XCTAssertTrue(locked!.isLocked)
    }

    // -------------------------------------------------------------------------
    // MARK: List Directory on Empty Drive
    // -------------------------------------------------------------------------

    /// Verifies that listing an empty drive throws driveEmpty.
    func testListDirectoryEmptyDrive() async throws {
        let manager = DiskManager()

        do {
            _ = try await manager.listDirectory(drive: 3)
            XCTFail("Expected driveEmpty error")
        } catch let error as DiskManagerError {
            guard case .driveEmpty(3) = error else {
                XCTFail("Expected driveEmpty(3), got \(error)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - 9.3 File Operations
    // =========================================================================

    // -------------------------------------------------------------------------
    // MARK: Read File
    // -------------------------------------------------------------------------

    /// Verifies reading a file via DiskManager.
    func testReadFile() async throws {
        let content = Data("HELLO WORLD FROM ATARI".utf8)
        let url = try createTestDiskWithFiles(files: [
            (name: "HELLO.TXT", data: content),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let data = try await manager.readFile(drive: 1, name: "HELLO.TXT")
        XCTAssertEqual(data, content)
    }

    /// Verifies reading a file from the current drive.
    func testReadFileCurrentDrive() async throws {
        let content = Data("current drive test".utf8)
        let url = try createTestDiskWithFiles(files: [
            (name: "TEST.DAT", data: content),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let data = try await manager.readFile(name: "TEST.DAT")
        XCTAssertEqual(data, content)
    }

    // -------------------------------------------------------------------------
    // MARK: Get File Info
    // -------------------------------------------------------------------------

    /// Verifies getting detailed file info through DiskManager.
    func testGetFileInfo() async throws {
        let content = Data(repeating: 0x42, count: 300)
        let url = try createTestDiskWithFiles(files: [
            (name: "INFO.DAT", data: content),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let info = try await manager.getFileInfo(drive: 1, name: "INFO.DAT")
        XCTAssertEqual(info.fullName, "INFO.DAT")
        XCTAssertEqual(info.fileSize, 300)
        XCTAssertFalse(info.isCorrupted)
        XCTAssertFalse(info.isLocked)
    }

    // -------------------------------------------------------------------------
    // MARK: Write File
    // -------------------------------------------------------------------------

    /// Verifies writing a new file through DiskManager.
    func testWriteFile() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let content = Data("Written via DiskManager".utf8)
        let sectors = try await manager.writeFile(drive: 1, name: "NEW.TXT", data: content)

        XCTAssertEqual(sectors, 1)

        // Read it back
        let data = try await manager.readFile(drive: 1, name: "NEW.TXT")
        XCTAssertEqual(data, content)
    }

    /// Verifies that writing to a read-only drive throws diskReadOnly.
    func testWriteFileReadOnly() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path, readOnly: true)

        do {
            try await manager.writeFile(drive: 1, name: "FAIL.TXT", data: Data("x".utf8))
            XCTFail("Expected diskReadOnly error")
        } catch let error as DiskManagerError {
            guard case .diskReadOnly(1) = error else {
                XCTFail("Expected diskReadOnly(1), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Delete File
    // -------------------------------------------------------------------------

    /// Verifies deleting a file through DiskManager.
    func testDeleteFile() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "DELETE.ME", data: Data("bye".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // File should exist
        let before = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(before.count, 1)

        try await manager.deleteFile(drive: 1, name: "DELETE.ME")

        // File should be gone
        let after = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(after.count, 0)
    }

    /// Verifies that deleting from a read-only drive throws diskReadOnly.
    func testDeleteFileReadOnly() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "KEEP.TXT", data: Data("keep".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path, readOnly: true)

        do {
            try await manager.deleteFile(drive: 1, name: "KEEP.TXT")
            XCTFail("Expected diskReadOnly error")
        } catch let error as DiskManagerError {
            guard case .diskReadOnly(1) = error else {
                XCTFail("Expected diskReadOnly(1), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Rename File
    // -------------------------------------------------------------------------

    /// Verifies renaming a file through DiskManager.
    func testRenameFile() async throws {
        let content = Data("rename me".utf8)
        let url = try createTestDiskWithFiles(files: [
            (name: "OLD.TXT", data: content),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        try await manager.renameFile(drive: 1, from: "OLD.TXT", to: "NEW.TXT")

        // Old name should be gone, new name should have same data
        let files = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fullName, "NEW.TXT")

        let data = try await manager.readFile(drive: 1, name: "NEW.TXT")
        XCTAssertEqual(data, content)
    }

    // -------------------------------------------------------------------------
    // MARK: Lock / Unlock
    // -------------------------------------------------------------------------

    /// Verifies locking and unlocking a file through DiskManager.
    func testLockUnlockFile() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "LOCK.TXT", data: Data("lock test".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // Initially unlocked
        var info = try await manager.getFileInfo(drive: 1, name: "LOCK.TXT")
        XCTAssertFalse(info.isLocked)

        // Lock
        try await manager.lockFile(drive: 1, name: "LOCK.TXT")
        info = try await manager.getFileInfo(drive: 1, name: "LOCK.TXT")
        XCTAssertTrue(info.isLocked)

        // Unlock
        try await manager.unlockFile(drive: 1, name: "LOCK.TXT")
        info = try await manager.getFileInfo(drive: 1, name: "LOCK.TXT")
        XCTAssertFalse(info.isLocked)
    }

    /// Verifies that locking on a read-only drive throws diskReadOnly.
    func testLockFileReadOnly() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "FILE.TXT", data: Data("data".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path, readOnly: true)

        do {
            try await manager.lockFile(drive: 1, name: "FILE.TXT")
            XCTFail("Expected diskReadOnly error")
        } catch let error as DiskManagerError {
            guard case .diskReadOnly(1) = error else {
                XCTFail("Expected diskReadOnly(1), got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Export File to Host
    // -------------------------------------------------------------------------

    /// Verifies exporting a file from disk to the host filesystem.
    func testExportFile() async throws {
        let content = Data("Export this content".utf8)
        let url = try createTestDiskWithFiles(files: [
            (name: "EXPORT.TXT", data: content),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        let hostPath = tempDir.appendingPathComponent("exported.txt").path
        let bytes = try await manager.exportFile(drive: 1, name: "EXPORT.TXT", to: hostPath)

        XCTAssertEqual(bytes, content.count)

        // Verify exported file on host
        let exported = try Data(contentsOf: URL(fileURLWithPath: hostPath))
        XCTAssertEqual(exported, content)
    }

    // -------------------------------------------------------------------------
    // MARK: Import File from Host
    // -------------------------------------------------------------------------

    /// Verifies importing a host file onto an Atari disk.
    func testImportFile() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // Create a host file to import
        let hostContent = Data("Imported from macOS".utf8)
        let hostPath = tempDir.appendingPathComponent("import_me.txt")
        try hostContent.write(to: hostPath)

        let sectors = try await manager.importFile(
            from: hostPath.path,
            drive: 1,
            name: "IMPORT.TXT"
        )
        XCTAssertGreaterThan(sectors, 0)

        // Read it back from the disk
        let data = try await manager.readFile(drive: 1, name: "IMPORT.TXT")
        XCTAssertEqual(data, hostContent)
    }

    /// Verifies that importing a non-existent host file throws pathNotFound.
    func testImportFileNotFound() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        do {
            try await manager.importFile(
                from: "/nonexistent/file.txt",
                drive: 1,
                name: "FAIL.TXT"
            )
            XCTFail("Expected pathNotFound error")
        } catch let error as DiskManagerError {
            guard case .pathNotFound = error else {
                XCTFail("Expected pathNotFound, got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Copy File Between Drives
    // -------------------------------------------------------------------------

    /// Verifies copying a file between two mounted drives.
    func testCopyFileBetweenDrives() async throws {
        let url1 = try createTestDiskWithFiles(
            name: "src.atr",
            files: [(name: "SOURCE.TXT", data: Data("copy me".utf8))]
        )
        let url2 = try createTestDisk(name: "dest.atr")

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url1.path)
        try await manager.mount(drive: 2, path: url2.path)

        let sectors = try await manager.copyFile(
            from: 1,
            name: "SOURCE.TXT",
            to: 2
        )
        XCTAssertGreaterThan(sectors, 0)

        // Verify file exists on drive 2 with same data
        let data = try await manager.readFile(drive: 2, name: "SOURCE.TXT")
        XCTAssertEqual(data, Data("copy me".utf8))
    }

    /// Verifies copying a file with a different destination name.
    func testCopyFileWithRename() async throws {
        let url1 = try createTestDiskWithFiles(
            name: "src.atr",
            files: [(name: "ORIG.DAT", data: Data("data".utf8))]
        )
        let url2 = try createTestDisk(name: "dest.atr")

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url1.path)
        try await manager.mount(drive: 2, path: url2.path)

        try await manager.copyFile(
            from: 1,
            name: "ORIG.DAT",
            to: 2,
            as: "COPY.DAT"
        )

        let files = try await manager.listDirectory(drive: 2)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fullName, "COPY.DAT")
    }

    // =========================================================================
    // MARK: - 9.4 Disk Creation
    // =========================================================================

    // -------------------------------------------------------------------------
    // MARK: Create New Single Density Disk
    // -------------------------------------------------------------------------

    /// Verifies creating a new single density disk image.
    func testCreateDiskSingleDensity() async throws {
        let manager = DiskManager()
        let path = tempDir.appendingPathComponent("new_sd.atr").path

        let resultURL = try await manager.createDisk(at: path, type: .singleDensity)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))

        // Mount and verify it's a valid empty disk
        try await manager.mount(drive: 1, path: resultURL.path)
        let files = try await manager.listDirectory(drive: 1)
        XCTAssertTrue(files.isEmpty)

        let info = try await manager.getInfo(drive: 1)
        XCTAssertEqual(info.diskType, .singleDensity)
        XCTAssertGreaterThan(info.freeSectors, 700)
    }

    // -------------------------------------------------------------------------
    // MARK: Create New Enhanced Density Disk
    // -------------------------------------------------------------------------

    /// Verifies creating a new enhanced density disk image.
    func testCreateDiskEnhancedDensity() async throws {
        let manager = DiskManager()
        let path = tempDir.appendingPathComponent("new_ed.atr").path

        let resultURL = try await manager.createDisk(at: path, type: .enhancedDensity)

        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))

        try await manager.mount(drive: 1, path: resultURL.path)
        let info = try await manager.getInfo(drive: 1)
        XCTAssertEqual(info.diskType, .enhancedDensity)
    }

    // -------------------------------------------------------------------------
    // MARK: Create New Double Density Disk
    // -------------------------------------------------------------------------

    /// Verifies creating a new double density disk image.
    func testCreateDiskDoubleDensity() async throws {
        let manager = DiskManager()
        let path = tempDir.appendingPathComponent("new_dd.atr").path

        let resultURL = try await manager.createDisk(at: path, type: .doubleDensity)

        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))

        try await manager.mount(drive: 1, path: resultURL.path)
        let info = try await manager.getInfo(drive: 1)
        XCTAssertEqual(info.diskType, .doubleDensity)
    }

    // -------------------------------------------------------------------------
    // MARK: Format Existing Disk
    // -------------------------------------------------------------------------

    /// Verifies formatting an existing disk erases all files.
    func testFormatDisk() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "FILE1.TXT", data: Data("one".utf8)),
            (name: "FILE2.TXT", data: Data("two".utf8)),
            (name: "FILE3.TXT", data: Data("three".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // Verify files exist
        let before = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(before.count, 3)

        // Format
        try await manager.formatDisk(drive: 1)

        // Verify disk is now empty
        let after = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(after.count, 0)
    }

    /// Verifies formatting a read-only disk throws diskReadOnly.
    func testFormatDiskReadOnly() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path, readOnly: true)

        do {
            try await manager.formatDisk(drive: 1)
            XCTFail("Expected diskReadOnly error")
        } catch let error as DiskManagerError {
            guard case .diskReadOnly(1) = error else {
                XCTFail("Expected diskReadOnly(1), got \(error)")
                return
            }
        }
    }

    /// Verifies formatting the current drive (nil drive parameter).
    func testFormatCurrentDrive() async throws {
        let url = try createTestDiskWithFiles(files: [
            (name: "GONE.TXT", data: Data("bye".utf8)),
        ])

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        try await manager.formatDisk()

        let files = try await manager.listDirectory()
        XCTAssertTrue(files.isEmpty)
    }

    // -------------------------------------------------------------------------
    // MARK: Create Disk Then Use It
    // -------------------------------------------------------------------------

    /// End-to-end test: create a disk, mount it, write files, read them back.
    func testCreateMountWriteReadWorkflow() async throws {
        let manager = DiskManager()
        let path = tempDir.appendingPathComponent("workflow.atr").path

        // Create
        let diskURL = try await manager.createDisk(at: path, type: .singleDensity)

        // Mount
        try await manager.mount(drive: 1, path: diskURL.path)

        // Write multiple files
        let file1 = Data("10 PRINT \"HELLO\"\n20 GOTO 10".utf8)
        let file2 = Data(repeating: 0xFF, count: 256)
        try await manager.writeFile(drive: 1, name: "HELLO.BAS", data: file1)
        try await manager.writeFile(drive: 1, name: "DATA.BIN", data: file2)

        // List and verify
        let files = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(files.count, 2)

        // Read back and verify
        let read1 = try await manager.readFile(drive: 1, name: "HELLO.BAS")
        XCTAssertEqual(read1, file1)

        let read2 = try await manager.readFile(drive: 1, name: "DATA.BIN")
        XCTAssertEqual(read2, file2)

        // Unmount
        try await manager.unmount(drive: 1)
        let mounted = await manager.isDriveMounted(1)
        XCTAssertFalse(mounted)
    }

    // =========================================================================
    // MARK: - Error Message Tests
    // =========================================================================

    /// Verifies that DiskManagerError produces readable error descriptions.
    func testErrorDescriptions() {
        let errors: [(DiskManagerError, String)] = [
            (.invalidDrive(0), "Invalid drive number: 0 (must be 1-8)"),
            (.driveEmpty(3), "Drive D3: is empty"),
            (.driveInUse(2), "Drive D2: already has a disk mounted"),
            (.mountFailed("bad file"), "Failed to mount disk: bad file"),
            (.pathNotFound("/foo.atr"), "Path not found: /foo.atr"),
            (.diskReadOnly(1), "Disk in D1: is read-only"),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    // =========================================================================
    // MARK: - Save Operations
    // =========================================================================

    /// Verifies saving a single drive's changes.
    func testSaveDisk() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path)

        // Write a file (modifies the disk)
        try await manager.writeFile(drive: 1, name: "SAVE.TXT", data: Data("save me".utf8))

        // Save
        try await manager.saveDisk(drive: 1)

        // Remount and verify data persisted
        try await manager.unmount(drive: 1, save: false)
        try await manager.mount(drive: 1, path: url.path)

        let files = try await manager.listDirectory(drive: 1)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].fullName, "SAVE.TXT")
    }

    /// Verifies saving all modified disks at once.
    func testSaveAllDisks() async throws {
        let url1 = try createTestDisk(name: "save1.atr")
        let url2 = try createTestDisk(name: "save2.atr")

        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url1.path)
        try await manager.mount(drive: 2, path: url2.path)

        // Modify both
        try await manager.writeFile(drive: 1, name: "A.TXT", data: Data("a".utf8))
        try await manager.writeFile(drive: 2, name: "B.TXT", data: Data("b".utf8))

        let saved = try await manager.saveAllDisks()
        XCTAssertEqual(saved, 2)
    }

    /// Verifies that saving a read-only disk throws diskReadOnly.
    func testSaveDiskReadOnly() async throws {
        let url = try createTestDisk()
        let manager = DiskManager()
        try await manager.mount(drive: 1, path: url.path, readOnly: true)

        do {
            try await manager.saveDisk(drive: 1)
            XCTFail("Expected diskReadOnly error")
        } catch let error as DiskManagerError {
            guard case .diskReadOnly(1) = error else {
                XCTFail("Expected diskReadOnly(1), got \(error)")
                return
            }
        }
    }
}
