// =============================================================================
// StatePersistenceIntegrationTests.swift - Integration Tests for State Persistence
// =============================================================================
//
// This file provides integration test coverage for the state persistence system:
// 1. Save State (11.1) - File creation, size, flags, error handling
// 2. Load State (11.2) - Memory/metadata/mode restoration, error handling
// 3. State Integrity (11.3) - Modify-then-restore, multi-file, overwrite cycles
//
// These tests exercise the full StateFileHandler pipeline (write → read) with
// realistic emulator state data. They complement the unit tests in
// StatePersistenceTests.swift by testing cross-component workflows and edge cases.
//
// No emulator or server is needed — these tests work directly with
// StateFileHandler, StateMetadata, and EmulatorState structures.
//
// Running:
//   swift test --filter StatePersistenceIntegrationTests
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - 11.1 Save State Tests
// =============================================================================

/// Tests for state save operations, verifying file creation, size, flags,
/// metadata content, and error handling for invalid paths.
///
/// The save operation serializes an EmulatorState and StateMetadata into the
/// v2 binary format (.attic file). Key behaviors:
/// - File must contain the "ATTC" magic bytes and version 0x02
/// - Realistic state data (~210KB) produces files >200KB
/// - StateFileFlags (wasPaused, hasBasicProgram) are preserved
/// - Invalid paths produce StateFileError.writeFailed
final class StateSaveIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Create a unique temp directory for each test to avoid cross-contamination
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_save_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - File Creation
    // =========================================================================

    /// Saving state creates a file on disk.
    func test_save_createsFile() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00, 0x01, 0x02]

        let url = tempDir.appendingPathComponent("test.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Saving realistic ~210KB state produces a file larger than 200KB.
    ///
    /// The Atari 800 XL has ~64KB of RAM plus chip state; libatari800 serializes
    /// roughly 210KB of state data. This test verifies the file format doesn't
    /// introduce excessive overhead or truncation.
    func test_save_realisticSize_exceeds200KB() throws {
        let metadata = StateMetadata.create(replMode: .basic(variant: .atari), mountedDisks: [])
        var state = EmulatorState()
        state.tags.size = 210_000
        // Fill with a recognizable pattern (repeating 0x00–0xFF)
        state.data = (0..<210_000).map { UInt8($0 & 0xFF) }

        let url = tempDir.appendingPathComponent("large.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs[.size] as! UInt64

        // File must be >200KB (state data alone is 210KB, plus headers/metadata)
        XCTAssertGreaterThan(fileSize, 200_000, "State file should be >200KB for realistic state")
    }

    /// Saved file starts with "ATTC" magic bytes and version 0x02.
    func test_save_containsMagicAndVersion() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0xAB]

        let url = tempDir.appendingPathComponent("magic.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let fileData = try Data(contentsOf: url)
        XCTAssertEqual(Array(fileData.prefix(4)), [0x41, 0x54, 0x54, 0x43])  // "ATTC"
        XCTAssertEqual(fileData[4], 0x02)  // Version 2
    }

    // =========================================================================
    // MARK: - State File Flags
    // =========================================================================

    /// The wasPaused flag is written to the file header at byte offset 5.
    func test_save_wasPausedFlag_storedInHeader() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("paused.attic")
        try StateFileHandler.write(
            to: url, metadata: metadata, state: state, flags: .wasPaused
        )

        let fileData = try Data(contentsOf: url)
        let flagsByte = fileData[5]
        XCTAssertTrue(StateFileFlags(rawValue: flagsByte).contains(.wasPaused))
    }

    /// The hasBasicProgram flag is preserved in the header.
    func test_save_hasBasicProgramFlag_storedInHeader() throws {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .atari), mountedDisks: []
        )
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("basic.attic")
        try StateFileHandler.write(
            to: url, metadata: metadata, state: state, flags: .hasBasicProgram
        )

        let fileData = try Data(contentsOf: url)
        let flagsByte = fileData[5]
        XCTAssertTrue(StateFileFlags(rawValue: flagsByte).contains(.hasBasicProgram))
    }

    /// Multiple flags can be combined.
    func test_save_combinedFlags_storedInHeader() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("combined.attic")
        let flags: StateFileFlags = [.wasPaused, .hasBasicProgram]
        try StateFileHandler.write(to: url, metadata: metadata, state: state, flags: flags)

        let fileData = try Data(contentsOf: url)
        let flagsByte = fileData[5]
        let storedFlags = StateFileFlags(rawValue: flagsByte)
        XCTAssertTrue(storedFlags.contains(.wasPaused))
        XCTAssertTrue(storedFlags.contains(.hasBasicProgram))
    }

    // =========================================================================
    // MARK: - Metadata Preservation
    // =========================================================================

    /// Mounted disk references are preserved in the saved file.
    func test_save_mountedDisks_preservedInMetadata() throws {
        let disks = [
            MountedDiskReference(
                drive: 1, path: "/games/starraiders.atr",
                diskType: "SS/SD", readOnly: false
            ),
            MountedDiskReference(
                drive: 2, path: "/utils/dos25.atr",
                diskType: "SS/ED", readOnly: true
            )
        ]
        let metadata = StateMetadata.create(replMode: .dos, mountedDisks: disks)
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("disks.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        // Read back and verify
        let loaded = try StateFileHandler.readMetadata(from: url)
        XCTAssertEqual(loaded.mountedDisks.count, 2)
        XCTAssertEqual(loaded.mountedDisks[0].drive, 1)
        XCTAssertEqual(loaded.mountedDisks[0].path, "/games/starraiders.atr")
        XCTAssertEqual(loaded.mountedDisks[0].diskType, "SS/SD")
        XCTAssertFalse(loaded.mountedDisks[0].readOnly)
        XCTAssertEqual(loaded.mountedDisks[1].drive, 2)
        XCTAssertTrue(loaded.mountedDisks[1].readOnly)
    }

    /// Optional note is preserved in metadata.
    func test_save_note_preservedInMetadata() throws {
        let metadata = StateMetadata(
            timestamp: "2025-06-15T10:30:00.000Z",
            replMode: REPLModeReference(from: .monitor),
            mountedDisks: [],
            note: "Before boss fight",
            appVersion: "1.0.0"
        )
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("noted.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let loaded = try StateFileHandler.readMetadata(from: url)
        XCTAssertEqual(loaded.note, "Before boss fight")
    }

    /// Timestamp is preserved exactly in the saved file.
    func test_save_timestamp_preservedExactly() throws {
        let metadata = StateMetadata(
            timestamp: "2025-12-31T23:59:59.999Z",
            replMode: REPLModeReference(from: .monitor),
            mountedDisks: [],
            appVersion: "1.0.0"
        )
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("timestamp.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let loaded = try StateFileHandler.readMetadata(from: url)
        XCTAssertEqual(loaded.timestamp, "2025-12-31T23:59:59.999Z")
    }

    // =========================================================================
    // MARK: - Error Handling
    // =========================================================================

    /// Saving to a non-existent directory throws writeFailed.
    func test_save_invalidPath_throwsWriteFailed() {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let badURL = URL(fileURLWithPath: "/nonexistent/directory/state.attic")

        XCTAssertThrowsError(
            try StateFileHandler.write(to: badURL, metadata: metadata, state: state)
        ) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .writeFailed = stateError {
                // Expected — directory doesn't exist
            } else {
                XCTFail("Expected writeFailed, got \(stateError)")
            }
        }
    }

    /// Saving to a read-only location throws writeFailed.
    func test_save_readOnlyPath_throwsWriteFailed() throws {
        // Create a read-only directory
        let readOnlyDir = tempDir.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readOnlyDir, withIntermediateDirectories: true)

        // Set directory to read-only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: readOnlyDir.path
        )

        defer {
            // Restore write permission so tearDown can delete it
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: readOnlyDir.path
            )
        }

        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let url = readOnlyDir.appendingPathComponent("state.attic")

        XCTAssertThrowsError(
            try StateFileHandler.write(to: url, metadata: metadata, state: state)
        ) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .writeFailed = stateError {
                // Expected — read-only directory
            } else {
                XCTFail("Expected writeFailed, got \(stateError)")
            }
        }
    }

    /// Saving with empty state data still creates a valid file.
    func test_save_emptyStateData_createsValidFile() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = []

        let url = tempDir.appendingPathComponent("empty.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        // Should be readable
        let (loaded, loadedState) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.replMode.mode, "monitor")
        XCTAssertTrue(loadedState.data.isEmpty)
    }
}

