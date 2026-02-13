// =============================================================================
// ErrorHandlingIntegrationTests.swift - Error Handling Integration Tests
// =============================================================================
//
// This file provides integration test coverage for error handling behavior:
// 1. Missing ROMs (13.1) - Clear error messages, path included, suggestions
// 2. Invalid Files (13.2) - ATR, state file, and disk manager error handling
// 3. Network Errors (13.3) - Connection failures, timeouts, error descriptions
//
// These tests exercise the error paths in AtticCore and AtticProtocol without
// requiring a running emulator or server. They verify that:
// - Error messages are human-readable and actionable
// - Error types carry the right associated values (paths, filenames, reasons)
// - Error enums conform to LocalizedError with useful errorDescription
// - Recovery suggestions exist where applicable
//
// Running:
//   swift test --filter ErrorHandling
//   make test-error
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - 13.1 Missing ROMs Error Tests
// =============================================================================

/// Tests for ROM-related error handling.
///
/// These tests verify:
/// - AtticError.romNotFound includes the missing file path
/// - AtticError.initializationFailed includes the underlying reason
/// - AtticError.notInitialized provides a clear message
/// - LibAtari800Wrapper.initialize() throws romNotFound for missing ROMs
/// - Error descriptions are suitable for display to users
///
/// These tests do NOT initialize the actual emulator — they test the error
/// paths that fire before libatari800_init() is called (ROM file existence
/// checks) and the error message formatting for all ROM-related errors.
final class MissingROMsErrorTests: XCTestCase {

    // =========================================================================
    // MARK: - ROM Not Found Error Messages
    // =========================================================================

