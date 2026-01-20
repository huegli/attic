// =============================================================================
// DOSModeIntegrationTests.swift - Integration Tests for DOS Mode Through REPL
// =============================================================================
//
// This file contains integration tests for the DOS mode functionality
// accessible through the REPL. These tests verify the full end-to-end
// flow of DOS commands from parsing through execution.
//
// Test Categories:
// 1. REPL DOS mode switching
// 2. Drive management through REPL (mount, unmount, drives, cd)
// 3. Directory operations through REPL (dir, info)
// 4. File viewing through REPL (type, dump)
// 5. File operations through REPL (delete, rename, lock, unlock)
// 6. Host transfer through REPL (export, import)
// 7. Disk management through REPL (newdisk, format)
// 8. Error handling and edge cases
//
// Running tests:
//   swift test --filter DOSModeIntegration
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - DOS Mode REPL Integration Tests
// =============================================================================

/// Integration tests for DOS mode through the REPLEngine.
///
/// These tests create a mock emulator environment and test the full
/// command flow from REPL input to output.
final class DOSModeIntegrationTests: XCTestCase {
    var tempDir: URL!
    var engine: EmulatorEngine!
    var repl: REPLEngine!

    override func setUp() async throws {
        try await super.setUp()

        // Create temp directory for test disk images
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create emulator engine (doesn't need to be initialized for DOS mode tests)
        engine = EmulatorEngine()

        // Create REPL engine starting in DOS mode
        repl = REPLEngine(emulator: engine, initialMode: .dos)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Mode Switching Tests
    // =========================================================================

    /// Test switching to DOS mode.
    func test_switchToDOSMode() async {
        // Start in basic mode
        let basicRepl = REPLEngine(emulator: engine, initialMode: .basic(variant: .atari))

        let output = await basicRepl.execute(".dos")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("dos") ?? false)

        // Verify prompt changes to DOS format
        let prompt = await basicRepl.prompt
        XCTAssertTrue(prompt.contains("[dos]"))
        XCTAssertTrue(prompt.contains("D"))
    }

    /// Test DOS mode prompt format.
    func test_dosPrompt() async {
        let prompt = await repl.prompt
        XCTAssertTrue(prompt.hasPrefix("[dos]"))
        XCTAssertTrue(prompt.contains("D1:"))
        XCTAssertTrue(prompt.hasSuffix("> "))
    }

    // =========================================================================
    // MARK: - Drive Management Tests
    // =========================================================================

    /// Test drives command with no disks mounted.
    func test_drives_empty() async {
        let output = await repl.execute("drives")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("D1:") ?? false)
        XCTAssertTrue(output?.contains("(empty)") ?? false)
    }

    /// Test mount command with valid disk.
    func test_mount_valid() async throws {
        // Create a test disk image
        let diskPath = tempDir.appendingPathComponent("test.atr").path
        _ = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)

