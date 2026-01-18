// =============================================================================
// ATRError.swift - ATR Filesystem Error Types
// =============================================================================
//
// This file defines all error types specific to ATR disk image operations.
// These errors are separate from the general AtticError to provide detailed,
// filesystem-specific error information.
//
// Error Categories:
// -----------------
// 1. Format Errors: Invalid ATR file format, corrupted headers, etc.
// 2. Filesystem Errors: DOS-level errors like file not found, disk full
// 3. I/O Errors: File system access errors when reading/writing ATR files
// 4. Validation Errors: Invalid parameters like bad sector numbers
//
// Usage Example:
//
//     do {
//         let image = try ATRImage(url: diskURL)
//     } catch ATRError.invalidMagic {
//         print("Not a valid ATR file")
//     } catch ATRError.corrupted(let reason) {
//         print("Disk image corrupted: \(reason)")
//     }
//
// Recovery:
// ---------
// Some errors support recovery attempts. When ATRValidationMode is set to
// .lenient, the parser will try to recover from minor corruption and log
// warnings instead of throwing errors.
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - ATR Error Types
// =============================================================================

/// Errors that can occur during ATR disk image operations.
///
/// These errors provide detailed information about what went wrong during
/// ATR file parsing, DOS filesystem operations, or disk I/O.
///
/// All errors conform to LocalizedError for human-readable error messages
/// that can be displayed to users.
public enum ATRError: Error, LocalizedError, Equatable {

    // =========================================================================
    // MARK: - Format Errors (ATR Container Level)
    // =========================================================================

    /// The file does not start with the ATR magic bytes ($96 $02).
    ///
    /// This indicates the file is not an ATR disk image, or is severely corrupted.
    /// There's no recovery possible - you need a valid ATR file.
    case invalidMagic

    /// The ATR header is incomplete (less than 16 bytes).
    ///
    /// ATR files must have a 16-byte header. This error occurs if the file
    /// is truncated or not an ATR file at all.
    case headerTooShort

    /// The sector size in the header is invalid.
    ///
    /// Valid sector sizes are 128 (single/enhanced density) or 256 (double density).
    /// Any other value indicates corruption or an unsupported format.
    ///
    /// - Parameter size: The invalid sector size found in the header.
    case invalidSectorSize(Int)

    /// The calculated disk size doesn't match the file size.
    ///
    /// The ATR header specifies the disk size in paragraphs. If this doesn't
    /// match the actual file content size, the image may be truncated or corrupted.
    ///
    /// - Parameters:
    ///   - expected: Expected size based on header.
    ///   - actual: Actual file content size.
    case sizeMismatch(expected: Int, actual: Int)

    /// The disk image appears to be corrupted.
    ///
    /// This is a catch-all for various corruption scenarios that don't fit
    /// other specific error types.
    ///
    /// - Parameter reason: Description of what corruption was detected.
    case corrupted(String)

    // =========================================================================
    // MARK: - Sector Errors
    // =========================================================================

    /// The requested sector number is out of range.
    ///
    /// Sector numbers start at 1 (not 0) and must not exceed the disk's
    /// total sector count.
    ///
    /// - Parameters:
    ///   - sector: The invalid sector number requested.
    ///   - maxSector: The maximum valid sector number for this disk.
    case sectorOutOfRange(sector: Int, maxSector: Int)

    /// A sector read returned unexpected data.
    ///
    /// This can occur when reading a sector that should contain specific
    /// data (like the VTOC) but doesn't have the expected format.
    ///
    /// - Parameter reason: Description of what was unexpected.
    case sectorReadError(String)

    // =========================================================================
    // MARK: - DOS Filesystem Errors
    // =========================================================================

    /// The requested file was not found in the directory.
    ///
    /// - Parameter filename: The filename that was not found.
    case fileNotFound(String)

    /// The disk is full - no free sectors available.
    ///
    /// This occurs when trying to write a file but the VTOC shows no
    /// free sectors remaining.
    case diskFull

    /// The directory is full - no free entries available.
    ///
    /// Atari DOS 2.x supports a maximum of 64 files (8 sectors × 8 entries).
    /// This error occurs when all directory entries are in use.
    case directoryFull

    /// The filename is invalid (wrong length, illegal characters, etc.).
    ///
    /// Atari filenames must be 1-8 characters for the name and 0-3 for
    /// the extension. Only uppercase letters, numbers, and some symbols
    /// are allowed.
    ///
    /// - Parameters:
    ///   - filename: The invalid filename.
    ///   - reason: Why the filename is invalid.
    case invalidFilename(filename: String, reason: String)

    /// A file with this name already exists.
    ///
    /// - Parameter filename: The duplicate filename.
    case fileExists(String)

    /// The file is locked (read-only).
    ///
    /// Locked files cannot be deleted or overwritten without first unlocking.
    ///
    /// - Parameter filename: The locked filename.
    case fileLocked(String)

    /// The file chain is corrupted (circular link, invalid sector, etc.).
    ///
    /// This occurs when following a file's sector chain and encountering
    /// an invalid link - pointing to a non-data sector, creating a loop,
    /// or pointing beyond the disk boundary.
    ///
    /// - Parameters:
    ///   - filename: The affected filename.
    ///   - reason: What corruption was detected.
    case fileChainCorrupted(filename: String, reason: String)

    // =========================================================================
    // MARK: - VTOC Errors
    // =========================================================================

