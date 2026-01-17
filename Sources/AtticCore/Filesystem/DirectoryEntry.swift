// =============================================================================
// DirectoryEntry.swift - Atari DOS Directory Entry Structure
// =============================================================================
//
// This file defines the DirectoryEntry structure that represents a single file
// entry in an Atari DOS directory. The directory occupies sectors 361-368
// (8 sectors × 8 entries = 64 files maximum).
//
// Directory Entry Format (16 bytes):
// ===================================
//
//   Offset  Size  Description
//   ------  ----  -----------
//   0       1     Flags byte
//   1       2     Sector count (little-endian)
//   3       2     Starting sector (little-endian)
//   5       8     Filename (ASCII, space-padded)
//   13      3     Extension (ASCII, space-padded)
//
// Flag Byte Bits:
// ---------------
//   Bit 7: Entry in use (1 = active file, 0 with other bits = deleted)
//   Bit 6: File is open for write
//   Bit 5: DOS 2.5 extended file (uses sectors 721+)
//   Bit 4-2: Reserved
//   Bit 1: File is locked (read-only)
//   Bit 0: Entry never used (virgin slot)
//
// Common Flag Values:
// -------------------
//   $00 - Entry never used
//   $42 - Normal file in use
//   $43 - Normal file in use, locked
//   $46 - File open for write
//   $62 - DOS 2.5 extended file in use
//   $80 - Deleted file
//
// Filename Format:
// ----------------
// Atari filenames follow the 8.3 convention:
// - 1-8 character filename (uppercase A-Z, 0-9, and some symbols)
// - 0-3 character extension
// - Names are space-padded to fill the full 8+3 characters
// - Case is not significant (always stored uppercase)
//
// Usage Example:
//
//     let entry = DirectoryEntry(bytes: sectorData[0..<16])
//     if entry.isInUse {
//         print("Found file: \(entry.fullName) (\(entry.sectorCount) sectors)")
//     }
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Directory Entry Flags
// =============================================================================

/// Flags that describe the state of a directory entry.
///
/// These flags are stored in the first byte of each directory entry.
/// Multiple flags can be combined (e.g., in use + locked).
public struct DirectoryEntryFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    // =========================================================================
    // MARK: - Flag Definitions
    // =========================================================================

    /// Entry is in use (contains a valid file).
    ///
    /// When clear along with other flags, indicates a deleted file.
    public static let inUse = DirectoryEntryFlags(rawValue: 0x80)

    /// File is currently open for writing.
    ///
    /// This flag is set when a file is opened for write and cleared
    /// when the file is closed. If set on a closed disk, indicates
    /// the file may be incomplete or corrupted.
    public static let openForWrite = DirectoryEntryFlags(rawValue: 0x40)

    /// DOS 2.5 extended file flag.
    ///
    /// Indicates the file may use sectors in the extended area (721-1040).
    /// This flag was added in DOS 2.5 for enhanced density support.
    public static let dos25Extended = DirectoryEntryFlags(rawValue: 0x20)

    /// File is locked (read-only).
    ///
    /// Locked files cannot be deleted or overwritten without
    /// first unlocking them.
    public static let locked = DirectoryEntryFlags(rawValue: 0x02)

    /// Entry has never been used.
    ///
    /// A freshly formatted disk has all entries marked as never used.
    /// Once used (even if later deleted), this flag is cleared.
    public static let neverUsed = DirectoryEntryFlags(rawValue: 0x01)

    // =========================================================================
    // MARK: - Common Combinations
    // =========================================================================

    /// A normal active file (in use, not locked).
    public static let normalFile: DirectoryEntryFlags = [.inUse, .locked.complement]

    /// A locked active file.
    public static let lockedFile: DirectoryEntryFlags = [.inUse, .locked]

    /// A deleted file marker.
    ///
    /// Note: Deleted files have 0x80 as the flag byte (only inUse clear,
    /// but the byte value is 0x80). This is a quirk of Atari DOS.
    public static let deleted = DirectoryEntryFlags(rawValue: 0x80)

    // =========================================================================
    // MARK: - Helper for Complement
    // =========================================================================

    /// Returns the bitwise complement of these flags.
    public var complement: DirectoryEntryFlags {
        DirectoryEntryFlags(rawValue: ~rawValue)
    }
}

// =============================================================================
// MARK: - Directory Entry Structure
// =============================================================================