// =============================================================================
// MARK: - 11.2 Load State Tests
// =============================================================================

/// Tests for state load operations, verifying memory restoration, REPL mode
/// restoration, metadata extraction, and error handling for invalid files.
///
/// Loading deserializes an .attic file back into EmulatorState and
/// StateMetadata. The tests verify that all components of the saved state
/// are faithfully restored, and that corrupted/invalid files produce
/// appropriate errors.
final class StateLoadIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_load_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Memory/State Data Restoration
    // =========================================================================

    /// Loading restores the exact state data byte-for-byte.
    func test_load_restoresStateData_byteForByte() throws {
        // Create a recognizable data pattern (not just zeros)
        let originalData: [UInt8] = (0..<1024).map { UInt8($0 & 0xFF) }

        var state = EmulatorState()
        state.data = originalData
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("data.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)

        // Byte-for-byte comparison
        XCTAssertEqual(loaded.data.count, originalData.count)
        XCTAssertEqual(loaded.data, originalData)
    }

    /// Loading restores state tags (section offsets) accurately.
    func test_load_restoresStateTags() throws {
        var state = EmulatorState()
        state.tags.size = 210_000
        state.tags.cpu = 0x0100
        state.tags.pc = 0x0600
        state.tags.baseRam = 0x1000
        state.tags.antic = 0x2000
        state.tags.gtia = 0x3000
        state.tags.pia = 0x4000
        state.tags.pokey = 0x5000
        state.data = [0x00]
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("tags.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)

        XCTAssertEqual(loaded.tags.size, 210_000)
        XCTAssertEqual(loaded.tags.cpu, 0x0100)
        XCTAssertEqual(loaded.tags.pc, 0x0600)
        XCTAssertEqual(loaded.tags.baseRam, 0x1000)
        XCTAssertEqual(loaded.tags.antic, 0x2000)
        XCTAssertEqual(loaded.tags.gtia, 0x3000)
        XCTAssertEqual(loaded.tags.pia, 0x4000)
        XCTAssertEqual(loaded.tags.pokey, 0x5000)
    }

    /// Loading restores state flags (frameCount, selfTestEnabled).
    func test_load_restoresStateFlags() throws {
        var state = EmulatorState()
        state.flags.frameCount = 123456
        state.flags.selfTestEnabled = true
        state.data = [0x00]
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("flags.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)

        XCTAssertEqual(loaded.flags.frameCount, 123456)
        XCTAssertTrue(loaded.flags.selfTestEnabled)
    }

    /// Loading a large (~210KB) state restores all data correctly.
    func test_load_largeState_restoresCompletely() throws {
        var state = EmulatorState()
        state.tags.size = 210_000
        state.data = (0..<210_000).map { UInt8($0 & 0xFF) }
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("large.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)

        XCTAssertEqual(loaded.data.count, 210_000)
        // Spot-check the repeating pattern at known offsets
        XCTAssertEqual(loaded.data[0], 0x00)
        XCTAssertEqual(loaded.data[127], 0x7F)
        XCTAssertEqual(loaded.data[255], 0xFF)
        XCTAssertEqual(loaded.data[256], 0x00)  // Pattern wraps
        XCTAssertEqual(loaded.data[209_999], UInt8(209_999 & 0xFF))
    }

    // =========================================================================
    // MARK: - REPL Mode Restoration
    // =========================================================================

    /// Loading restores monitor mode.
    func test_load_restoresMonitorMode() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("monitor.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (loaded, _) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.replMode.toREPLMode(), .monitor)
    }

    /// Loading restores Atari BASIC mode.
    func test_load_restoresAtariBasicMode() throws {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .atari), mountedDisks: []
        )
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("atari_basic.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (loaded, _) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.replMode.toREPLMode(), .basic(variant: .atari))
    }

    /// Loading restores Turbo BASIC mode.
    func test_load_restoresTurboBasicMode() throws {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .turbo), mountedDisks: []
        )
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("turbo_basic.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (loaded, _) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.replMode.toREPLMode(), .basic(variant: .turbo))
    }

    /// Loading restores DOS mode.
    func test_load_restoresDOSMode() throws {
        let metadata = StateMetadata.create(replMode: .dos, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let url = tempDir.appendingPathComponent("dos.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (loaded, _) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.replMode.toREPLMode(), .dos)
    }

    /// All four REPL modes round-trip correctly.
    func test_load_allModes_roundTrip() throws {
        let modes: [REPLMode] = [
            .monitor,
            .basic(variant: .atari),
            .basic(variant: .turbo),
            .dos
        ]

        for mode in modes {
            let metadata = StateMetadata.create(replMode: mode, mountedDisks: [])
            var state = EmulatorState()
            state.data = [0x00]

            let url = tempDir.appendingPathComponent("mode_\(mode.name).attic")
            try StateFileHandler.write(to: url, metadata: metadata, state: state)

            let (loaded, _) = try StateFileHandler.read(from: url)
            XCTAssertEqual(
                loaded.replMode.toREPLMode(), mode,
                "Mode \(mode.name) should round-trip correctly"
            )
        }
    }

    // =========================================================================
    // MARK: - Metadata-Only Read
    // =========================================================================

    /// Metadata-only read extracts metadata without parsing state data.
    func test_load_metadataOnly_skipsStateData() throws {
        let metadata = StateMetadata(
            timestamp: "2025-06-15T12:00:00.000Z",
            replMode: REPLModeReference(from: .dos),
            mountedDisks: [
                MountedDiskReference(
                    drive: 1, path: "/test.atr", diskType: "SS/SD", readOnly: false
                )
            ],
            note: "Quick save",
            appVersion: "1.0.0"
        )
        var state = EmulatorState()
        state.data = Array(repeating: 0xFF, count: 100_000)

        let url = tempDir.appendingPathComponent("metadata_only.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        // Read metadata only — should succeed without parsing 100KB of state
        let loaded = try StateFileHandler.readMetadata(from: url)
        XCTAssertEqual(loaded.timestamp, "2025-06-15T12:00:00.000Z")
        XCTAssertEqual(loaded.replMode.mode, "dos")
        XCTAssertEqual(loaded.mountedDisks.count, 1)
        XCTAssertEqual(loaded.note, "Quick save")
    }

    // =========================================================================
    // MARK: - Error Handling: Invalid Files
    // =========================================================================

    /// Loading a file that doesn't exist throws readFailed.
    func test_load_nonExistentFile_throwsReadFailed() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).attic")

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .readFailed = stateError {
                // Expected
            } else {
                XCTFail("Expected readFailed, got \(stateError)")
            }
        }
    }

    /// Loading a random binary file (not .attic format) throws invalidMagic.
    func test_load_randomBinaryFile_throwsInvalidMagic() throws {
        // Write random data that isn't an attic file
        let randomData = Data((0..<100).map { _ in UInt8.random(in: 0...254) })
        let url = tempDir.appendingPathComponent("random.bin")
        try randomData.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            // Could be invalidMagic or truncatedFile depending on data
            switch stateError {
            case .invalidMagic, .truncatedFile:
                break  // Both are acceptable for random data
            default:
                XCTFail("Expected invalidMagic or truncatedFile, got \(stateError)")
            }
        }
    }

    /// Loading a file with correct magic but wrong version throws unsupportedVersion.
    func test_load_wrongFormatVersion_throwsUnsupportedVersion() throws {
        // Hand-craft a file with correct magic but version 0x99
        var data = Data(StateFileConstants.magic)
        data.append(0x99)  // Bad version
        data.append(0x00)  // Flags
        data.append(contentsOf: [UInt8](repeating: 0, count: 10))  // Reserved
        data.append(contentsOf: [UInt8](repeating: 0, count: 4))   // Metadata length

        let url = tempDir.appendingPathComponent("bad_version.attic")
        try data.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .unsupportedVersion(let version) = stateError {
                XCTAssertEqual(version, 0x99)
            } else {
                XCTFail("Expected unsupportedVersion, got \(stateError)")
            }
        }
    }

    /// Loading a truncated file (just the header, no metadata) throws truncatedFile.
    func test_load_truncatedFile_throwsTruncatedFile() throws {
        // Write just the 16-byte header with a metadata length that exceeds file size
        var data = Data(StateFileConstants.magic)
        data.append(StateFileConstants.version)
        data.append(0x00)  // Flags
        data.append(contentsOf: [UInt8](repeating: 0, count: 10))  // Reserved

        // Metadata length = 9999 but file ends here
        var length: UInt32 = 9999
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }

        let url = tempDir.appendingPathComponent("truncated.attic")
        try data.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .truncatedFile = stateError {
                // Expected
            } else {
                XCTFail("Expected truncatedFile, got \(stateError)")
            }
        }
    }

    /// Loading a file with corrupted metadata JSON throws invalidMetadata.
    func test_load_corruptedMetadata_throwsInvalidMetadata() throws {
        // Build a file with valid header but garbage JSON
        var data = Data(StateFileConstants.magic)
        data.append(StateFileConstants.version)
        data.append(0x00)  // Flags
        data.append(contentsOf: [UInt8](repeating: 0, count: 10))  // Reserved

        // Write garbage "JSON"
        let garbageJSON = Data("this is not json{{{".utf8)
        var length = UInt32(garbageJSON.count)
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(garbageJSON)

        // Add enough bytes for tags and flags so we don't get truncatedFile
        data.append(contentsOf: [UInt8](repeating: 0, count: 40))

        let url = tempDir.appendingPathComponent("bad_json.attic")
        try data.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .invalidMetadata = stateError {
                // Expected
            } else {
                XCTFail("Expected invalidMetadata, got \(stateError)")
            }
        }
    }

    /// Loading a zero-byte file throws truncatedFile.
    func test_load_emptyFile_throwsTruncatedFile() throws {
        let url = tempDir.appendingPathComponent("empty.attic")
        try Data().write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            if case .truncatedFile = stateError {
                // Expected
            } else {
                XCTFail("Expected truncatedFile, got \(stateError)")
            }
        }
    }

    /// Loading a text file (e.g., .bas source) throws invalidMagic.
    func test_load_textFile_throwsInvalidMagic() throws {
        let textData = Data("10 PRINT \"HELLO\"\n20 GOTO 10\n".utf8)
        let url = tempDir.appendingPathComponent("program.attic")
        try textData.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(error)")
                return
            }
            // "10 P" != "ATTC", so this should be invalidMagic
            if case .invalidMagic = stateError {
                // Expected
            } else {
                XCTFail("Expected invalidMagic, got \(stateError)")
            }
        }
    }
}

