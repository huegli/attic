// =============================================================================
// StatePersistenceTests.swift - Unit Tests for State Persistence (Phase 16)
// =============================================================================
//
// Tests for the v2 state file format including:
// - StateMetadata encoding/decoding
// - StateFileHandler read/write operations
// - Round-trip verification
// - Error handling for malformed files
//
// =============================================================================

import XCTest
@testable import AtticCore

final class StatePersistenceTests: XCTestCase {

    // =========================================================================
    // MARK: - StateMetadata Tests
    // =========================================================================

    func testStateMetadataCreation() {
        // Create metadata with current timestamp
        let metadata = StateMetadata.create(
            replMode: .monitor,
            mountedDisks: []
        )

        // Verify timestamp is set (ISO 8601 format)
        XCTAssertFalse(metadata.timestamp.isEmpty)
        XCTAssertTrue(metadata.timestamp.contains("T"))  // ISO 8601 has T separator

        // Verify REPL mode
        XCTAssertEqual(metadata.replMode.mode, "monitor")
        XCTAssertNil(metadata.replMode.basicVariant)

        // Verify app version
        XCTAssertEqual(metadata.appVersion, "1.0.0")
    }

    func testStateMetadataWithBasicMode() {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .atari),
            mountedDisks: []
        )

        XCTAssertEqual(metadata.replMode.mode, "basic")
        XCTAssertEqual(metadata.replMode.basicVariant, "atari")
    }

    func testStateMetadataWithTurboBasic() {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .turbo),
            mountedDisks: []
        )

        XCTAssertEqual(metadata.replMode.mode, "basic")
        XCTAssertEqual(metadata.replMode.basicVariant, "turbo")
    }

    func testStateMetadataWithDosMode() {
        let metadata = StateMetadata.create(
            replMode: .dos,
            mountedDisks: []
        )

        XCTAssertEqual(metadata.replMode.mode, "dos")
        XCTAssertNil(metadata.replMode.basicVariant)
    }

    func testStateMetadataWithMountedDisks() {
        let disks = [
            MountedDiskReference(drive: 1, path: "/path/to/disk1.atr", diskType: "SS/SD", readOnly: false),
            MountedDiskReference(drive: 2, path: "/path/to/disk2.atr", diskType: "SS/ED", readOnly: true)
        ]

        let metadata = StateMetadata.create(
            replMode: .dos,
            mountedDisks: disks
        )

        XCTAssertEqual(metadata.mountedDisks.count, 2)
        XCTAssertEqual(metadata.mountedDisks[0].drive, 1)
        XCTAssertEqual(metadata.mountedDisks[0].path, "/path/to/disk1.atr")
        XCTAssertEqual(metadata.mountedDisks[0].diskType, "SS/SD")
        XCTAssertFalse(metadata.mountedDisks[0].readOnly)

        XCTAssertEqual(metadata.mountedDisks[1].drive, 2)
        XCTAssertTrue(metadata.mountedDisks[1].readOnly)
    }

    // =========================================================================
    // MARK: - REPLModeReference Conversion Tests
    // =========================================================================

    func testREPLModeReferenceRoundTrip() {
        // Monitor mode
        let monitorRef = REPLModeReference(from: .monitor)
        XCTAssertEqual(monitorRef.toREPLMode(), .monitor)

        // Atari BASIC mode
        let atariRef = REPLModeReference(from: .basic(variant: .atari))
        XCTAssertEqual(atariRef.toREPLMode(), .basic(variant: .atari))

        // Turbo BASIC mode
        let turboRef = REPLModeReference(from: .basic(variant: .turbo))
        XCTAssertEqual(turboRef.toREPLMode(), .basic(variant: .turbo))

        // DOS mode
        let dosRef = REPLModeReference(from: .dos)
        XCTAssertEqual(dosRef.toREPLMode(), .dos)
    }

    func testREPLModeReferenceUnknownMode() {
        // Unknown mode should default to BASIC
        let unknownRef = REPLModeReference(mode: "unknown", basicVariant: nil)
        XCTAssertEqual(unknownRef.toREPLMode(), .basic(variant: .atari))
    }

    // =========================================================================
    // MARK: - JSON Encoding/Decoding Tests
    // =========================================================================

    func testMetadataJSONRoundTrip() throws {
        let original = StateMetadata(
            timestamp: "2025-01-19T12:00:00.000Z",
            replMode: REPLModeReference(mode: "monitor", basicVariant: nil),
            mountedDisks: [
                MountedDiskReference(drive: 1, path: "/test.atr", diskType: "SS/SD", readOnly: false)
            ],
            note: "Test state",
            appVersion: "1.0.0"
        )

        // Encode
        let jsonData = try original.encode()
        XCTAssertFalse(jsonData.isEmpty)

        // Decode
        let decoded = try StateMetadata.decode(from: jsonData)

        // Verify
        XCTAssertEqual(decoded.timestamp, original.timestamp)
        XCTAssertEqual(decoded.replMode.mode, original.replMode.mode)
        XCTAssertEqual(decoded.mountedDisks.count, 1)
        XCTAssertEqual(decoded.mountedDisks[0].path, "/test.atr")
        XCTAssertEqual(decoded.note, "Test state")
        XCTAssertEqual(decoded.appVersion, "1.0.0")
    }

    func testMetadataJSONWithEmptyDisks() throws {
        let metadata = StateMetadata.create(
            replMode: .basic(variant: .atari),
            mountedDisks: []
        )

        let jsonData = try metadata.encode()
        let decoded = try StateMetadata.decode(from: jsonData)

        XCTAssertTrue(decoded.mountedDisks.isEmpty)
    }

    // =========================================================================
    // MARK: - StateFileHandler Tests
    // =========================================================================

    func testStateFileWriteAndRead() throws {
        // Create test metadata
        let metadata = StateMetadata(
            timestamp: "2025-01-19T12:00:00.000Z",
            replMode: REPLModeReference(from: .monitor),
            mountedDisks: [
                MountedDiskReference(drive: 1, path: "/disk.atr", diskType: "SS/SD", readOnly: false)
            ],
            note: nil,
            appVersion: "1.0.0"
        )

        // Create test emulator state
        var state = EmulatorState()
        state.tags.size = 1024
        state.tags.cpu = 100
        state.tags.pc = 200
        state.flags.frameCount = 12345
        state.data = [0x01, 0x02, 0x03, 0x04, 0x05]

        // Write to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_state_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try StateFileHandler.write(to: testURL, metadata: metadata, state: state)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: testURL.path))

        // Read back
        let (readMetadata, readState) = try StateFileHandler.read(from: testURL)

        // Verify metadata
        XCTAssertEqual(readMetadata.timestamp, metadata.timestamp)
        XCTAssertEqual(readMetadata.replMode.mode, "monitor")
        XCTAssertEqual(readMetadata.mountedDisks.count, 1)
        XCTAssertEqual(readMetadata.mountedDisks[0].path, "/disk.atr")

        // Verify state
        XCTAssertEqual(readState.tags.size, state.tags.size)
        XCTAssertEqual(readState.tags.cpu, state.tags.cpu)
        XCTAssertEqual(readState.tags.pc, state.tags.pc)
        XCTAssertEqual(readState.flags.frameCount, state.flags.frameCount)
        XCTAssertEqual(readState.data, state.data)
    }

    func testStateFileReadMetadataOnly() throws {
        // Create test file
        let metadata = StateMetadata.create(
            replMode: .dos,
            mountedDisks: []
        )

        var state = EmulatorState()
        state.data = Array(repeating: 0xAB, count: 1000)  // Larger data

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("test_metadata_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try StateFileHandler.write(to: testURL, metadata: metadata, state: state)

        // Read metadata only (faster)
        let readMetadata = try StateFileHandler.readMetadata(from: testURL)

        XCTAssertEqual(readMetadata.replMode.mode, "dos")
        XCTAssertFalse(readMetadata.timestamp.isEmpty)
    }

    // =========================================================================
    // MARK: - Error Handling Tests
    // =========================================================================

    func testInvalidMagicBytes() {
        // Create file with wrong magic but sufficient length (20+ bytes)
        var badData = Data([0x00, 0x00, 0x00, 0x00, 0x02])  // Wrong magic
        badData.append(contentsOf: Array(repeating: UInt8(0), count: 20))  // Padding to pass length check

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("bad_magic_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try! badData.write(to: testURL)

        XCTAssertThrowsError(try StateFileHandler.read(from: testURL)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError")
                return
            }
            if case .invalidMagic = stateError {
                // Expected
            } else {
                XCTFail("Expected invalidMagic error, got \(stateError)")
            }
        }
    }

    func testUnsupportedVersion() {
        // Create file with wrong version
        var badData = Data([0x41, 0x54, 0x54, 0x43])  // ATTC magic
        badData.append(0x99)  // Bad version
        badData.append(contentsOf: Array(repeating: UInt8(0), count: 20))  // Padding

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("bad_version_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try! badData.write(to: testURL)

        XCTAssertThrowsError(try StateFileHandler.read(from: testURL)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError")
                return
            }
            if case .unsupportedVersion(let version) = stateError {
                XCTAssertEqual(version, 0x99)
            } else {
                XCTFail("Expected unsupportedVersion error, got \(stateError)")
            }
        }
    }

    func testTruncatedFile() {
        // Create file that's too short
        let shortData = Data([0x41, 0x54, 0x54, 0x43, 0x02])  // Just header start

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("truncated_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try! shortData.write(to: testURL)

        XCTAssertThrowsError(try StateFileHandler.read(from: testURL)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError")
                return
            }
            if case .truncatedFile = stateError {
                // Expected
            } else {
                XCTFail("Expected truncatedFile error, got \(stateError)")
            }
        }
    }

    func testFileNotFound() {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/file.attic")

        XCTAssertThrowsError(try StateFileHandler.read(from: nonExistentURL)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError")
                return
            }
            if case .readFailed = stateError {
                // Expected
            } else {
                XCTFail("Expected readFailed error, got \(stateError)")
            }
        }
    }

    // =========================================================================
    // MARK: - File Format Validation Tests
    // =========================================================================

    func testFileHeaderStructure() throws {
        let metadata = StateMetadata.create(replMode: .monitor, mountedDisks: [])
        var state = EmulatorState()
        state.data = [0x00]

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("header_test_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try StateFileHandler.write(to: testURL, metadata: metadata, state: state)

        let fileData = try Data(contentsOf: testURL)

        // Verify header (16 bytes)
        XCTAssertTrue(fileData.count >= 16)

        // Magic bytes "ATTC"
        XCTAssertEqual(fileData[0], 0x41)  // A
        XCTAssertEqual(fileData[1], 0x54)  // T
        XCTAssertEqual(fileData[2], 0x54)  // T
        XCTAssertEqual(fileData[3], 0x43)  // C

        // Version
        XCTAssertEqual(fileData[4], StateFileConstants.version)

        // Flags (byte 5)
        // Reserved (bytes 6-15)
        for i in 6..<16 {
            XCTAssertEqual(fileData[i], 0x00)
        }
    }

    func testMetadataLengthEncoding() throws {
        let metadata = StateMetadata.create(replMode: .dos, mountedDisks: [])
        var state = EmulatorState()
        state.data = []

        let tempDir = FileManager.default.temporaryDirectory
        let testURL = tempDir.appendingPathComponent("length_test_\(UUID().uuidString).attic")

        defer {
            try? FileManager.default.removeItem(at: testURL)
        }

        try StateFileHandler.write(to: testURL, metadata: metadata, state: state)

        let fileData = try Data(contentsOf: testURL)

        // Read metadata length at offset 16 (4 bytes, little-endian)
        let lengthData = fileData.subdata(in: 16..<20)
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }

        // Verify it's reasonable (JSON metadata should be between 50-500 bytes typically)
        XCTAssertGreaterThan(length, 50)
        XCTAssertLessThan(length, 1000)

        // Verify we can read the JSON at offset 20
        let jsonData = fileData.subdata(in: 20..<(20 + Int(length)))
        XCTAssertNoThrow(try StateMetadata.decode(from: jsonData))
    }
}