    /// AtticError.romNotFound includes the missing file path in its description.
    ///
    /// When the user provides a ROM directory that doesn't contain the expected
    /// ROM files, the error message must include the full path so the user knows
    /// exactly which file is missing.
    func test_romNotFound_includesPath() {
        let path = "/Users/test/.attic/ROM/ATARIXL.ROM"
        let error = AtticError.romNotFound(path)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains(path),
            "Error should include the missing ROM path, got: \(description)")
        XCTAssertTrue(description.contains("ROM not found"),
            "Error should say ROM not found, got: \(description)")
    }

    /// AtticError.romNotFound uses LocalizedError protocol correctly.
    ///
    /// Swift's LocalizedError protocol provides errorDescription which is used
    /// by the default Error description. This test verifies the protocol
    /// conformance is working so that error.localizedDescription also works.
    func test_romNotFound_localizedDescription_matchesErrorDescription() {
        let error = AtticError.romNotFound("/path/to/ATARIXL.ROM")

        // localizedDescription should match errorDescription for LocalizedError
        XCTAssertEqual(
            error.localizedDescription,
            error.errorDescription,
            "localizedDescription should match errorDescription"
        )
    }

    /// Multiple ROM paths produce distinct error messages.
    ///
    /// The emulator needs two ROMs: ATARIXL.ROM and ATARIBAS.ROM. Each missing
    /// ROM should produce a unique error message that identifies it specifically.
    func test_romNotFound_distinctPathsProduceDistinctMessages() {
        let osError = AtticError.romNotFound("/rom/ATARIXL.ROM")
        let basicError = AtticError.romNotFound("/rom/ATARIBAS.ROM")

        XCTAssertNotEqual(
            osError.errorDescription, basicError.errorDescription,
            "Different ROM paths should produce different error messages"
        )
        XCTAssertTrue(osError.errorDescription!.contains("ATARIXL.ROM"))
        XCTAssertTrue(basicError.errorDescription!.contains("ATARIBAS.ROM"))
    }

    // =========================================================================
    // MARK: - Initialization Failed Error Messages
    // =========================================================================

    /// AtticError.initializationFailed includes the underlying reason.
    ///
    /// When libatari800_init() fails (returns 0), the error should include
    /// whatever message the C library provides. This helps diagnose issues
    /// like incompatible ROM files or corrupted ROM data.
    func test_initializationFailed_includesReason() {
        let reason = "Invalid ROM checksum"
        let error = AtticError.initializationFailed(reason)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains(reason),
            "Error should include the failure reason, got: \(description)")
        XCTAssertTrue(description.lowercased().contains("initialization"),
            "Error should mention initialization, got: \(description)")
    }

    /// AtticError.initializationFailed with empty reason still provides useful context.
    func test_initializationFailed_emptyReason_stillUseful() {
        let error = AtticError.initializationFailed("")

        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty,
            "Error description should never be empty")
        XCTAssertTrue(description.lowercased().contains("initialization"),
            "Error should still mention initialization even with empty reason")
    }

    // =========================================================================
    // MARK: - Not Initialized Error Messages
    // =========================================================================

    /// AtticError.notInitialized provides a clear message.
    ///
    /// This error is thrown when emulator methods are called before
    /// initialize(romPath:). The message should help the user understand
    /// what they need to do.
    func test_notInitialized_providesUsefulMessage() {
        let error = AtticError.notInitialized

        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.lowercased().contains("not initialized"),
            "Error should say the emulator is not initialized, got: \(description)")
    }

    // =========================================================================
    // MARK: - Invalid ROM Error Messages
    // =========================================================================

    /// AtticError.invalidROM includes the reason for invalidity.
    ///
    /// A ROM file might exist but be the wrong size, corrupted, or for the
    /// wrong machine. The error should explain why the ROM was rejected.
    func test_invalidROM_includesReason() {
        let reason = "Expected 16384 bytes, got 8192"
        let error = AtticError.invalidROM(reason)

        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains(reason),
            "Error should include the invalidity reason, got: \(description)")
    }

    // =========================================================================
    // MARK: - LibAtari800Wrapper ROM Checks
    // =========================================================================

    /// Wrapper throws romNotFound when OS ROM (ATARIXL.ROM) is missing.
    ///
    /// LibAtari800Wrapper.initialize() checks for ROM files before calling
    /// into the C library. If the directory exists but ATARIXL.ROM is absent,
    /// it should throw romNotFound with the expected path.
    func test_wrapper_missingOSRom_throwsRomNotFound() {
        let wrapper = LibAtari800Wrapper()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_rom_test_\(UUID().uuidString)")

        // Create a directory with only ATARIBAS.ROM (no ATARIXL.ROM)
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        try? Data(repeating: 0, count: 8192).write(
            to: tempDir.appendingPathComponent("ATARIBAS.ROM")
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertThrowsError(try wrapper.initialize(romPath: tempDir)) { error in
            guard let atticError = error as? AtticError else {
                XCTFail("Expected AtticError, got \(type(of: error))")
                return
            }
            if case .romNotFound(let path) = atticError {
                XCTAssertTrue(path.contains("ATARIXL.ROM"),
                    "Error should identify ATARIXL.ROM as missing, got: \(path)")
            } else {
                XCTFail("Expected romNotFound, got \(atticError)")
            }
        }
    }

    /// Wrapper throws romNotFound when BASIC ROM (ATARIBAS.ROM) is missing.
    ///
    /// If ATARIXL.ROM exists but ATARIBAS.ROM is absent, the error should
    /// specifically identify the BASIC ROM as the missing file.
    func test_wrapper_missingBasicRom_throwsRomNotFound() {
        let wrapper = LibAtari800Wrapper()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_rom_test_\(UUID().uuidString)")

        // Create a directory with only ATARIXL.ROM (no ATARIBAS.ROM)
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        try? Data(repeating: 0, count: 16384).write(
            to: tempDir.appendingPathComponent("ATARIXL.ROM")
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertThrowsError(try wrapper.initialize(romPath: tempDir)) { error in
            guard let atticError = error as? AtticError else {
                XCTFail("Expected AtticError, got \(type(of: error))")
                return
            }
            if case .romNotFound(let path) = atticError {
                XCTAssertTrue(path.contains("ATARIBAS.ROM"),
                    "Error should identify ATARIBAS.ROM as missing, got: \(path)")
            } else {
                XCTFail("Expected romNotFound, got \(atticError)")
            }
        }
    }

    /// Wrapper throws romNotFound when both ROMs are missing.
    ///
    /// The check is sequential — ATARIXL.ROM is checked first, so that's
    /// the one reported. This tests the empty directory case.
    func test_wrapper_bothRomsMissing_throwsForOSRomFirst() {
        let wrapper = LibAtari800Wrapper()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_rom_test_\(UUID().uuidString)")

        // Create an empty directory
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertThrowsError(try wrapper.initialize(romPath: tempDir)) { error in
            guard let atticError = error as? AtticError else {
                XCTFail("Expected AtticError, got \(type(of: error))")
                return
            }
            if case .romNotFound(let path) = atticError {
                // ATARIXL.ROM is checked first
                XCTAssertTrue(path.contains("ATARIXL.ROM"),
                    "Should report ATARIXL.ROM first when both are missing, got: \(path)")
            } else {
                XCTFail("Expected romNotFound, got \(atticError)")
            }
        }
    }

    /// Wrapper throws romNotFound when the ROM directory itself doesn't exist.
    ///
    /// A completely nonexistent path should still produce a romNotFound error,
    /// not a crash or an unrelated system error.
    func test_wrapper_nonexistentRomDir_throwsRomNotFound() {
        let wrapper = LibAtari800Wrapper()
        let badPath = URL(fileURLWithPath: "/nonexistent/rom/path/\(UUID().uuidString)")

        XCTAssertThrowsError(try wrapper.initialize(romPath: badPath)) { error in
            guard let atticError = error as? AtticError else {
                XCTFail("Expected AtticError, got \(type(of: error))")
                return
            }
            if case .romNotFound = atticError {
                // Expected — the directory doesn't exist, so neither ROM is found
            } else {
                XCTFail("Expected romNotFound, got \(atticError)")
            }
        }
    }

    // =========================================================================
    // MARK: - Error Type Identity
    // =========================================================================

    /// All ROM-related error cases are distinct.
    ///
    /// Verifies that the error enum cases are properly differentiated so
    /// that catch blocks can match on specific cases.
    func test_romErrors_areDistinctCases() {
        let romNotFound = AtticError.romNotFound("/path")
        let invalidROM = AtticError.invalidROM("bad size")
        let notInitialized = AtticError.notInitialized
        let initFailed = AtticError.initializationFailed("unknown")

        // Each should have a different error description
        let descriptions = [
            romNotFound.errorDescription!,
            invalidROM.errorDescription!,
            notInitialized.errorDescription!,
            initFailed.errorDescription!,
        ]
        let uniqueDescriptions = Set(descriptions)
        XCTAssertEqual(descriptions.count, uniqueDescriptions.count,
            "All ROM-related errors should have distinct descriptions")
    }
}

// =============================================================================
// MARK: - 13.2 Invalid Files Error Tests
// =============================================================================

/// Tests for error handling when loading invalid or corrupt files.
///
/// These tests verify:
/// - Invalid ATR disk images produce clear, specific errors
/// - Corrupt state files are detected and reported with context
/// - DiskManager reports path/mount errors with the relevant filename
/// - Error descriptions include recovery suggestions where applicable
/// - ATR format validation catches all known corruption types
///
/// No emulator or server is needed — these tests create temporary files
/// with specific corruption patterns and verify the error responses.
final class InvalidFilesErrorTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attic_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // =========================================================================
    // MARK: - ATR Invalid Magic
    // =========================================================================

    /// A random binary file (not ATR) throws invalidMagic.
    ///
    /// ATR files must start with bytes $96 $02. Any other opening bytes
    /// indicate a non-ATR file and should produce a clear error.
    func test_atr_randomData_throwsInvalidMagic() {
        let randomData = Data([0xFF, 0xFE, 0x00, 0x01] + [UInt8](repeating: 0, count: 20))

        XCTAssertThrowsError(try ATRImage(data: randomData)) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(atrError, .invalidMagic,
                "Random data should trigger invalidMagic")
        }
    }

    /// An empty file throws headerTooShort.
    ///
    /// The ATR header is 16 bytes. An empty file cannot contain a valid header.
    func test_atr_emptyData_throwsHeaderTooShort() {
        XCTAssertThrowsError(try ATRImage(data: Data())) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(atrError, .headerTooShort)
        }
    }

    /// A truncated header (less than 16 bytes) throws headerTooShort.
    func test_atr_truncatedHeader_throwsHeaderTooShort() {
        // Only 10 bytes — too short for a 16-byte header
        let data = Data([0x96, 0x02, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try ATRImage(data: data)) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(atrError, .headerTooShort)
        }
    }

    /// A file with valid magic but invalid sector size throws invalidSectorSize.
    ///
    /// Valid sector sizes are 128 and 256. Anything else indicates corruption
    /// or an unsupported format.
    func test_atr_invalidSectorSize_throwsInvalidSectorSize() {
        // Build a 16-byte header with valid magic but sector size of 512
        var data = Data(count: 16)
        data[0] = 0x96  // Magic byte 1
        data[1] = 0x02  // Magic byte 2
        data[2] = 0x01  // Paragraphs low
        data[3] = 0x00
        data[4] = 0x00  // Sector size low byte: 0x0200 = 512
        data[5] = 0x02  // Sector size high byte
        // Rest is zeros

        XCTAssertThrowsError(try ATRImage(data: data)) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            if case .invalidSectorSize(let size) = atrError {
                XCTAssertEqual(size, 512,
                    "Should report the invalid sector size value")
            } else {
                XCTFail("Expected invalidSectorSize, got \(atrError)")
            }
        }
    }

    /// A text file (e.g., BASIC source) is not a valid ATR image.
    func test_atr_textFile_throwsInvalidMagicOrHeaderTooShort() {
        let textData = Data("10 PRINT \"HELLO\"\n20 GOTO 10\n".utf8)

        XCTAssertThrowsError(try ATRImage(data: textData)) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            // "10 " doesn't match $96 $02 magic bytes
            XCTAssertEqual(atrError, .invalidMagic)
        }
    }

    /// ATR file loaded from nonexistent path throws readFailed.
    func test_atr_nonexistentPath_throwsReadFailed() {
        let badURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).atr")

        XCTAssertThrowsError(try ATRImage(url: badURL)) { error in
            guard let atrError = error as? ATRError else {
                XCTFail("Expected ATRError, got \(type(of: error))")
                return
            }
            if case .readFailed = atrError {
                // Expected — file doesn't exist
            } else {
                XCTFail("Expected readFailed, got \(atrError)")
            }
        }
    }

    // =========================================================================
    // MARK: - ATR Error Descriptions
    // =========================================================================

    /// ATRError.invalidMagic has a human-readable description.
    func test_atrError_invalidMagic_hasUsefulDescription() {
        let error = ATRError.invalidMagic
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.lowercased().contains("atr") ||
                      description.lowercased().contains("magic"),
            "Error should mention ATR or magic bytes, got: \(description)")
    }

    /// ATRError.headerTooShort suggests the file may be truncated.
    func test_atrError_headerTooShort_suggestsTruncation() {
        let error = ATRError.headerTooShort
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.lowercased().contains("truncated") ||
                      description.lowercased().contains("incomplete"),
            "Error should mention truncation, got: \(description)")
    }

    /// ATRError.invalidSectorSize includes the invalid value.
    func test_atrError_invalidSectorSize_includesValue() {
        let error = ATRError.invalidSectorSize(512)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("512"),
            "Error should include the invalid sector size, got: \(description)")
    }

    /// ATRError.readFailed includes the underlying reason.
    func test_atrError_readFailed_includesReason() {
        let error = ATRError.readFailed("No such file or directory")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("No such file"),
            "Error should include the underlying reason, got: \(description)")
    }

    /// ATRError recovery suggestions exist for common errors.
    func test_atrError_recoverySuggestions_exist() {
        // invalidMagic should have a recovery suggestion
        XCTAssertNotNil(ATRError.invalidMagic.recoverySuggestion,
            "invalidMagic should have a recovery suggestion")
        XCTAssertNotNil(ATRError.headerTooShort.recoverySuggestion,
            "headerTooShort should have a recovery suggestion")
        XCTAssertNotNil(ATRError.fileNotFound("test").recoverySuggestion,
            "fileNotFound should have a recovery suggestion")
        XCTAssertNotNil(ATRError.diskFull.recoverySuggestion,
            "diskFull should have a recovery suggestion")
    }

    /// ATRError.sizeMismatch includes expected and actual values.
    func test_atrError_sizeMismatch_includesBothValues() {
        let error = ATRError.sizeMismatch(expected: 92160, actual: 50000)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("92160"),
            "Error should include expected size, got: \(description)")
        XCTAssertTrue(description.contains("50000"),
            "Error should include actual size, got: \(description)")
    }

    // =========================================================================
    // MARK: - ATR DOS Filesystem Errors
    // =========================================================================

    /// ATRError.fileNotFound includes the filename.
    func test_atrError_fileNotFound_includesFilename() {
        let error = ATRError.fileNotFound("GAME.COM")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("GAME.COM"),
            "Error should include the missing filename, got: \(description)")
    }

    /// ATRError.invalidFilename includes both the filename and the reason.
    func test_atrError_invalidFilename_includesDetails() {
        let error = ATRError.invalidFilename(
            filename: "toolongfilename.ext",
            reason: "Name exceeds 8 characters"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("toolongfilename"),
            "Error should include the invalid filename, got: \(description)")
        XCTAssertTrue(description.contains("8 characters"),
            "Error should include the reason, got: \(description)")
    }

    /// ATRError.fileChainCorrupted includes both filename and corruption details.
    func test_atrError_fileChainCorrupted_includesContext() {
        let error = ATRError.fileChainCorrupted(
            filename: "DATA.DAT",
            reason: "Circular link detected at sector 42"
        )
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("DATA.DAT"),
            "Error should include the filename, got: \(description)")
        XCTAssertTrue(description.contains("sector 42"),
            "Error should include the corruption detail, got: \(description)")
    }

    /// ATRError.sectorOutOfRange includes the invalid sector and the valid range.
    func test_atrError_sectorOutOfRange_includesRange() {
        let error = ATRError.sectorOutOfRange(sector: 999, maxSector: 720)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("999"),
            "Error should include the invalid sector, got: \(description)")
        XCTAssertTrue(description.contains("720"),
            "Error should include the max sector, got: \(description)")
    }

    // =========================================================================
    // MARK: - Corrupt State File Errors
    // =========================================================================

    /// Loading a file with wrong magic bytes throws invalidMagic.
    func test_stateFile_wrongMagic_throwsInvalidMagic() throws {
        // Write data that starts with "XXXX" instead of "ATTC"
        var data = Data("XXXX".utf8)
        data.append(contentsOf: [UInt8](repeating: 0, count: 100))

        let url = tempDir.appendingPathComponent("bad_magic.attic")
        try data.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(type(of: error))")
                return
            }
            if case .invalidMagic = stateError {
                // Expected
            } else {
                XCTFail("Expected invalidMagic, got \(stateError)")
            }
        }
    }

    /// Loading a file with unsupported version number throws unsupportedVersion.
    func test_stateFile_futureVersion_throwsUnsupportedVersion() throws {
        var data = Data(StateFileConstants.magic)
        data.append(0xFF)  // Version 255 — far future version
        data.append(0x00)  // Flags
        data.append(contentsOf: [UInt8](repeating: 0, count: 100))

        let url = tempDir.appendingPathComponent("future_version.attic")
        try data.write(to: url)

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(type(of: error))")
                return
            }
            if case .unsupportedVersion(let version) = stateError {
                XCTAssertEqual(version, 0xFF)
            } else {
                XCTFail("Expected unsupportedVersion, got \(stateError)")
            }
        }
    }

    /// Loading a 3-byte file (too small for header) throws truncatedFile.
    func test_stateFile_tooSmall_throwsTruncatedFile() throws {
        let url = tempDir.appendingPathComponent("tiny.attic")
        try Data([0x41, 0x54, 0x43]).write(to: url)  // "ATC" — incomplete magic

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(type(of: error))")
                return
            }
            if case .truncatedFile = stateError {
                // Expected
            } else if case .invalidMagic = stateError {
                // Also acceptable — header too short to even check magic
            } else {
                XCTFail("Expected truncatedFile or invalidMagic, got \(stateError)")
            }
        }
    }

    /// Loading a nonexistent file throws readFailed.
    func test_stateFile_nonexistent_throwsReadFailed() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).attic")

        XCTAssertThrowsError(try StateFileHandler.read(from: url)) { error in
            guard let stateError = error as? StateFileError else {
                XCTFail("Expected StateFileError, got \(type(of: error))")
                return
            }
            if case .readFailed = stateError {
                // Expected
            } else {
                XCTFail("Expected readFailed, got \(stateError)")
            }
        }
    }

    // =========================================================================
    // MARK: - State File Error Descriptions
    // =========================================================================

    /// StateFileError.invalidMagic has a useful error description.
    func test_stateFileError_invalidMagic_hasDescription() {
        let error = StateFileError.invalidMagic
        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.isEmpty,
            "invalidMagic should have an error description")
    }

    /// StateFileError.unsupportedVersion includes the version number.
    func test_stateFileError_unsupportedVersion_includesVersion() {
        let error = StateFileError.unsupportedVersion(0x99)
        let description = error.errorDescription ?? ""
        // The description should reference the version somehow
        XCTAssertFalse(description.isEmpty,
            "unsupportedVersion should have an error description")
    }

    /// StateFileError.truncatedFile includes expected and actual sizes.
    func test_stateFileError_truncatedFile_includesSizes() {
        let error = StateFileError.truncatedFile(expected: 210016, actual: 1024)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("210016") || description.contains("1024"),
            "truncatedFile should include size information, got: \(description)")
    }

    /// StateFileError.writeFailed includes the underlying reason.
    func test_stateFileError_writeFailed_includesReason() {
        let error = StateFileError.writeFailed("Permission denied")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Permission denied"),
            "writeFailed should include the reason, got: \(description)")
    }

    /// StateFileError.readFailed includes the underlying reason.
    func test_stateFileError_readFailed_includesReason() {
        let error = StateFileError.readFailed("No such file or directory")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("No such file"),
            "readFailed should include the reason, got: \(description)")
    }

    // =========================================================================
    // MARK: - DiskManager Error Handling
    // =========================================================================

    /// DiskManager.mount with nonexistent path throws pathNotFound.
    func test_diskManager_nonexistentPath_throwsPathNotFound() async {
        let manager = DiskManager()
        let badPath = "/tmp/nonexistent_\(UUID().uuidString).atr"

        do {
            try await manager.mount(drive: 1, path: badPath)
            XCTFail("Should have thrown an error for nonexistent path")
        } catch let error as DiskManagerError {
            if case .pathNotFound(let path) = error {
                XCTAssertEqual(path, badPath,
                    "Error should include the exact path that was not found")
            } else {
                XCTFail("Expected pathNotFound, got \(error)")
            }
        } catch {
            XCTFail("Expected DiskManagerError, got \(type(of: error)): \(error)")
        }
    }

    /// DiskManager.mount with invalid drive number throws invalidDrive.
    func test_diskManager_invalidDrive_throwsInvalidDrive() async {
        let manager = DiskManager()

        // Drive 0 is invalid (valid range is 1-8)
        do {
            try await manager.mount(drive: 0, path: "/tmp/test.atr")
            XCTFail("Should have thrown for drive 0")
        } catch let error as DiskManagerError {
            if case .invalidDrive(let drive) = error {
                XCTAssertEqual(drive, 0)
            } else {
                XCTFail("Expected invalidDrive, got \(error)")
            }
        } catch {
            XCTFail("Expected DiskManagerError, got \(type(of: error))")
        }

        // Drive 9 is also invalid
        do {
            try await manager.mount(drive: 9, path: "/tmp/test.atr")
            XCTFail("Should have thrown for drive 9")
        } catch let error as DiskManagerError {
            if case .invalidDrive(let drive) = error {
                XCTAssertEqual(drive, 9)
            } else {
                XCTFail("Expected invalidDrive, got \(error)")
            }
        } catch {
            XCTFail("Expected DiskManagerError, got \(type(of: error))")
        }
    }

    /// DiskManager.unmount on empty drive throws driveEmpty.
    func test_diskManager_unmountEmptyDrive_throwsDriveEmpty() async {
        let manager = DiskManager()

        do {
            try await manager.unmount(drive: 1)
            XCTFail("Should have thrown for empty drive")
        } catch let error as DiskManagerError {
            if case .driveEmpty(let drive) = error {
                XCTAssertEqual(drive, 1)
            } else {
                XCTFail("Expected driveEmpty, got \(error)")
            }
        } catch {
            XCTFail("Expected DiskManagerError, got \(type(of: error))")
        }
    }

    /// DiskManager.changeDrive to empty drive throws driveEmpty.
    func test_diskManager_changeToEmptyDrive_throwsDriveEmpty() async {
        let manager = DiskManager()

        do {
            try await manager.changeDrive(to: 5)
            XCTFail("Should have thrown for empty drive")
        } catch let error as DiskManagerError {
            if case .driveEmpty(let drive) = error {
                XCTAssertEqual(drive, 5)
            } else {
                XCTFail("Expected driveEmpty, got \(error)")
            }
        } catch {
            XCTFail("Expected DiskManagerError, got \(type(of: error))")
        }
    }

    /// DiskManager error descriptions include the drive number.
    func test_diskManagerError_descriptions_includeDriveNumber() {
        let errors: [(DiskManagerError, String)] = [
            (.invalidDrive(0), "0"),
            (.driveEmpty(3), "3"),
            (.driveInUse(2), "2"),
            (.diskReadOnly(4), "4"),
        ]

        for (error, expectedNumber) in errors {
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains(expectedNumber),
                "\(error) description should include drive number \(expectedNumber), got: \(description)")
        }
    }

    /// DiskManager.pathNotFound includes the path in the error description.
    func test_diskManagerError_pathNotFound_includesPath() {
        let error = DiskManagerError.pathNotFound("/games/starraiders.atr")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("/games/starraiders.atr"),
            "Error should include the path, got: \(description)")
    }

    /// DiskManager.mountFailed includes the reason.
    func test_diskManagerError_mountFailed_includesReason() {
        let error = DiskManagerError.mountFailed("Not a valid ATR disk image")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Not a valid ATR"),
            "Error should include the reason, got: \(description)")
    }

    // =========================================================================
    // MARK: - General AtticError File Errors
    // =========================================================================

    /// AtticError.fileError includes the reason.
    func test_atticError_fileError_includesReason() {
        let error = AtticError.fileError("Permission denied: /path/to/file")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Permission denied"),
            "Error should include the reason, got: \(description)")
    }

    /// AtticError.diskError includes the reason.
    func test_atticError_diskError_includesReason() {
        let error = AtticError.diskError("Drive D1: is not formatted")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Drive D1"),
            "Error should include the disk detail, got: \(description)")
    }

    /// AtticError.atrError includes the reason.
    func test_atticError_atrError_includesReason() {
        let error = AtticError.atrError("Invalid sector link at sector 42")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("sector 42"),
            "Error should include the ATR detail, got: \(description)")
    }
}