    /// The VTOC (Volume Table of Contents) is invalid or corrupted.
    ///
    /// The VTOC at sector 360 contains the free sector bitmap. If it's
    /// missing or corrupted, the filesystem cannot function properly.
    ///
    /// - Parameter reason: What's wrong with the VTOC.
    case invalidVTOC(String)

    /// The VTOC bitmap doesn't match the actual sector usage.
    ///
    /// This is a consistency warning - the bitmap says sectors are free/used
    /// but following file chains shows otherwise. In lenient mode, the
    /// file chain takes precedence.
    ///
    /// - Parameter details: Description of the mismatch.
    case vtocInconsistent(String)

    // =========================================================================
    // MARK: - I/O Errors
    // =========================================================================

    /// Failed to read the ATR file from disk.
    ///
    /// - Parameter reason: The underlying file system error description.
    case readFailed(String)

    /// Failed to write the ATR file to disk.
    ///
    /// - Parameter reason: The underlying file system error description.
    case writeFailed(String)

    /// The disk image is read-only.
    ///
    /// This occurs when trying to write to a disk that was opened read-only
    /// or is on read-only media.
    case readOnly

    // =========================================================================
    // MARK: - Unsupported Format Errors
    // =========================================================================

    /// The disk format is not supported.
    ///
    /// This occurs for disk types we can read but not fully support,
    /// like quad density (double-sided) disks.
    ///
    /// - Parameter format: Description of the unsupported format.
    case unsupportedFormat(String)

    /// The DOS variant is not supported.
    ///
    /// We support DOS 2.0, 2.5, and compatible variants. Other DOSes
    /// (MyDOS, SpartaDOS, etc.) may have different directory formats.
    ///
    /// - Parameter dosCode: The DOS code byte from the VTOC.
    case unsupportedDOS(Int)

    // =========================================================================
    // MARK: - LocalizedError Implementation
    // =========================================================================

    /// Human-readable error description for display to users.
    ///
    /// These messages are designed to be informative and actionable,
    /// helping users understand what went wrong and how to fix it.
    public var errorDescription: String? {
        switch self {
        // Format errors
        case .invalidMagic:
            return "Not a valid ATR disk image (invalid magic bytes)"
        case .headerTooShort:
            return "ATR file header is incomplete (file may be truncated)"
        case .invalidSectorSize(let size):
            return "Invalid sector size \(size) (expected 128 or 256)"
        case .sizeMismatch(let expected, let actual):
            return "Disk size mismatch: header says \(expected) bytes but file has \(actual) bytes"
        case .corrupted(let reason):
            return "Disk image corrupted: \(reason)"

        // Sector errors
        case .sectorOutOfRange(let sector, let maxSector):
            return "Sector \(sector) is out of range (valid: 1-\(maxSector))"
        case .sectorReadError(let reason):
            return "Sector read error: \(reason)"

        // DOS filesystem errors
        case .fileNotFound(let filename):
            return "File not found: '\(filename)'"
        case .diskFull:
            return "Disk is full - no free sectors available"
        case .directoryFull:
            return "Directory is full - maximum 64 files"
        case .invalidFilename(let filename, let reason):
            return "Invalid filename '\(filename)': \(reason)"
        case .fileExists(let filename):
            return "File '\(filename)' already exists"
        case .fileLocked(let filename):
            return "File '\(filename)' is locked (read-only)"
        case .fileChainCorrupted(let filename, let reason):
            return "File '\(filename)' has corrupted sector chain: \(reason)"

        // VTOC errors
        case .invalidVTOC(let reason):
            return "Invalid VTOC: \(reason)"
        case .vtocInconsistent(let details):
            return "VTOC bitmap inconsistent: \(details)"

        // I/O errors
        case .readFailed(let reason):
            return "Failed to read disk image: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write disk image: \(reason)"
        case .readOnly:
            return "Disk image is read-only"

        // Unsupported format errors
        case .unsupportedFormat(let format):
            return "Unsupported disk format: \(format)"
        case .unsupportedDOS(let dosCode):
            return "Unsupported DOS variant (code: \(dosCode))"
        }
    }

    /// Suggestion for how to resolve the error, if applicable.
    public var recoverySuggestion: String? {
        switch self {
        case .invalidMagic, .headerTooShort:
            return "Ensure the file is a valid ATR disk image."
        case .sizeMismatch:
            return "The disk image may be truncated. Try obtaining a fresh copy."
        case .fileNotFound(let filename):
            return "Check the filename spelling. Use 'dir' to list available files."
        case .fileLocked:
            return "Use 'unlock' command to remove the read-only flag."
        case .diskFull:
            return "Delete some files to free up space."
        case .directoryFull:
            return "Delete some files to free up directory entries."
        default:
            return nil
        }
    }
}

// =============================================================================
// MARK: - Validation Mode
// =============================================================================

/// Controls how strictly ATR files are validated.
///
/// When working with old disk images that may have minor corruption,
/// lenient mode allows recovery attempts instead of failing outright.
public enum ATRValidationMode: Sendable {
    /// Strict validation - any error throws immediately.
    ///
    /// Use this mode when you need guaranteed data integrity,
    /// or when working with disks you created yourself.
    case strict

    /// Lenient validation - attempt to recover from minor errors.
    ///
    /// Use this mode when working with old disk images that may have
    /// minor corruption. Warnings are logged but don't cause failures.
    /// The parser will make best-effort attempts to read damaged data.
    case lenient
}