// =============================================================================
// MARK: - 11.3 State Integrity Tests
// =============================================================================

/// Tests for state data integrity across save/load cycles, including
/// modify-then-restore workflows, multi-file operations, and repeated cycles.
///
/// These tests verify the critical property: saving state, changing the
/// emulator, then loading restores the exact original state. This is
/// essential for save-state functionality in games and debugging.
final class StateIntegrityIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_integrity_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - Save → Modify → Load Restores Original
    // =========================================================================

    /// Save state, modify the state data, load — the original is restored.
    ///
    /// This simulates the core use case: saving mid-game, continuing to play
    /// (state changes), then loading to return to the saved point.
    func test_saveModifyLoad_restoresOriginal() throws {
        // Create original state with a distinctive pattern
        var originalState = EmulatorState()
        originalState.tags.size = 1024
        originalState.tags.cpu = 0xABCD
        originalState.tags.pc = 0x0600
        originalState.flags.frameCount = 50000
        originalState.data = (0..<1024).map { UInt8($0 & 0xFF) }

        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        let url = tempDir.appendingPathComponent("checkpoint.attic")

        // Save the original state
        try StateFileHandler.write(to: url, metadata: metadata, state: originalState)

        // "Modify" the state (simulating continued emulation)
        var modifiedState = originalState
        modifiedState.tags.pc = 0x9999
        modifiedState.flags.frameCount = 99999
        modifiedState.data = Array(repeating: 0xDE, count: 1024)

        // Verify the modification actually changed things
        XCTAssertNotEqual(modifiedState.data, originalState.data)
        XCTAssertNotEqual(modifiedState.tags.pc, originalState.tags.pc)

        // Load the saved state
        let (_, restoredState) = try StateFileHandler.read(from: url)

        // The restored state should match the original, not the modified
        XCTAssertEqual(restoredState.data, originalState.data)
        XCTAssertEqual(restoredState.tags.pc, originalState.tags.pc)
        XCTAssertEqual(restoredState.tags.cpu, originalState.tags.cpu)
        XCTAssertEqual(restoredState.flags.frameCount, originalState.flags.frameCount)
    }

    /// Save state with realistic 210KB data, modify all of it, load restores original.
    func test_saveModifyLoad_largeState_restoresOriginal() throws {
        var originalState = EmulatorState()
        originalState.tags.size = 210_000
        originalState.data = (0..<210_000).map { UInt8($0 & 0xFF) }
        originalState.flags.frameCount = 77777

        let metadata = StateMetadata.create(
            replMode: .basic(variant: .atari), mountedDisks: []
        )
        let url = tempDir.appendingPathComponent("large_checkpoint.attic")

        try StateFileHandler.write(to: url, metadata: metadata, state: originalState)

        // Completely overwrite the state data (simulating continued play)
        var modifiedState = originalState
        modifiedState.data = Array(repeating: 0x00, count: 210_000)
        modifiedState.flags.frameCount = 0

        // Load
        let (_, restored) = try StateFileHandler.read(from: url)

        XCTAssertEqual(restored.data.count, 210_000)
        XCTAssertEqual(restored.data, originalState.data)
        XCTAssertEqual(restored.flags.frameCount, 77777)
    }

    // =========================================================================
    // MARK: - Multiple Save/Load Cycles
    // =========================================================================

    /// Five save/load cycles with changing data — each load returns the last save.
    func test_multipleCycles_eachLoadMatchesLastSave() throws {
        let url = tempDir.appendingPathComponent("cycles.attic")

        for cycle in 0..<5 {
            // Create unique state for this cycle
            var state = EmulatorState()
            state.tags.size = UInt32(cycle * 1000)
            state.tags.pc = UInt32(0x0600 + cycle)
            state.flags.frameCount = UInt32(cycle * 10000)
            state.data = Array(repeating: UInt8(cycle * 50), count: 500)

            let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

            // Save
            try StateFileHandler.write(to: url, metadata: metadata, state: state)

            // Load immediately and verify
            let (_, loaded) = try StateFileHandler.read(from: url)

            XCTAssertEqual(loaded.tags.size, UInt32(cycle * 1000),
                           "Cycle \(cycle): tags.size mismatch")
            XCTAssertEqual(loaded.tags.pc, UInt32(0x0600 + cycle),
                           "Cycle \(cycle): tags.pc mismatch")
            XCTAssertEqual(loaded.flags.frameCount, UInt32(cycle * 10000),
                           "Cycle \(cycle): frameCount mismatch")
            XCTAssertTrue(loaded.data.allSatisfy { $0 == UInt8(cycle * 50) },
                          "Cycle \(cycle): data pattern mismatch")
        }
    }

    /// Save/load with different REPL modes each cycle.
    func test_multipleCycles_differentModes() throws {
        let modes: [REPLMode] = [
            .monitor,
            .basic(variant: .atari),
            .basic(variant: .turbo),
            .dos,
            .monitor  // Back to start
        ]

        let url = tempDir.appendingPathComponent("mode_cycles.attic")

        for (i, mode) in modes.enumerated() {
            var state = EmulatorState()
            state.data = [UInt8(i)]
            let metadata = StateMetadata.create(replMode: mode, mountedDisks: [])

            try StateFileHandler.write(to: url, metadata: metadata, state: state)
            let (loaded, loadedState) = try StateFileHandler.read(from: url)

            XCTAssertEqual(loaded.replMode.toREPLMode(), mode,
                           "Cycle \(i): mode should be \(mode.name)")
            XCTAssertEqual(loadedState.data, [UInt8(i)],
                           "Cycle \(i): data should match")
        }
    }

    // =========================================================================
    // MARK: - Multi-File Independence
    // =========================================================================

    /// Saving to different files produces independent snapshots.
    func test_multiFile_savesAreIndependent() throws {
        let url1 = tempDir.appendingPathComponent("save1.attic")
        let url2 = tempDir.appendingPathComponent("save2.attic")
        let url3 = tempDir.appendingPathComponent("save3.attic")

        // Save three different states to three files
        for (url, value) in [(url1, UInt8(0xAA)), (url2, UInt8(0xBB)), (url3, UInt8(0xCC))] {
            var state = EmulatorState()
            state.data = Array(repeating: value, count: 100)
            state.flags.frameCount = UInt32(value) * 100
            let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
            try StateFileHandler.write(to: url, metadata: metadata, state: state)
        }

        // Load each and verify they are independent
        let (_, s1) = try StateFileHandler.read(from: url1)
        let (_, s2) = try StateFileHandler.read(from: url2)
        let (_, s3) = try StateFileHandler.read(from: url3)

        XCTAssertTrue(s1.data.allSatisfy { $0 == 0xAA })
        XCTAssertTrue(s2.data.allSatisfy { $0 == 0xBB })
        XCTAssertTrue(s3.data.allSatisfy { $0 == 0xCC })

        XCTAssertEqual(s1.flags.frameCount, 0xAA * 100)
        XCTAssertEqual(s2.flags.frameCount, 0xBB * 100)
        XCTAssertEqual(s3.flags.frameCount, 0xCC * 100)
    }

    /// Loading file A after saving file B still returns file A's original data.
    func test_multiFile_loadOlderSave_unaffectedByNewerSave() throws {
        let urlA = tempDir.appendingPathComponent("saveA.attic")
        let urlB = tempDir.appendingPathComponent("saveB.attic")

        // Save state A
        var stateA = EmulatorState()
        stateA.data = Array(repeating: 0x11, count: 200)
        stateA.flags.frameCount = 1111
        let metaA = StateMetadata.create(replMode: .basic(variant: .atari), mountedDisks: [])
        try StateFileHandler.write(to: urlA, metadata: metaA, state: stateA)

        // Save state B (different data)
        var stateB = EmulatorState()
        stateB.data = Array(repeating: 0x22, count: 300)
        stateB.flags.frameCount = 2222
        let metaB = StateMetadata.create(replMode: .dos, mountedDisks: [])
        try StateFileHandler.write(to: urlB, metadata: metaB, state: stateB)

        // Load state A — should still be intact
        let (loadedMetaA, loadedA) = try StateFileHandler.read(from: urlA)
        XCTAssertEqual(loadedA.data.count, 200)
        XCTAssertTrue(loadedA.data.allSatisfy { $0 == 0x11 })
        XCTAssertEqual(loadedA.flags.frameCount, 1111)
        XCTAssertEqual(loadedMetaA.replMode.toREPLMode(), .basic(variant: .atari))

        // Load state B — should also be intact
        let (loadedMetaB, loadedB) = try StateFileHandler.read(from: urlB)
        XCTAssertEqual(loadedB.data.count, 300)
        XCTAssertTrue(loadedB.data.allSatisfy { $0 == 0x22 })
        XCTAssertEqual(loadedB.flags.frameCount, 2222)
        XCTAssertEqual(loadedMetaB.replMode.toREPLMode(), .dos)
    }

    // =========================================================================
    // MARK: - Overwrite Behavior
    // =========================================================================

    /// Saving to the same file overwrites previous contents completely.
    func test_overwrite_replacesOldState() throws {
        let url = tempDir.appendingPathComponent("overwrite.attic")

        // First save: 500 bytes of 0xAA
        var state1 = EmulatorState()
        state1.data = Array(repeating: 0xAA, count: 500)
        state1.flags.frameCount = 1000
        let meta1 = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        try StateFileHandler.write(to: url, metadata: meta1, state: state1)

        // Second save: 300 bytes of 0xBB (smaller!)
        var state2 = EmulatorState()
        state2.data = Array(repeating: 0xBB, count: 300)
        state2.flags.frameCount = 2000
        let meta2 = StateMetadata.create(replMode: .dos, mountedDisks: [])
        try StateFileHandler.write(to: url, metadata: meta2, state: state2)

        // Load should return the second save, not a mix of both
        let (loadedMeta, loaded) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.data.count, 300)
        XCTAssertTrue(loaded.data.allSatisfy { $0 == 0xBB })
        XCTAssertEqual(loaded.flags.frameCount, 2000)
        XCTAssertEqual(loadedMeta.replMode.toREPLMode(), .dos)
    }

    /// Overwriting with larger state than original produces correct file.
    func test_overwrite_largerState_replacesCompletely() throws {
        let url = tempDir.appendingPathComponent("grow.attic")

        // First save: small state
        var state1 = EmulatorState()
        state1.data = [0x01, 0x02, 0x03]
        let meta1 = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        try StateFileHandler.write(to: url, metadata: meta1, state: state1)

        // Second save: much larger state
        var state2 = EmulatorState()
        state2.data = Array(repeating: 0xFF, count: 10_000)
        let meta2 = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        try StateFileHandler.write(to: url, metadata: meta2, state: state2)

        let (_, loaded) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.data.count, 10_000)
        XCTAssertTrue(loaded.data.allSatisfy { $0 == 0xFF })
    }

    // =========================================================================
    // MARK: - Tag Integrity
    // =========================================================================

    /// All 8 tag fields survive save/load with maximum UInt32 values.
    func test_tagIntegrity_maxValues() throws {
        var state = EmulatorState()
        state.tags.size = UInt32.max
        state.tags.cpu = UInt32.max
        state.tags.pc = UInt32.max
        state.tags.baseRam = UInt32.max
        state.tags.antic = UInt32.max
        state.tags.gtia = UInt32.max
        state.tags.pia = UInt32.max
        state.tags.pokey = UInt32.max
        state.data = [0x00]
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("max_tags.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.tags.size, UInt32.max)
        XCTAssertEqual(loaded.tags.cpu, UInt32.max)
        XCTAssertEqual(loaded.tags.pc, UInt32.max)
        XCTAssertEqual(loaded.tags.baseRam, UInt32.max)
        XCTAssertEqual(loaded.tags.antic, UInt32.max)
        XCTAssertEqual(loaded.tags.gtia, UInt32.max)
        XCTAssertEqual(loaded.tags.pia, UInt32.max)
        XCTAssertEqual(loaded.tags.pokey, UInt32.max)
    }

    /// Tags with zero values survive save/load.
    func test_tagIntegrity_zeroValues() throws {
        var state = EmulatorState()
        // All tags default to 0
        state.data = [0x00]
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("zero_tags.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.tags.size, 0)
        XCTAssertEqual(loaded.tags.cpu, 0)
        XCTAssertEqual(loaded.tags.pc, 0)
        XCTAssertEqual(loaded.tags.baseRam, 0)
        XCTAssertEqual(loaded.tags.antic, 0)
        XCTAssertEqual(loaded.tags.gtia, 0)
        XCTAssertEqual(loaded.tags.pia, 0)
        XCTAssertEqual(loaded.tags.pokey, 0)
    }

    /// Each tag field is independently stored (no field bleeding).
    func test_tagIntegrity_fieldsAreIndependent() throws {
        var state = EmulatorState()
        // Set each field to a unique value
        state.tags.size = 0x11111111
        state.tags.cpu = 0x22222222
        state.tags.pc = 0x33333333
        state.tags.baseRam = 0x44444444
        state.tags.antic = 0x55555555
        state.tags.gtia = 0x66666666
        state.tags.pia = 0x77777777
        state.tags.pokey = 0x88888888
        state.data = [0x00]
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])

        let url = tempDir.appendingPathComponent("distinct_tags.attic")
        try StateFileHandler.write(to: url, metadata: metadata, state: state)

        let (_, loaded) = try StateFileHandler.read(from: url)
        XCTAssertEqual(loaded.tags.size, 0x11111111)
        XCTAssertEqual(loaded.tags.cpu, 0x22222222)
        XCTAssertEqual(loaded.tags.pc, 0x33333333)
        XCTAssertEqual(loaded.tags.baseRam, 0x44444444)
        XCTAssertEqual(loaded.tags.antic, 0x55555555)
        XCTAssertEqual(loaded.tags.gtia, 0x66666666)
        XCTAssertEqual(loaded.tags.pia, 0x77777777)
        XCTAssertEqual(loaded.tags.pokey, 0x88888888)
    }
}