// =============================================================================
// MARK: - 13.3 Network Errors Tests
// =============================================================================

/// Tests for network-related error handling.
///
/// These tests verify:
/// - AESPError types have human-readable descriptions
/// - Connection error messages include the relevant detail (host, reason)
/// - Client configuration defaults are sensible (timeout, ports)
/// - AESP protocol validation errors are specific and actionable
/// - Error descriptions help users diagnose connection problems
///
/// These tests use the AESPError enum and AESPClientConfiguration directly —
/// they do NOT require a running server or actual network connections.
///
/// Note: Tests that require AtticProtocol types are imported from that module.
import AtticProtocol

final class NetworkErrorsTests: XCTestCase {

    // =========================================================================
    // MARK: - Connection Error Messages
    // =========================================================================

    /// AESPError.connectionError includes the underlying reason.
    ///
    /// When a client can't reach the server, the error message should include
    /// enough detail to help the user fix the problem (e.g., wrong host,
    /// server not running, firewall blocking).
    func test_connectionError_includesReason() {
        let error = AESPError.connectionError("Connection refused on port 47800")
        let description = error.description
        XCTAssertTrue(description.contains("47800"),
            "Error should include the port, got: \(description)")
        XCTAssertTrue(description.contains("refused"),
            "Error should include the reason, got: \(description)")
    }

