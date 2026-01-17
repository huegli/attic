// =============================================================================
// DirectoryEntryTests.swift - Unit Tests for Directory Entry Parsing
// =============================================================================
//
// Tests for the DirectoryEntry structure that represents files in the
// Atari DOS directory.
//
// =============================================================================

import XCTest
@testable import AtticCore

final class DirectoryEntryTests: XCTestCase {

    // =========================================================================
    // MARK: - Parsing
    // =========================================================================

    func testParseNormalFile() {
        // Create a directory entry for GAME.BAS
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x42  // Flags: in use
        bytes[1] = 10    // Sector count low
        bytes[2] = 0     // Sector count high
        bytes[3] = 45    // Start sector low
        bytes[4] = 0     // Start sector high
        // Filename "GAME    " (8 bytes)
        bytes[5] = 0x47  // G
        bytes[6] = 0x41  // A
        bytes[7] = 0x4D  // M
        bytes[8] = 0x45  // E
        bytes[9] = 0x20  // space
        bytes[10] = 0x20 // space
        bytes[11] = 0x20 // space
        bytes[12] = 0x20 // space
        // Extension "BAS" (3 bytes)
        bytes[13] = 0x42 // B
        bytes[14] = 0x41 // A
        bytes[15] = 0x53 // S

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 5)