/// Represents a single file entry in the Atari DOS directory.
///
/// Each directory entry is 16 bytes and contains the file's metadata:
/// flags, sector count, starting sector, and 8.3 filename.
///
/// The directory can hold up to 64 files (8 sectors × 8 entries per sector).
public struct DirectoryEntry: Sendable, Equatable {

    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// The size of a directory entry in bytes.
    public static let entrySize = 16

    /// Maximum filename length (not including extension).
    public static let maxFilenameLength = 8

    /// Maximum extension length.
    public static let maxExtensionLength = 3

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The raw flags byte for this entry.
    public let flags: UInt8

    /// The number of sectors used by this file.
    ///
    /// This includes all data sectors in the file's chain.
    public let sectorCount: UInt16

    /// The first sector number of the file's sector chain.
    ///
    /// Follow the sector links from here to read the entire file.
    public let startSector: UInt16

    /// The filename (up to 8 characters, space-padded).
    ///
    /// This is the raw value from the directory; use `trimmedFilename`
    /// to get the actual filename without padding.
    public let filename: String

    /// The file extension (up to 3 characters, space-padded).
    ///
    /// This is the raw value from the directory; use `trimmedExtension`
    /// to get the actual extension without padding.
    public let fileExtension: String

    /// The directory entry index (0-63) where this entry was found.
    ///
    /// This is set when the entry is read from the directory, and is
    /// used as the file ID in sector links.
    public let entryIndex: Int

    // =========================================================================
    // MARK: - Computed Properties (Flags)
    // =========================================================================

    /// The flags as an OptionSet for easier checking.
    public var flagsSet: DirectoryEntryFlags {
        DirectoryEntryFlags(rawValue: flags)
    }

    /// Returns true if this entry contains an active (non-deleted) file.
    ///
    /// An entry is in use if:
    /// - The inUse flag (bit 7) is set, OR
    /// - The entry is marked as open for write (bit 6)
    /// AND the entry is not marked as never used (bit 0).
    public var isInUse: Bool {
        // An entry is in use if bit 7 is set OR bit 6 is set,
        // AND it's not a "never used" entry
        let hasContent = (flags & 0x40) != 0  // Open for write
        let isActive = (flags & 0x80) != 0 && (flags != 0x80)  // In use and not deleted
        return (isActive || hasContent) && !isNeverUsed
    }

    /// Returns true if this entry represents a deleted file.
    ///
    /// Deleted entries have exactly 0x80 as the flags byte (only the
    /// high bit set, indicating the entry was once in use).
    public var isDeleted: Bool {
        flags == 0x80
    }

    /// Returns true if this entry has never been used.
    ///
    /// Never-used entries have flags = 0x00, indicating a virgin slot
    /// on a freshly formatted disk.
    public var isNeverUsed: Bool {
        flags == 0x00 || (flags & 0x01) != 0
    }

    /// Returns true if the file is locked (read-only).
    public var isLocked: Bool {
        (flags & 0x02) != 0
    }

    /// Returns true if the file is currently open for writing.
    ///
    /// If this flag is set on a disk that's not in use, the file may
    /// be incomplete or corrupted.
    public var isOpenForWrite: Bool {
        (flags & 0x40) != 0
    }

    /// Returns true if this is a DOS 2.5 extended file.
    ///
    /// Extended files may use sectors in the 721-1040 range.
    public var isDOS25Extended: Bool {
        (flags & 0x20) != 0
    }

    // =========================================================================
    // MARK: - Computed Properties (Filename)
    // =========================================================================

    /// The filename with trailing spaces removed.
    public var trimmedFilename: String {
        filename.trimmingCharacters(in: .whitespaces)
    }

    /// The extension with trailing spaces removed.
    public var trimmedExtension: String {
        fileExtension.trimmingCharacters(in: .whitespaces)
    }