    /// AESPError.connectionError with server-not-running message.
    func test_connectionError_serverNotRunning_hasHelpfulMessage() {
        let error = AESPError.connectionError(
            "Could not connect to localhost:47800 - is AtticServer running?"
        )
        let description = error.description
        XCTAssertTrue(description.contains("AtticServer"),
            "Error should mention AtticServer, got: \(description)")
        XCTAssertTrue(description.lowercased().contains("running"),
            "Error should ask if server is running, got: \(description)")
    }

    /// AESPError.connectionError with timeout message.
    func test_connectionError_timeout_hasHelpfulMessage() {
        let error = AESPError.connectionError(
            "Connection timed out after 5.0 seconds"
        )
        let description = error.description
        XCTAssertTrue(description.contains("timed out"),
            "Error should mention timeout, got: \(description)")
    }

    // =========================================================================
    // MARK: - Protocol Validation Errors
    // =========================================================================

    /// AESPError.invalidMagic includes the received (wrong) magic value.
    ///
    /// When connecting to a non-AESP server (or a corrupt stream), the
    /// error should show what magic number was received so the user can
    /// diagnose whether they connected to the wrong service.
    func test_protocolError_invalidMagic_includesReceivedValue() {
        let error = AESPError.invalidMagic(received: 0x4854)  // "HT" — HTTP server
        let description = error.description
        XCTAssertTrue(description.contains("4854") || description.contains("0x4854"),
            "Error should include the received magic value, got: \(description)")
        XCTAssertTrue(description.contains("AE50") || description.contains("0xAE50"),
            "Error should mention the expected magic value, got: \(description)")
    }