        let output = await repl.execute("mount 1 \(diskPath)")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Mounted D1:") ?? false)
        XCTAssertTrue(output?.contains("test.atr") ?? false)
        XCTAssertTrue(output?.contains("Single Density") ?? false)
    }

    /// Test mount command with nonexistent file.
    func test_mount_notFound() async {
        let output = await repl.execute("mount 1 /nonexistent/path/disk.atr")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
        XCTAssertTrue(output?.lowercased().contains("not found") ?? false)
    }

    /// Test mount command with invalid drive.
    func test_mount_invalidDrive() async {
        // This should fail at parse time
        do {
            let parser = CommandParser()
            _ = try parser.parse("mount 0 /test.atr", mode: .dos)
            XCTFail("Should throw for invalid drive")
        } catch {
            // Expected
        }
    }

    /// Test unmount command.
    func test_unmount() async throws {
        // Mount first
        let diskPath = tempDir.appendingPathComponent("unmount_test.atr").path
        _ = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        _ = await repl.execute("mount 1 \(diskPath)")

        // Unmount
        let output = await repl.execute("unmount 1")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Unmounted D1:") ?? false)
    }

    /// Test unmount empty drive.
    func test_unmount_emptyDrive() async {
        let output = await repl.execute("unmount 5")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test cd command.
    func test_cd() async throws {
        // Mount disks on drives 1 and 2
        let disk1 = tempDir.appendingPathComponent("disk1.atr").path
        let disk2 = tempDir.appendingPathComponent("disk2.atr").path
        _ = try ATRImage.create(at: URL(fileURLWithPath: disk1), type: .singleDensity)
        _ = try ATRImage.create(at: URL(fileURLWithPath: disk2), type: .singleDensity)

        _ = await repl.execute("mount 1 \(disk1)")
        _ = await repl.execute("mount 2 \(disk2)")

        // Change to drive 2
        let output = await repl.execute("cd 2")
        XCTAssertTrue(output?.contains("Changed to D2:") ?? false)

        // Verify prompt updated
        let prompt = await repl.prompt
        XCTAssertTrue(prompt.contains("D2:"))
    }

    /// Test cd to empty drive fails.
    func test_cd_emptyDrive() async {
        let output = await repl.execute("cd 8")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    // =========================================================================
    // MARK: - Directory Operations Tests
    // =========================================================================

    /// Test dir command on empty disk.
    func test_dir_emptyDisk() async throws {
        let diskPath = tempDir.appendingPathComponent("empty.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("dir")

        XCTAssertNotNil(output)
        // Empty disk should show no files
        XCTAssertTrue(output?.contains("No files") ?? false || output?.contains("0 files") ?? false)
    }

    /// Test dir command when no disk mounted.
    func test_dir_noDisk() async {
        let output = await repl.execute("dir")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test info command when file not found.
    func test_info_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("info_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("info NOTEXIST.COM")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
        XCTAssertTrue(output?.lowercased().contains("not found") ?? false)
    }

    // =========================================================================
    // MARK: - File Viewing Tests
    // =========================================================================

    /// Test type command when file not found.
    func test_type_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("type_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("type MISSING.TXT")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test dump command when file not found.
    func test_dump_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("dump_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("dump MISSING.COM")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    // =========================================================================
    // MARK: - File Operations Tests
    // =========================================================================

    /// Test delete command when file not found.
    func test_delete_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("delete_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("delete GHOST.COM")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test rename command when file not found.
    func test_rename_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("rename_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("rename NOTHERE.COM THERE.COM")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test lock command when file not found.
    func test_lock_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("lock_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("lock MISSING.DAT")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test unlock command when file not found.
    func test_unlock_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("unlock_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("unlock MISSING.DAT")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test copy command (not yet implemented).
    func test_copy_notImplemented() async throws {
        let diskPath = tempDir.appendingPathComponent("copy_test.atr").path
        _ = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("copy SRC.COM DST.COM")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false || output?.contains("not yet implemented") ?? false)
    }

    // =========================================================================
    // MARK: - Host Transfer Tests
    // =========================================================================

    /// Test export command when file not found.
    func test_export_fileNotFound() async throws {
        let diskPath = tempDir.appendingPathComponent("export_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("export MISSING.COM ~/Desktop/missing.com")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test import command (not yet fully implemented).
    func test_import_notImplemented() async throws {
        let diskPath = tempDir.appendingPathComponent("import_test.atr").path
        let disk = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)
        let fs = try ATRFileSystem(disk: disk)
        try fs.format()
        try disk.save()

        // Create a file to import
        let hostFile = tempDir.appendingPathComponent("import_source.txt")
        try "test content".write(to: hostFile, atomically: true, encoding: .utf8)

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("import \(hostFile.path) IMPORTED.TXT")

        XCTAssertNotNil(output)
        // May error because import isn't fully implemented
        XCTAssertTrue(output?.contains("Error") ?? false || output?.contains("Imported") ?? false)
    }

    // =========================================================================
    // MARK: - Disk Management Tests
    // =========================================================================

    /// Test newdisk command creates new ATR.
    func test_newdisk() async {
        let newDiskPath = tempDir.appendingPathComponent("created.atr").path

        let output = await repl.execute("newdisk \(newDiskPath) ss/sd")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Created") ?? false)
        XCTAssertTrue(output?.contains("Single Density") ?? false)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDiskPath))
    }

    /// Test newdisk command with default type.
    func test_newdisk_defaultType() async {
        let newDiskPath = tempDir.appendingPathComponent("default.atr").path

        let output = await repl.execute("newdisk \(newDiskPath)")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Created") ?? false)
    }

    /// Test format command.
    func test_format() async throws {
        let diskPath = tempDir.appendingPathComponent("format_test.atr").path
        _ = try ATRImage.create(at: URL(fileURLWithPath: diskPath), type: .singleDensity)

        _ = await repl.execute("mount 1 \(diskPath)")
        let output = await repl.execute("format")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Formatted D1:") ?? false)
    }

    /// Test format on empty drive.
    func test_format_emptyDrive() async {
        let output = await repl.execute("format")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    // =========================================================================
    // MARK: - Help Text Tests
    // =========================================================================

    /// Test help in DOS mode shows DOS commands.
    func test_help_showsDOSCommands() async {
        let output = await repl.execute(".help")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("DOS Mode Commands") ?? false)
        XCTAssertTrue(output?.contains("mount") ?? false)
        XCTAssertTrue(output?.contains("dir") ?? false)
        XCTAssertTrue(output?.contains("export") ?? false)
    }

    // =========================================================================
    // MARK: - Error Handling Tests
    // =========================================================================

    /// Test unknown command in DOS mode.
    func test_unknownCommand() async {
        let output = await repl.execute("unknowncmd")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test empty command.
    func test_emptyCommand() async {
        let output = await repl.execute("")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false)
    }

    /// Test command with missing arguments.
    func test_missingArguments() async {
        let output = await repl.execute("info")

        XCTAssertNotNil(output)
        XCTAssertTrue(output?.contains("Error") ?? false || output?.lowercased().contains("usage") ?? false)
    }
}

// =============================================================================
// MARK: - DOS Mode Workflow Tests
// =============================================================================

/// Tests for complete DOS mode workflows.
final class DOSModeWorkflowTests: XCTestCase {
    var tempDir: URL!
    var engine: EmulatorEngine!
    var repl: REPLEngine!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        engine = EmulatorEngine()
        repl = REPLEngine(emulator: engine, initialMode: .dos)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    /// Test complete workflow: create disk, mount, check directory.
    func test_workflow_createMountDir() async {
        let diskPath = tempDir.appendingPathComponent("workflow.atr").path

        // Create disk
        var output = await repl.execute("newdisk \(diskPath) ss/sd")
        XCTAssertTrue(output?.contains("Created") ?? false)

        // Mount disk
        output = await repl.execute("mount 1 \(diskPath)")
        XCTAssertTrue(output?.contains("Mounted") ?? false)

        // Check directory (should be empty after format)
        output = await repl.execute("dir")
        XCTAssertNotNil(output)

        // Check drives
        output = await repl.execute("drives")
        XCTAssertTrue(output?.contains("workflow.atr") ?? false)
    }

    /// Test workflow with multiple drives.
    func test_workflow_multipleDrives() async throws {
        let disk1 = tempDir.appendingPathComponent("drive1.atr").path
        let disk2 = tempDir.appendingPathComponent("drive2.atr").path

        // Create both disks
        _ = try ATRImage.create(at: URL(fileURLWithPath: disk1), type: .singleDensity)
        _ = try ATRImage.create(at: URL(fileURLWithPath: disk2), type: .doubleDensity)

        // Mount both
        _ = await repl.execute("mount 1 \(disk1)")
        _ = await repl.execute("mount 2 \(disk2)")

        // Verify drives shows both
        let output = await repl.execute("drives")
        XCTAssertTrue(output?.contains("D1:") ?? false)
        XCTAssertTrue(output?.contains("D2:") ?? false)
        XCTAssertTrue(output?.contains("drive1.atr") ?? false)
        XCTAssertTrue(output?.contains("drive2.atr") ?? false)

        // Switch between drives
        _ = await repl.execute("cd 2")
        var prompt = await repl.prompt
        XCTAssertTrue(prompt.contains("D2:"))

        _ = await repl.execute("cd 1")
        prompt = await repl.prompt
        XCTAssertTrue(prompt.contains("D1:"))
    }
}