    /// The complete filename with extension (e.g., "GAME.BAS").
    ///
    /// If there's no extension, returns just the filename.
    public var fullName: String {
        let name = trimmedFilename
        let ext = trimmedExtension
        if ext.isEmpty {
            return name
        }
        return "\(name).\(ext)"
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a DirectoryEntry by parsing 16 bytes of raw directory data.
    ///
    /// - Parameters:
    ///   - bytes: A 16-byte array containing the raw directory entry.
    ///   - entryIndex: The position of this entry in the directory (0-63).
    ///
    /// Usage:
    ///
    ///     let sectorData = disk.readSector(361)  // First directory sector
    ///     for i in 0..<8 {
    ///         let entryBytes = Array(sectorData[i*16..<(i+1)*16])
    ///         let entry = DirectoryEntry(bytes: entryBytes, entryIndex: i)
    ///         if entry.isInUse {
    ///             print(entry.fullName)
    ///         }
    ///     }
    ///
    public init(bytes: [UInt8], entryIndex: Int = 0) {
        // Ensure we have at least 16 bytes
        let safeBytes = bytes.count >= 16 ? bytes : bytes + Array(repeating: 0, count: 16 - bytes.count)

        self.flags = safeBytes[0]
        self.sectorCount = UInt16(safeBytes[1]) | (UInt16(safeBytes[2]) << 8)
        self.startSector = UInt16(safeBytes[3]) | (UInt16(safeBytes[4]) << 8)

        // Parse filename (bytes 5-12, 8 characters)
        let filenameBytes = Array(safeBytes[5..<13])
        self.filename = String(bytes: filenameBytes, encoding: .ascii)?
            .replacingOccurrences(of: "\0", with: " ") ?? "        "

        // Parse extension (bytes 13-15, 3 characters)
        let extBytes = Array(safeBytes[13..<16])
        self.fileExtension = String(bytes: extBytes, encoding: .ascii)?
            .replacingOccurrences(of: "\0", with: " ") ?? "   "

        self.entryIndex = entryIndex
    }

    /// Creates a DirectoryEntry with explicit values.
    ///
    /// Used when creating new files or modifying existing entries.
    ///
    /// - Parameters:
    ///   - flags: The flags byte.
    ///   - sectorCount: Number of sectors used.
    ///   - startSector: First sector of the file.
    ///   - filename: The filename (will be padded/truncated to 8 chars).
    ///   - fileExtension: The extension (will be padded/truncated to 3 chars).
    ///   - entryIndex: The directory entry index.
    public init(
        flags: UInt8,
        sectorCount: UInt16,
        startSector: UInt16,
        filename: String,
        fileExtension: String,
        entryIndex: Int = 0
    ) {
        self.flags = flags
        self.sectorCount = sectorCount
        self.startSector = startSector
        self.entryIndex = entryIndex

        // Pad filename to 8 characters
        let paddedName = filename.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
        self.filename = String(paddedName.prefix(8))

        // Pad extension to 3 characters
        let paddedExt = fileExtension.uppercased().padding(toLength: 3, withPad: " ", startingAt: 0)
        self.fileExtension = String(paddedExt.prefix(3))
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Encodes the directory entry into 16 bytes for writing.
    ///
    /// - Returns: A 16-byte array containing the encoded entry.
    ///
    /// Usage:
    ///
    ///     let entry = DirectoryEntry(flags: 0x42, sectorCount: 5, ...)
    ///     let bytes = entry.encode()
    ///     // Write bytes to directory sector
    ///
    public func encode() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)

        // Byte 0: Flags
        bytes[0] = flags

        // Bytes 1-2: Sector count (little-endian)
        bytes[1] = UInt8(sectorCount & 0xFF)
        bytes[2] = UInt8((sectorCount >> 8) & 0xFF)

        // Bytes 3-4: Start sector (little-endian)
        bytes[3] = UInt8(startSector & 0xFF)
        bytes[4] = UInt8((startSector >> 8) & 0xFF)

        // Bytes 5-12: Filename
        let filenameBytes = Array(filename.utf8)
        for i in 0..<8 {
            bytes[5 + i] = i < filenameBytes.count ? filenameBytes[i] : 0x20  // Space padding
        }

        // Bytes 13-15: Extension
        let extBytes = Array(fileExtension.utf8)
        for i in 0..<3 {
            bytes[13 + i] = i < extBytes.count ? extBytes[i] : 0x20  // Space padding
        }

        return bytes
    }

    // =========================================================================
    // MARK: - Filename Validation
    // =========================================================================

    /// Validates a filename for Atari DOS compatibility.
    ///
    /// - Parameters:
    ///   - name: The filename to validate (without extension).
    ///   - ext: The extension to validate.
    /// - Returns: An error message if invalid, nil if valid.
    ///
    /// Valid Atari filenames:
    /// - 1-8 characters for filename
    /// - 0-3 characters for extension
    /// - Uppercase letters A-Z, digits 0-9
    /// - Some special characters (implementation may vary by DOS)
    public static func validateFilename(_ name: String, extension ext: String) -> String? {
        // Check filename length
        if name.isEmpty {
            return "Filename cannot be empty"
        }
        if name.count > maxFilenameLength {
            return "Filename too long (max \(maxFilenameLength) characters)"
        }

        // Check extension length
        if ext.count > maxExtensionLength {
            return "Extension too long (max \(maxExtensionLength) characters)"
        }

        // Check for valid characters (letters, digits, underscore)
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let nameChars = CharacterSet(charactersIn: name.uppercased())
        let extChars = CharacterSet(charactersIn: ext.uppercased())

        if !nameChars.isSubset(of: validChars) {
            return "Filename contains invalid characters (use A-Z, 0-9, _)"
        }
        if !ext.isEmpty && !extChars.isSubset(of: validChars) {
            return "Extension contains invalid characters (use A-Z, 0-9, _)"
        }

        return nil  // Valid
    }