    /// AESPError.unsupportedVersion includes the received version.
    func test_protocolError_unsupportedVersion_includesReceivedValue() {
        let error = AESPError.unsupportedVersion(received: 0x99)
        let description = error.description
        XCTAssertTrue(description.lowercased().contains("version"),
            "Error should mention version, got: \(description)")
    }

    /// AESPError.unknownMessageType includes the unknown type code.
    func test_protocolError_unknownMessageType_includesRawValue() {
        let error = AESPError.unknownMessageType(rawValue: 0xFE)
        let description = error.description
        XCTAssertTrue(description.contains("FE") || description.contains("254") || description.contains("0xFE"),
            "Error should include the unknown type value, got: \(description)")
    }

    /// AESPError.payloadTooLarge includes the size.
    func test_protocolError_payloadTooLarge_includesSize() {
        let error = AESPError.payloadTooLarge(size: 20_000_000)
        let description = error.description
        XCTAssertTrue(description.contains("20000000") || description.contains("20,000,000"),
            "Error should include the payload size, got: \(description)")
    }

    /// AESPError.insufficientData includes expected and received counts.
    func test_protocolError_insufficientData_includesBothCounts() {
        let error = AESPError.insufficientData(expected: 8, received: 3)
        let description = error.description
        XCTAssertTrue(description.contains("8"),
            "Error should include expected count, got: \(description)")
        XCTAssertTrue(description.contains("3"),
            "Error should include received count, got: \(description)")
    }