        XCTAssertEqual(entry.flags, 0x42)
        XCTAssertEqual(entry.sectorCount, 10)
        XCTAssertEqual(entry.startSector, 45)
        XCTAssertEqual(entry.trimmedFilename, "GAME")
        XCTAssertEqual(entry.trimmedExtension, "BAS")
        XCTAssertEqual(entry.fullName, "GAME.BAS")
        XCTAssertEqual(entry.entryIndex, 5)
        XCTAssertTrue(entry.isInUse)
        XCTAssertFalse(entry.isDeleted)
        XCTAssertFalse(entry.isLocked)
        XCTAssertFalse(entry.isNeverUsed)
    }

    func testParseLockedFile() {
        var bytes = [UInt8](repeating: 0x20, count: 16)
        bytes[0] = 0x43  // Flags: in use + locked
        bytes[1] = 5
        bytes[3] = 100

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertTrue(entry.isInUse)
        XCTAssertTrue(entry.isLocked)
        XCTAssertFalse(entry.isDeleted)
    }

    func testParseDeletedFile() {
        var bytes = [UInt8](repeating: 0x20, count: 16)
        bytes[0] = 0x80  // Flags: deleted
        bytes[1] = 5
        bytes[3] = 100

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertTrue(entry.isDeleted)
        XCTAssertFalse(entry.isInUse)
    }

    func testParseNeverUsedEntry() {
        let bytes = [UInt8](repeating: 0, count: 16)

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertTrue(entry.isNeverUsed)
        XCTAssertFalse(entry.isInUse)
        XCTAssertFalse(entry.isDeleted)
    }

    func testParseOpenForWrite() {
        var bytes = [UInt8](repeating: 0x20, count: 16)
        bytes[0] = 0x46  // Flags: in use + open for write

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertTrue(entry.isOpenForWrite)
    }

    func testParseDOS25Extended() {
        var bytes = [UInt8](repeating: 0x20, count: 16)
        bytes[0] = 0x62  // Flags: in use + DOS 2.5 extended

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertTrue(entry.isDOS25Extended)
        XCTAssertTrue(entry.isInUse)
    }

    func testParseFilenameWithoutExtension() {
        var bytes = [UInt8](repeating: 0x20, count: 16)
        bytes[0] = 0x42
        bytes[1] = 3
        bytes[3] = 50
        // Filename "README  "
        bytes[5] = 0x52  // R
        bytes[6] = 0x45  // E
        bytes[7] = 0x41  // A
        bytes[8] = 0x44  // D
        bytes[9] = 0x4D  // M
        bytes[10] = 0x45 // E
        // Extension "   " (all spaces)
        bytes[13] = 0x20
        bytes[14] = 0x20
        bytes[15] = 0x20

        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        XCTAssertEqual(entry.trimmedFilename, "README")
        XCTAssertEqual(entry.trimmedExtension, "")
        XCTAssertEqual(entry.fullName, "README")
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    func testEncode() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 15,
            startSector: 200,
            filename: "TEST",
            fileExtension: "DAT",
            entryIndex: 3
        )

        let encoded = entry.encode()

        XCTAssertEqual(encoded.count, 16)
        XCTAssertEqual(encoded[0], 0x42)
        XCTAssertEqual(encoded[1], 15)
        XCTAssertEqual(encoded[2], 0)
        XCTAssertEqual(encoded[3], 200)
        XCTAssertEqual(encoded[4], 0)
        // Filename should be uppercase and padded
        XCTAssertEqual(encoded[5], 0x54)  // T
        XCTAssertEqual(encoded[6], 0x45)  // E
        XCTAssertEqual(encoded[7], 0x53)  // S
        XCTAssertEqual(encoded[8], 0x54)  // T
        XCTAssertEqual(encoded[9], 0x20)  // space
    }

    func testEncodeUppercasesFilename() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 5,
            startSector: 100,
            filename: "myfile",
            fileExtension: "txt",
            entryIndex: 0
        )

        XCTAssertEqual(entry.filename, "MYFILE  ")
        XCTAssertEqual(entry.fileExtension, "TXT")
    }

    // =========================================================================
    // MARK: - Round-Trip
    // =========================================================================

    func testRoundTrip() {
        let original = DirectoryEntry(
            flags: 0x43,
            sectorCount: 25,
            startSector: 300,
            filename: "PROGRAM",
            fileExtension: "COM",
            entryIndex: 7
        )

        let encoded = original.encode()
        let decoded = DirectoryEntry(bytes: encoded, entryIndex: 7)

        XCTAssertEqual(decoded.flags, original.flags)
        XCTAssertEqual(decoded.sectorCount, original.sectorCount)
        XCTAssertEqual(decoded.startSector, original.startSector)
        XCTAssertEqual(decoded.trimmedFilename, "PROGRAM")
        XCTAssertEqual(decoded.trimmedExtension, "COM")
    }

    // =========================================================================
    // MARK: - Filename Validation
    // =========================================================================

    func testValidFilename() {
        let error = DirectoryEntry.validateFilename("GAME", extension: "BAS")
        XCTAssertNil(error)
    }

    func testValidFilenameWithDigits() {
        let error = DirectoryEntry.validateFilename("GAME123", extension: "V1")
        XCTAssertNil(error)
    }

    func testEmptyFilename() {
        let error = DirectoryEntry.validateFilename("", extension: "BAS")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("empty"))
    }

    func testFilenameTooLong() {
        let error = DirectoryEntry.validateFilename("VERYLONGNAME", extension: "BAS")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("too long"))
    }

    func testExtensionTooLong() {
        let error = DirectoryEntry.validateFilename("FILE", extension: "BASIC")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("Extension too long"))
    }

    func testFilenameInvalidChars() {
        let error = DirectoryEntry.validateFilename("FILE@", extension: "TXT")
        XCTAssertNotNil(error)
        XCTAssertTrue(error!.contains("invalid characters"))
    }

    // =========================================================================
    // MARK: - Filename Parsing
    // =========================================================================

    func testParseFilenameWithExtension() {
        let result = DirectoryEntry.parseFilename("GAME.BAS")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "GAME")
        XCTAssertEqual(result?.ext, "BAS")
    }

    func testParseFilenameWithoutExtension() {
        let result = DirectoryEntry.parseFilename("README")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "README")
        XCTAssertEqual(result?.ext, "")
    }

    func testParseFilenameMultipleDots() {
        let result = DirectoryEntry.parseFilename("A.B.C")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "A")
        XCTAssertEqual(result?.ext, "B")  // Only first dot is separator
    }

    // =========================================================================
    // MARK: - Wildcard Matching
    // =========================================================================

    func testWildcardMatchStarExtension() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 5,
            startSector: 100,
            filename: "GAME",
            fileExtension: "BAS",
            entryIndex: 0
        )

        XCTAssertTrue(entry.matchesPattern("*.BAS"))
        XCTAssertTrue(entry.matchesPattern("*.*"))
        XCTAssertFalse(entry.matchesPattern("*.COM"))
    }

    func testWildcardMatchStarFilename() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 5,
            startSector: 100,
            filename: "GAME",
            fileExtension: "BAS",
            entryIndex: 0
        )

        XCTAssertTrue(entry.matchesPattern("GAME.*"))
        XCTAssertTrue(entry.matchesPattern("GA*.*"))
        XCTAssertFalse(entry.matchesPattern("TEST.*"))
    }

    func testWildcardMatchQuestionMark() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 5,
            startSector: 100,
            filename: "GAME1",
            fileExtension: "BAS",
            entryIndex: 0
        )

        XCTAssertTrue(entry.matchesPattern("GAME?.BAS"))
        XCTAssertTrue(entry.matchesPattern("?????.BAS"))
        XCTAssertFalse(entry.matchesPattern("GAME.BAS"))  // Too short
    }

    func testWildcardMatchExact() {
        let entry = DirectoryEntry(
            flags: 0x42,
            sectorCount: 5,
            startSector: 100,
            filename: "GAME",
            fileExtension: "BAS",
            entryIndex: 0
        )

        XCTAssertTrue(entry.matchesPattern("GAME.BAS"))
        XCTAssertFalse(entry.matchesPattern("game.bas"))  // Pattern is uppercase
    }

    // =========================================================================
    // MARK: - Edge Cases
    // =========================================================================

    func testShortBytes() {
        let bytes = [UInt8](repeating: 0, count: 8)  // Too short
        let entry = DirectoryEntry(bytes: bytes, entryIndex: 0)

        // Should handle gracefully with padding
        XCTAssertEqual(entry.flags, 0)
        XCTAssertTrue(entry.isNeverUsed)
    }

    func testDescription() {
        let entry = DirectoryEntry(
            flags: 0x43,
            sectorCount: 10,
            startSector: 100,
            filename: "TEST",
            fileExtension: "DAT",
            entryIndex: 5
        )

        let desc = entry.description
        XCTAssertTrue(desc.contains("TEST.DAT"))
        XCTAssertTrue(desc.contains("10 sectors"))
        XCTAssertTrue(desc.contains("LOCKED"))
    }

    func testDescriptionDeleted() {
        let entry = DirectoryEntry(
            flags: 0x80,
            sectorCount: 5,
            startSector: 50,
            filename: "OLD",
            fileExtension: "TXT",
            entryIndex: 2
        )

        let desc = entry.description
        XCTAssertTrue(desc.contains("DELETED"))
    }

    func testDescriptionNeverUsed() {
        let bytes = [UInt8](repeating: 0, count: 16)
        let entry = DirectoryEntry(bytes: bytes, entryIndex: 10)

        let desc = entry.description
        XCTAssertTrue(desc.contains("unused"))
    }
}