// =============================================================================
// MARK: - .state Command Parsing Tests
// =============================================================================

/// Tests for `.state save` and `.state load` command parsing through
/// CommandParser.
///
/// The `.state` command is a global dot-command available in all REPL modes.
/// It has two subcommands: `save` and `load`, each requiring a file path.
final class StateCommandParsingTests: XCTestCase {
    let parser = CommandParser()

    // =========================================================================
    // MARK: - .state save Parsing
    // =========================================================================

    /// `.state save /tmp/test.attic` parses to saveState command.
    func test_stateSave_validPath() throws {
        let cmd = try parser.parse(".state save /tmp/test.attic", mode: .monitor)
        guard case .saveState(let path) = cmd else {
            XCTFail("Expected saveState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/test.attic")
    }

    /// `.state save` expands tilde in home-relative paths.
    func test_stateSave_homeRelativePath() throws {
        let cmd = try parser.parse(".state save ~/saves/game.attic", mode: .monitor)
        guard case .saveState(let path) = cmd else {
            XCTFail("Expected saveState, got \(cmd)")
            return
        }
        // Tilde should be expanded to the user's home directory
        let expected = NSString(string: "~/saves/game.attic").expandingTildeInPath
        XCTAssertEqual(path, expected)
    }

    /// `.state save` works in BASIC mode.
    func test_stateSave_worksInBasicMode() throws {
        let cmd = try parser.parse(
            ".state save /tmp/test.attic", mode: .basic(variant: .atari)
        )
        guard case .saveState(let path) = cmd else {
            XCTFail("Expected saveState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/test.attic")
    }

    /// `.state save` works in DOS mode.
    func test_stateSave_worksInDOSMode() throws {
        let cmd = try parser.parse(".state save /tmp/test.attic", mode: .dos)
        guard case .saveState(let path) = cmd else {
            XCTFail("Expected saveState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/test.attic")
    }

    /// `.state save` path with spaces is preserved.
    func test_stateSave_pathWithSpaces() throws {
        let cmd = try parser.parse(
            ".state save /tmp/my saves/test game.attic", mode: .monitor
        )
        guard case .saveState(let path) = cmd else {
            XCTFail("Expected saveState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/my saves/test game.attic")
    }

    // =========================================================================
    // MARK: - .state load Parsing
    // =========================================================================

    /// `.state load /tmp/test.attic` parses to loadState command.
    func test_stateLoad_validPath() throws {
        let cmd = try parser.parse(".state load /tmp/test.attic", mode: .monitor)
        guard case .loadState(let path) = cmd else {
            XCTFail("Expected loadState, got \(cmd)")
            return
        }
        XCTAssertEqual(path, "/tmp/test.attic")
    }

    /// `.state load` works in all modes.
    func test_stateLoad_worksInAllModes() throws {
        let modes: [REPLMode] = [
            .monitor, .basic(variant: .atari), .basic(variant: .turbo), .dos
        ]
        for mode in modes {
            let cmd = try parser.parse(".state load /tmp/test.attic", mode: mode)
            guard case .loadState = cmd else {
                XCTFail("Expected loadState in \(mode.name), got \(cmd)")
                return
            }
        }
    }

    // =========================================================================
    // MARK: - .state Error Cases
    // =========================================================================

    /// `.state` with no subcommand throws invalidCommand.
    func test_state_noSubcommand_throws() {
        XCTAssertThrowsError(try parser.parse(".state", mode: .monitor))
    }

    /// `.state save` with no path throws invalidCommand.
    func test_stateSave_noPath_throws() {
        XCTAssertThrowsError(try parser.parse(".state save", mode: .monitor))
    }

    /// `.state load` with no path throws invalidCommand.
    func test_stateLoad_noPath_throws() {
        XCTAssertThrowsError(try parser.parse(".state load", mode: .monitor))
    }

    /// `.state foo` (unknown subcommand) throws invalidCommand.
    func test_state_unknownSubcommand_throws() {
        XCTAssertThrowsError(try parser.parse(".state foo /path", mode: .monitor))
    }

    /// `.state delete` (non-existent subcommand) throws invalidCommand.
    func test_state_deleteSubcommand_throws() {
        XCTAssertThrowsError(try parser.parse(".state delete /path", mode: .monitor))
    }
}