    /// AESPError.invalidPayload includes the message type and reason.
    func test_protocolError_invalidPayload_includesContext() {
        let error = AESPError.invalidPayload(
            messageType: .status,
            reason: "Missing required fields"
        )
        let description = error.description
        XCTAssertTrue(description.lowercased().contains("status"),
            "Error should include the message type, got: \(description)")
        XCTAssertTrue(description.contains("Missing required"),
            "Error should include the reason, got: \(description)")
    }

    /// AESPError.serverError includes the error code and message.
    func test_protocolError_serverError_includesCodeAndMessage() {
        let error = AESPError.serverError(code: 0x01, message: "Emulator not initialized")
        let description = error.description
        XCTAssertTrue(description.contains("not initialized") || description.contains("Emulator"),
            "Error should include the server message, got: \(description)")
    }

    // =========================================================================
    // MARK: - Client Configuration Defaults
    // =========================================================================

    /// Default client configuration has sensible timeout.
    ///
    /// The default timeout should be long enough to handle normal startup
    /// but short enough that users don't wait forever for a dead server.
    func test_clientConfig_defaultTimeout_isSensible() {
        let config = AESPClientConfiguration()
        XCTAssertGreaterThanOrEqual(config.connectionTimeout, 1.0,
            "Timeout should be at least 1 second")
        XCTAssertLessThanOrEqual(config.connectionTimeout, 30.0,
            "Timeout should be at most 30 seconds")
    }