    /// Parses a full filename string into name and extension components.
    ///
    /// - Parameter fullName: A filename like "GAME.BAS" or "README".
    /// - Returns: A tuple of (name, extension), or nil if invalid.
    ///
    /// Examples:
    ///   "GAME.BAS" → ("GAME", "BAS")
    ///   "README" → ("README", "")
    ///   "A.B.C" → ("A", "B") (only first dot is separator)
    public static func parseFilename(_ fullName: String) -> (name: String, ext: String)? {
        let upper = fullName.uppercased()

        if let dotIndex = upper.firstIndex(of: ".") {
            let name = String(upper[..<dotIndex])
            let ext = String(upper[upper.index(after: dotIndex)...])
            return (name, ext)
        } else {
            return (upper, "")
        }
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension DirectoryEntry: CustomStringConvertible {
    /// A human-readable description of the directory entry.
    public var description: String {
        if isNeverUsed {
            return "DirectoryEntry[\(entryIndex)]: (unused)"
        } else if isDeleted {
            return "DirectoryEntry[\(entryIndex)]: \(fullName) (DELETED)"
        } else {
            var status = isLocked ? " [LOCKED]" : ""
            if isOpenForWrite {
                status += " [OPEN]"
            }
            return "DirectoryEntry[\(entryIndex)]: \(fullName) - \(sectorCount) sectors, start: \(startSector)\(status)"
        }
    }
}

// =============================================================================
// MARK: - Wildcard Matching
// =============================================================================

extension DirectoryEntry {
    /// Checks if the filename matches a wildcard pattern.
    ///
    /// Supports * and ? wildcards in DOS style:
    /// - * matches any sequence of characters
    /// - ? matches any single character
    ///
    /// - Parameter pattern: The pattern to match against (e.g., "*.BAS", "GAME?.*").
    /// - Returns: True if the filename matches the pattern.
    ///
    /// Examples:
    ///   "GAME.BAS".matches("*.BAS") → true
    ///   "GAME1.BAS".matches("GAME?.BAS") → true
    ///   "README.TXT".matches("*.BAS") → false
    public func matchesPattern(_ pattern: String) -> Bool {
        // Parse pattern into name and extension parts
        guard let (patternName, patternExt) = DirectoryEntry.parseFilename(pattern) else {
            return false
        }

        // Match filename part
        if !wildcardMatch(trimmedFilename, pattern: patternName) {
            return false
        }

        // Match extension part
        if !wildcardMatch(trimmedExtension, pattern: patternExt) {
            return false
        }

        return true
    }

    /// Helper function for wildcard matching.
    private func wildcardMatch(_ string: String, pattern: String) -> Bool {
        // Handle empty pattern
        if pattern.isEmpty {
            return string.isEmpty
        }

        // Handle "*" pattern
        if pattern == "*" {
            return true
        }

        var s = string.startIndex
        var p = pattern.startIndex

        while s < string.endIndex && p < pattern.endIndex {
            let patternChar = pattern[p]

            if patternChar == "*" {
                // * matches zero or more characters
                // Try matching the rest of the pattern against the rest of the string
                let restOfPattern = String(pattern[pattern.index(after: p)...])
                for i in s...string.endIndex {
                    let restOfString = String(string[i...])
                    if wildcardMatch(restOfString, pattern: restOfPattern) {
                        return true
                    }
                }
                return false
            } else if patternChar == "?" {
                // ? matches exactly one character
                s = string.index(after: s)
                p = pattern.index(after: p)
            } else if patternChar == string[s] {
                // Exact match
                s = string.index(after: s)
                p = pattern.index(after: p)
            } else {
                // No match
                return false
            }
        }

        // Check if we've consumed both strings
        // Pattern can have trailing * which matches empty string
        while p < pattern.endIndex && pattern[p] == "*" {
            p = pattern.index(after: p)
        }

        return s == string.endIndex && p == pattern.endIndex
    }
}