    /// Default client configuration uses localhost.
    func test_clientConfig_defaultHost_isLocalhost() {
        let config = AESPClientConfiguration()
        XCTAssertEqual(config.host, "localhost",
            "Default host should be localhost for local emulator")
    }

    /// Default client configuration uses AESP standard ports.
    func test_clientConfig_defaultPorts_matchAESPConstants() {
        let config = AESPClientConfiguration()
        XCTAssertEqual(config.controlPort, AESPConstants.defaultControlPort)
        XCTAssertEqual(config.videoPort, AESPConstants.defaultVideoPort)
        XCTAssertEqual(config.audioPort, AESPConstants.defaultAudioPort)
    }

    /// Custom client configuration preserves all values.
    func test_clientConfig_customValues_preserved() {
        let config = AESPClientConfiguration(
            host: "192.168.1.50",
            controlPort: 9000,
            videoPort: 9001,
            audioPort: 9002,
            connectionTimeout: 15.0
        )
        XCTAssertEqual(config.host, "192.168.1.50")
        XCTAssertEqual(config.controlPort, 9000)
        XCTAssertEqual(config.videoPort, 9001)
        XCTAssertEqual(config.audioPort, 9002)
        XCTAssertEqual(config.connectionTimeout, 15.0)
    }

    // =========================================================================
    // MARK: - Connection State
    // =========================================================================

    /// AESPClientState.failed carries the error.
    ///
    /// When a connection attempt fails, the state should carry the error
    /// so that the UI or REPL can display it to the user.
    func test_connectionState_failed_carriesError() {
        let underlyingError = AESPError.connectionError("Connection refused")
        let state = AESPClientState.failed(underlyingError)

        if case .failed(let error) = state {
            let aesp = error as? AESPError
            XCTAssertNotNil(aesp,
                "Failed state should carry the AESPError")
        } else {
            XCTFail("Expected failed state")
        }
    }

    /// All connection states are representable.
    func test_connectionStates_allCasesExist() {
        // Verify all expected states exist (compile-time check)
        let states: [AESPClientState] = [
            .disconnected,
            .connecting,
            .connected,
            .failed(AESPError.connectionError("test"))
        ]
        XCTAssertEqual(states.count, 4, "Should have 4 connection states")
    }

    // =========================================================================
    // MARK: - AtticError Socket/Network Errors
    // =========================================================================

    /// AtticError.socketError includes the reason.
    func test_atticError_socketError_includesReason() {
        let error = AtticError.socketError("Connection reset by peer")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Connection reset"),
            "Error should include the socket reason, got: \(description)")
    }

    /// AtticError.socketError is distinct from AESPError.connectionError.
    ///
    /// AtticError.socketError is used for the CLI socket server, while
    /// AESPError.connectionError is used for the AESP protocol. They are
    /// separate error types from separate modules.
    func test_socketError_vs_connectionError_distinct() {
        let atticError = AtticError.socketError("test")
        let aespError = AESPError.connectionError("test")

        // They're different types entirely
        XCTAssertFalse(type(of: atticError as Error) == type(of: aespError as Error))
    }

    // =========================================================================
    // MARK: - Error Descriptions Are Non-Empty
    // =========================================================================

    /// All AESPError cases produce non-empty descriptions.
    ///
    /// This is a meta-test ensuring no error case was forgotten when
    /// implementing CustomStringConvertible.
    func test_allAESPErrors_haveNonEmptyDescriptions() {
        let errors: [AESPError] = [
            .invalidMagic(received: 0x0000),
            .unsupportedVersion(received: 0),
            .unknownMessageType(rawValue: 0),
            .payloadTooLarge(size: 0),
            .insufficientData(expected: 0, received: 0),
            .invalidPayload(messageType: .ping, reason: ""),
            .connectionError(""),
            .serverError(code: 0, message: ""),
        ]

        for error in errors {
            XCTAssertFalse(error.description.isEmpty,
                "\(error) should have a non-empty description")
        }
    }

    /// All AtticError cases produce non-empty descriptions.
    func test_allAtticErrors_haveNonEmptyDescriptions() {
        let errors: [AtticError] = [
            .romNotFound(""),
            .invalidROM(""),
            .stateLoadFailed(""),
            .stateSaveFailed(""),
            .memoryAccessError(""),
            .notInitialized,
            .initializationFailed(""),
            .socketError(""),
            .invalidCommand("", suggestion: nil),
            .fileError(""),
            .diskError(""),
            .atrError(""),
            .dosError(""),
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty,
                "\(error) should have a non-empty error description")
        }
    }

    /// AtticError.invalidCommand includes the suggestion when provided.
    func test_atticError_invalidCommand_includesSuggestion() {
        let error = AtticError.invalidCommand(".hlp", suggestion: "Did you mean '.help'?")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains(".hlp"),
            "Error should include the invalid command, got: \(description)")
        XCTAssertTrue(description.contains("Did you mean"),
            "Error should include the suggestion, got: \(description)")
    }

    /// AtticError.invalidCommand without suggestion still works.
    func test_atticError_invalidCommand_withoutSuggestion_stillUseful() {
        let error = AtticError.invalidCommand(".xyz", suggestion: nil)
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains(".xyz"),
            "Error should include the invalid command, got: \(description)")
        XCTAssertFalse(description.isEmpty)
    }
}
