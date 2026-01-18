// =============================================================================
// AtariFileSystem.swift - DOS 2.x File System Operations
// =============================================================================
//
// This file implements the Atari DOS 2.x file system format used on ATR disk
// images. It provides operations for reading and manipulating files stored
// in the standard DOS 2.x format.
//
// DOS 2.x Disk Layout (Single Density):
// - Sectors 1-3: Boot sectors
// - Sectors 4-359: Data area (first half)
// - Sector 360: VTOC (Volume Table of Contents)
// - Sectors 361-368: Directory (8 sectors, 64 entries max)
// - Sectors 369-720: Data area (second half)
//
// Key Structures:
// - VTOC: Contains disk info and sector allocation bitmap
// - Directory Entry: 16 bytes per file (name, extension, flags, sectors)
// - Sector Link: Last 3 bytes of each data sector link to next sector
//
// Usage:
//
//     let disk = try ATRImage(url: diskURL)
//     let fs = AtariFileSystem(disk: disk)
//
//     // List files
//     let files = try fs.listDirectory()
//     for file in files {
//         print("\(file.fullName) - \(file.sectorCount) sectors")
//     }
//
//     // Read a file
//     let data = try fs.readFile(named: "GAME.COM")
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - File System Error Types
// =============================================================================

/// Errors that can occur during file system operations.
public enum FileSystemError: Error, LocalizedError, Sendable {
    /// The specified file was not found in the directory.
    case fileNotFound(String)

    /// A file with the specified name already exists.
    case fileExists(String)

    /// The directory is full (64 entries maximum).
    case directoryFull

    /// The disk does not have enough free sectors for the operation.
    case diskFull(required: Int, available: Int)

    /// The file is locked (read-only) and cannot be modified.
    case fileLocked(String)

    /// The filename is invalid (too long, invalid characters, etc.).
    case invalidFilename(String)

    /// The VTOC (Volume Table of Contents) is corrupt or invalid.
    case invalidVTOC

    /// The file's sector chain is corrupt.
    case corruptFileChain(String)

    /// Cannot delete or modify a file that is open for writing.
    case fileInUse(String)

    /// The pattern is invalid for wildcard matching.
    case invalidPattern(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "File not found: '\(name)'"
        case .fileExists(let name):
            return "File already exists: '\(name)'"
        case .directoryFull:
            return "Directory full (maximum 64 files)"
        case .diskFull(let required, let available):
            return "Disk full: need \(required) sectors, only \(available) available"
        case .fileLocked(let name):
            return "File '\(name)' is locked"
        case .invalidFilename(let reason):
            return "Invalid filename: \(reason)"
        case .invalidVTOC:
            return "Invalid or corrupt VTOC"
        case .corruptFileChain(let name):
            return "Corrupt file chain for '\(name)'"
        case .fileInUse(let name):
            return "File '\(name)' is open for writing"
        case .invalidPattern(let pattern):
            return "Invalid pattern: '\(pattern)'"
        }
    }
}

// =============================================================================
// MARK: - Directory Entry Flags
// =============================================================================

/// Flags byte interpretation for directory entries.
///
/// The flags byte (byte 0 of each directory entry) indicates the file status:
/// - Bit 7: Entry in use (1) or deleted (0, but entry was used before)
/// - Bit 6: File is open for write
/// - Bit 5: DOS 2.5 extended directory
/// - Bit 1: File is locked (read-only)
/// - Bit 0: Entry never used
public struct DirectoryFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Entry is currently in use (not deleted).
    public static let inUse = DirectoryFlags(rawValue: 0x40)

    /// File is open for writing.
    public static let openForWrite = DirectoryFlags(rawValue: 0x20)

    /// DOS 2.5 extended directory entry.
    public static let extended = DirectoryFlags(rawValue: 0x10)

    /// File is locked (read-only).
    public static let locked = DirectoryFlags(rawValue: 0x02)

    /// Entry has never been used.
    public static let neverUsed = DirectoryFlags(rawValue: 0x01)

    /// Common flag combinations
    public static let normalFile: UInt8 = 0x42     // In use, not locked
    public static let lockedFile: UInt8 = 0x43    // In use, locked
    public static let deletedFile: UInt8 = 0x80   // Deleted
    public static let unusedEntry: UInt8 = 0x00   // Never used
}

// =============================================================================
// MARK: - Directory Entry Structure
// =============================================================================

/// Represents a single directory entry in the Atari DOS 2.x file system.
///
/// Each directory entry is 16 bytes:
/// - Byte 0: Flags (status and attributes)
/// - Bytes 1-2: Sector count (little-endian)
/// - Bytes 3-4: Starting sector (little-endian)
/// - Bytes 5-12: Filename (8 characters, space-padded)
/// - Bytes 13-15: Extension (3 characters, space-padded)
///
/// Example directory entry for "GAME.COM":
/// ```
/// 42 1C 00 2D 00 47 41 4D  45 20 20 20 43 4F 4D
/// ││ └──┘  └──┘  └───────────────┘  └───────┘
/// ││  │     │         GAME           COM
/// ││  │     └─ Start sector: $002D (45)
/// ││  └─────── Sector count: $001C (28)
/// │└────────── In use, not locked (0x42)
/// ```
public struct DirectoryEntry: Sendable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Raw flags byte indicating file status and attributes.
    public var flags: UInt8

    /// Number of sectors used by this file.
    public var sectorCount: UInt16

    /// First sector of the file's data chain.
    public var startSector: UInt16

    /// Filename without extension (up to 8 characters, space-padded).
    public var filename: String

    /// File extension (up to 3 characters, space-padded).
    public var ext: String

    /// The directory entry index (0-63) for this entry, if known.
    public var entryIndex: Int?

    // =========================================================================
    // MARK: - Computed Properties
    // =========================================================================

    /// Whether this entry is currently in use (not deleted).
    public var isInUse: Bool {
        // Entry is in use if bit 6 is set (0x40) and it's not a deleted entry (0x80)
        (flags & 0x40) != 0 || flags == 0x42 || flags == 0x43
    }

    /// Whether this entry has been deleted.
    public var isDeleted: Bool {
        flags == 0x80
    }

    /// Whether this file is locked (read-only).
    public var isLocked: Bool {
        (flags & 0x02) != 0
    }

    /// Whether this entry has never been used.
    public var neverUsed: Bool {
        flags == 0x00 || (flags & 0x01) != 0
    }

    /// Whether the file is currently open for writing.
    public var isOpenForWrite: Bool {
        (flags & 0x20) != 0
    }

    /// The full filename with extension (e.g., "GAME.COM").
    public var fullName: String {
        let trimmedName = filename.trimmingCharacters(in: .whitespaces)
        let trimmedExt = ext.trimmingCharacters(in: .whitespaces)
        if trimmedExt.isEmpty {
            return trimmedName
        }
        return "\(trimmedName).\(trimmedExt)"
    }

    /// Estimated file size in bytes based on sector count and data bytes per sector.
    ///
    /// Note: This is an estimate because the last sector may not be full.
    /// For accurate size, you need to read the file and check the last sector's
    /// byte count field.
    public func estimatedSize(sectorSize: Int) -> Int {
        let dataPerSector = sectorSize - 3  // 3 bytes reserved for link info
        return Int(sectorCount) * dataPerSector
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a directory entry from raw bytes.
    ///
    /// - Parameters:
    ///   - bytes: 16 bytes of directory entry data.
    ///   - index: The entry index (0-63) in the directory, if known.
    public init(bytes: [UInt8], index: Int? = nil) {
        precondition(bytes.count >= 16, "Directory entry must be at least 16 bytes")

        self.flags = bytes[0]
        self.sectorCount = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        self.startSector = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)

        // Decode filename (bytes 5-12) as ASCII
        // The Atari uses ATASCII which is similar to ASCII for basic characters
        self.filename = String(bytes: bytes[5..<13], encoding: .ascii)?
            .replacingOccurrences(of: "\0", with: " ") ?? "????????"

        // Decode extension (bytes 13-15)
        self.ext = String(bytes: bytes[13..<16], encoding: .ascii)?
            .replacingOccurrences(of: "\0", with: " ") ?? "???"

        self.entryIndex = index
    }

    /// Creates a new directory entry with the specified values.
    ///
    /// - Parameters:
    ///   - filename: The filename (will be truncated to 8 chars and uppercased).
    ///   - ext: The extension (will be truncated to 3 chars and uppercased).
    ///   - startSector: The first sector of the file.
    ///   - sectorCount: The number of sectors used.
    ///   - locked: Whether the file should be locked.
    public init(filename: String, ext: String, startSector: UInt16, sectorCount: UInt16, locked: Bool = false) {
        self.flags = locked ? DirectoryFlags.lockedFile : DirectoryFlags.normalFile
        self.sectorCount = sectorCount
        self.startSector = startSector

        // Normalize and pad filename
        let normalizedName = filename.uppercased()
            .prefix(8)
            .padding(toLength: 8, withPad: " ", startingAt: 0)
        self.filename = String(normalizedName)

        // Normalize and pad extension
        let normalizedExt = ext.uppercased()
            .prefix(3)
            .padding(toLength: 3, withPad: " ", startingAt: 0)
        self.ext = String(normalizedExt)

        self.entryIndex = nil
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Encodes this directory entry to 16 bytes.
    ///
    /// - Returns: 16-byte array representing this directory entry.
    public func encode() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)

        bytes[0] = flags
        bytes[1] = UInt8(sectorCount & 0xFF)
        bytes[2] = UInt8((sectorCount >> 8) & 0xFF)
        bytes[3] = UInt8(startSector & 0xFF)
        bytes[4] = UInt8((startSector >> 8) & 0xFF)

        // Encode filename (pad with spaces to 8 chars)
        let nameBytes = Array(filename.padding(toLength: 8, withPad: " ", startingAt: 0).utf8)
        for i in 0..<min(8, nameBytes.count) {
            bytes[5 + i] = nameBytes[i]
        }

        // Encode extension (pad with spaces to 3 chars)
        let extBytes = Array(ext.padding(toLength: 3, withPad: " ", startingAt: 0).utf8)
        for i in 0..<min(3, extBytes.count) {
            bytes[13 + i] = extBytes[i]
        }

        return bytes
    }
}

// =============================================================================
// MARK: - Sector Link Structure
// =============================================================================

/// Represents the 3-byte link at the end of each data sector.
///
/// Each data sector reserves 3 bytes at the end for linking:
/// - 128-byte sectors: bytes 125-127
/// - 256-byte sectors: bytes 253-255
///
/// Format:
/// - Byte 0: File ID (bits 7-2) + Next sector high bits (bits 1-0)
/// - Byte 1: Next sector low byte (or bytes in last sector if next = 0)
/// - Byte 2: Always 0
public struct SectorLink: Sendable {
    /// The file ID (matches the directory entry index).
    public let fileID: UInt8

    /// The next sector in the chain (0 if this is the last sector).
    public let nextSector: UInt16

    /// Whether this is the last sector in the file.
    public let isLast: Bool

    /// Number of valid data bytes in this sector.
    public let bytesInSector: Int

    /// Creates a sector link from the raw bytes at the end of a sector.
    ///
    /// - Parameters:
    ///   - bytes: The sector data (full sector).
    ///   - sectorSize: The sector size (128 or 256).
    public init(bytes: [UInt8], sectorSize: Int) {
        precondition(bytes.count >= sectorSize, "Sector data too small")

        let linkOffset = sectorSize - 3

        // File ID is in the upper 6 bits of byte 0
        self.fileID = bytes[linkOffset] >> 2

        // Next sector is the lower 2 bits of byte 0 (high) + byte 1 (low)
        let nextHigh = UInt16(bytes[linkOffset] & 0x03) << 8
        let nextLow = UInt16(bytes[linkOffset + 1])
        let next = nextHigh | nextLow

        if next == 0 {
            // Last sector - byte 1 contains the count of valid bytes
            self.isLast = true
            self.nextSector = 0
            self.bytesInSector = Int(bytes[linkOffset + 1])
            // Handle edge case where byte count is 0 (means full sector)
            // This is a quirk of DOS 2.x
        } else {
            self.isLast = false
            self.nextSector = next
            self.bytesInSector = sectorSize - 3  // Full data portion
        }
    }

    /// Encodes this sector link to 3 bytes.
    ///
    /// - Parameters:
    ///   - fileID: The file ID (directory entry index).
    ///   - nextSector: The next sector (0 for last sector).
    ///   - bytesInLastSector: For last sector, the number of valid bytes.
    /// - Returns: 3-byte array for the sector link.
    public static func encode(fileID: Int, nextSector: UInt16, bytesInLastSector: Int = 0) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 3)

        if nextSector == 0 {
            // Last sector
            bytes[0] = UInt8((fileID & 0x3F) << 2)
            bytes[1] = UInt8(bytesInLastSector & 0xFF)
        } else {
            // Not last sector
            bytes[0] = UInt8((fileID & 0x3F) << 2) | UInt8((nextSector >> 8) & 0x03)
            bytes[1] = UInt8(nextSector & 0xFF)
        }
        bytes[2] = 0

        return bytes
    }
}

// =============================================================================
// MARK: - VTOC Structure
// =============================================================================

/// Represents the Volume Table of Contents (VTOC) at sector 360.
///
/// The VTOC contains:
/// - DOS version code
/// - Total and free sector counts
/// - Bitmap of sector allocation
public struct VTOC: Sendable {
    /// DOS version code (0 = DOS 2.0, 2 = DOS 2.5).
    public var dosCode: UInt8

    /// Total number of data sectors on the disk.
    public var totalSectors: UInt16

    /// Number of free (unallocated) sectors.
    public var freeSectors: UInt16

    /// Bitmap of sector allocation (1 = free, 0 = used).
    /// Stored starting at byte offset 10 in the VTOC.
    public var bitmap: [UInt8]

    /// The raw VTOC sector data.
    private var rawData: [UInt8]

    /// VTOC sector number (always 360 for DOS 2.x).
    public static let sectorNumber = 360

    /// Directory sector range (361-368).
    public static let directorySectors = 361...368

    /// Creates a VTOC from raw sector data.
    ///
    /// - Parameter bytes: The VTOC sector data (128 bytes).
    public init(bytes: [UInt8]) {
        precondition(bytes.count >= 128, "VTOC must be at least 128 bytes")

        self.rawData = Array(bytes)

        self.dosCode = bytes[0]
        self.totalSectors = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        self.freeSectors = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)

        // Bitmap starts at byte 10, covers 90 bytes (720 sectors)
        // For enhanced density, additional bytes at 100-127 cover sectors 720-1023
        self.bitmap = Array(bytes[10...])
    }

    /// Checks if a sector is free (unallocated).
    ///
    /// - Parameter sector: The sector number to check.
    /// - Returns: True if the sector is free.
    public func isSectorFree(_ sector: Int) -> Bool {
        let byteIndex = sector / 8
        let bitIndex = 7 - (sector % 8)
        guard byteIndex < bitmap.count else { return false }
        return (bitmap[byteIndex] & (1 << bitIndex)) != 0
    }

    /// Marks a sector as used (allocated).
    ///
    /// - Parameter sector: The sector number to mark.
    public mutating func setSectorUsed(_ sector: Int) {
        let byteIndex = sector / 8
        let bitIndex = 7 - (sector % 8)
        guard byteIndex < bitmap.count else { return }
        bitmap[byteIndex] &= ~(1 << bitIndex)
        rawData[10 + byteIndex] = bitmap[byteIndex]

        // Update free sector count
        if freeSectors > 0 {
            freeSectors -= 1
            rawData[3] = UInt8(freeSectors & 0xFF)
            rawData[4] = UInt8((freeSectors >> 8) & 0xFF)
        }
    }

    /// Marks a sector as free (unallocated).
    ///
    /// - Parameter sector: The sector number to mark.
    public mutating func setSectorFree(_ sector: Int) {
        let byteIndex = sector / 8
        let bitIndex = 7 - (sector % 8)
        guard byteIndex < bitmap.count else { return }
        bitmap[byteIndex] |= (1 << bitIndex)
        rawData[10 + byteIndex] = bitmap[byteIndex]

        // Update free sector count
        freeSectors += 1
        rawData[3] = UInt8(freeSectors & 0xFF)
        rawData[4] = UInt8((freeSectors >> 8) & 0xFF)
    }

    /// Finds and allocates the specified number of free sectors.
    ///
    /// - Parameter count: Number of sectors to allocate.
    /// - Returns: Array of allocated sector numbers, or nil if not enough space.
    public mutating func allocateSectors(_ count: Int) -> [UInt16]? {
        guard count <= Int(freeSectors) else { return nil }

        var allocated: [UInt16] = []
        var remaining = count

        // Skip boot sectors (1-3), VTOC (360), and directory (361-368)
        let reservedSectors: Set<Int> = Set(1...3).union([360]).union(Set(361...368))

        for sector in 4..<(4 + bitmap.count * 8) {
            guard remaining > 0 else { break }
            guard !reservedSectors.contains(sector) else { continue }

            if isSectorFree(sector) {
                setSectorUsed(sector)
                allocated.append(UInt16(sector))
                remaining -= 1
            }
        }

        return allocated.count == count ? allocated : nil
    }

    /// Encodes this VTOC to 128 bytes.
    ///
    /// - Returns: 128-byte array representing this VTOC.
    public func encode() -> [UInt8] {
        return rawData
    }

    /// Creates an initialized VTOC for a new disk.
    ///
    /// - Parameter diskType: The type of disk being formatted.
    /// - Returns: An initialized VTOC.
    public static func createEmpty(for diskType: ATRDiskType) -> VTOC {
        var bytes = [UInt8](repeating: 0, count: 128)

        // DOS version code (2 = DOS 2.5)
        bytes[0] = 2

        // Total sectors
        let total = UInt16(diskType.sectorCount)
        bytes[1] = UInt8(total & 0xFF)
        bytes[2] = UInt8((total >> 8) & 0xFF)

        // Calculate free sectors (total - boot(3) - vtoc(1) - directory(8))
        let free = total - 3 - 1 - 8
        bytes[3] = UInt8(free & 0xFF)
        bytes[4] = UInt8((free >> 8) & 0xFF)

        // Initialize bitmap - all sectors free initially
        for i in 10..<100 {
            bytes[i] = 0xFF
        }

        // For enhanced density, also initialize bytes 100-127
        if diskType == .enhancedDensity {
            for i in 100..<128 {
                bytes[i] = 0xFF
            }
        }

        var vtoc = VTOC(bytes: bytes)

        // Mark boot sectors (1-3) as used
        for sector in 1...3 {
            vtoc.setSectorUsed(sector)
        }

        // Mark VTOC (360) as used
        vtoc.setSectorUsed(360)

        // Mark directory sectors (361-368) as used
        for sector in 361...368 {
            vtoc.setSectorUsed(sector)
        }

        // Recalculate free sectors (the setSectorUsed calls decremented it too much)
        vtoc.freeSectors = free
        vtoc.rawData[3] = UInt8(free & 0xFF)
        vtoc.rawData[4] = UInt8((free >> 8) & 0xFF)

        return vtoc
    }
}

// =============================================================================
// MARK: - Atari File System Class
// =============================================================================

/// Provides DOS 2.x file system operations on an ATR disk image.
///
/// AtariFileSystem interprets the raw sector data in an ATRImage as a
/// DOS 2.x formatted disk, providing high-level operations like:
/// - Directory listing
/// - File reading and writing
/// - File deletion, renaming, locking
/// - Disk formatting
///
/// Thread Safety:
/// This class is NOT thread-safe. Access should be synchronized externally.
/// In practice, the DiskManager actor provides this synchronization.
public final class AtariFileSystem: Sendable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The underlying ATR disk image.
    public let disk: ATRImage

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a file system interface for the given ATR disk image.
    ///
    /// - Parameter disk: The ATR disk image to operate on.
    public init(disk: ATRImage) {
        self.disk = disk
    }

    // =========================================================================
    // MARK: - VTOC Operations
    // =========================================================================

    /// Reads the VTOC from the disk.
    ///
    /// - Returns: The VTOC structure.
    /// - Throws: ATRError if the sector cannot be read.
    public func readVTOC() throws -> VTOC {
        let bytes = try disk.readSector(VTOC.sectorNumber)
        return VTOC(bytes: bytes)
    }

    /// Writes the VTOC to the disk.
    ///
    /// - Parameter vtoc: The VTOC to write.
    /// - Throws: ATRError if the sector cannot be written.
    public func writeVTOC(_ vtoc: VTOC) throws {
        try disk.writeSector(VTOC.sectorNumber, data: vtoc.encode())
    }

    // =========================================================================
    // MARK: - Directory Operations
    // =========================================================================

    /// Reads all directory entries from the disk.
    ///
    /// Returns all entries, including deleted ones. Use `isInUse` to filter
    /// for active files.
    ///
    /// - Parameter includeDeleted: Whether to include deleted entries.
    /// - Returns: Array of directory entries with their indices.
    /// - Throws: ATRError if sectors cannot be read.
    public func readDirectory(includeDeleted: Bool = false) throws -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        var entryIndex = 0

        // Read all 8 directory sectors (361-368)
        for sector in VTOC.directorySectors {
            let sectorData = try disk.readSector(sector)

            // Each sector holds 8 entries of 16 bytes each
            for i in 0..<8 {
                let offset = i * 16
                let entryBytes = Array(sectorData[offset..<(offset + 16)])
                var entry = DirectoryEntry(bytes: entryBytes, index: entryIndex)
                entry.entryIndex = entryIndex

                // Skip entries that have never been used
                if !entry.neverUsed {
                    // Include if not deleted, or if includeDeleted is true
                    if entry.isInUse || (includeDeleted && entry.isDeleted) {
                        entries.append(entry)
                    }
                }

                entryIndex += 1
            }
        }

        return entries
    }

    /// Writes a directory entry at the specified index.
    ///
    /// - Parameters:
    ///   - entry: The directory entry to write.
    ///   - index: The entry index (0-63).
    /// - Throws: ATRError if the sector cannot be written.
    public func writeDirectoryEntry(_ entry: DirectoryEntry, at index: Int) throws {
        precondition(index >= 0 && index < 64, "Directory entry index must be 0-63")

        // Calculate which sector and offset within the sector
        let sectorIndex = index / 8  // 0-7
        let entryOffset = (index % 8) * 16
        let sector = 361 + sectorIndex

        // Read the current sector
        var sectorData = try disk.readSector(sector)

        // Replace the entry bytes
        let entryBytes = entry.encode()
        for (i, byte) in entryBytes.enumerated() {
            sectorData[entryOffset + i] = byte
        }

        // Write back
        try disk.writeSector(sector, data: sectorData)
    }

    /// Finds a file by name in the directory.
    ///
    /// - Parameter name: The filename to search for (case-insensitive).
    /// - Returns: The directory entry if found, nil otherwise.
    /// - Throws: ATRError if sectors cannot be read.
    public func findFile(named name: String) throws -> DirectoryEntry? {
        let (searchName, searchExt) = parseFilename(name)
        let entries = try readDirectory()

        return entries.first { entry in
            entry.filename.trimmingCharacters(in: .whitespaces).uppercased() == searchName &&
            entry.ext.trimmingCharacters(in: .whitespaces).uppercased() == searchExt
        }
    }

    /// Finds a free directory entry slot.
    ///
    /// - Returns: The index of a free entry, or nil if directory is full.
    /// - Throws: ATRError if sectors cannot be read.
    public func findFreeDirectoryEntry() throws -> Int? {
        var entryIndex = 0

        for sector in VTOC.directorySectors {
            let sectorData = try disk.readSector(sector)

            for i in 0..<8 {
                let offset = i * 16
                let flags = sectorData[offset]

                // Entry is free if never used (0x00 or bit 0 set) or deleted (0x80)
                if flags == 0x00 || (flags & 0x01) != 0 || flags == 0x80 {
                    return entryIndex
                }

                entryIndex += 1
            }
        }

        return nil  // Directory is full
    }

    /// Lists files matching a wildcard pattern.
    ///
    /// Supports * (match any characters) and ? (match single character).
    ///
    /// - Parameter pattern: The pattern to match (e.g., "*.COM", "GAME?.*").
    /// - Returns: Array of matching directory entries.
    /// - Throws: ATRError or FileSystemError.
    public func listFiles(matching pattern: String? = nil) throws -> [DirectoryEntry] {
        let entries = try readDirectory()

        guard let pattern = pattern, pattern != "*.*" && pattern != "*" else {
            return entries
        }

        return entries.filter { matchesPattern($0.fullName, pattern: pattern) }
    }

    // =========================================================================
    // MARK: - File Operations
    // =========================================================================

    /// Reads a file's contents from the disk.
    ///
    /// Follows the sector chain starting from the directory entry's start sector.
    ///
    /// - Parameter name: The filename to read.
    /// - Returns: The file data.
    /// - Throws: FileSystemError.fileNotFound or ATRError.
    public func readFile(named name: String) throws -> Data {
        guard let entry = try findFile(named: name) else {
            throw FileSystemError.fileNotFound(name)
        }

        return try readFileData(entry: entry)
    }

    /// Reads file data following the sector chain.
    ///
    /// - Parameter entry: The directory entry for the file.
    /// - Returns: The file data.
    /// - Throws: ATRError or FileSystemError if the chain is corrupt.
    public func readFileData(entry: DirectoryEntry) throws -> Data {
        var data = Data()
        var sector = entry.startSector
        var sectorsRead = 0
        let maxSectors = Int(entry.sectorCount) + 10  // Safety margin

        while sector != 0 && sectorsRead < maxSectors {
            let sectorData = try disk.readSector(Int(sector))
            let actualSize = disk.actualSectorSize(Int(sector))
            let link = SectorLink(bytes: sectorData, sectorSize: actualSize)

            // Append data bytes (excluding the 3-byte link)
            let dataBytes = sectorData[0..<link.bytesInSector]
            data.append(contentsOf: dataBytes)

            sector = link.nextSector
            sectorsRead += 1
        }

        if sectorsRead >= maxSectors && sector != 0 {
            throw FileSystemError.corruptFileChain(entry.fullName)
        }

        return data
    }

    /// Gets information about a file.
    ///
    /// - Parameter name: The filename.
    /// - Returns: A dictionary of file information.
    /// - Throws: FileSystemError.fileNotFound or ATRError.
    public func getFileInfo(named name: String) throws -> FileInfo {
        guard let entry = try findFile(named: name) else {
            throw FileSystemError.fileNotFound(name)
        }

        // Read the file to get exact size
        let data = try readFileData(entry: entry)

        return FileInfo(
            name: entry.fullName,
            sectorCount: Int(entry.sectorCount),
            size: data.count,
            startSector: Int(entry.startSector),
            isLocked: entry.isLocked,
            isDeleted: entry.isDeleted
        )
    }

    /// Deletes a file from the disk.
    ///
    /// Frees all sectors used by the file and marks the directory entry as deleted.
    ///
    /// - Parameter name: The filename to delete.
    /// - Throws: FileSystemError if file not found or locked.
    public func deleteFile(named name: String) throws {
        guard let entry = try findFile(named: name) else {
            throw FileSystemError.fileNotFound(name)
        }

        guard !entry.isLocked else {
            throw FileSystemError.fileLocked(name)
        }

        guard !entry.isOpenForWrite else {
            throw FileSystemError.fileInUse(name)
        }

        // Read VTOC to free sectors
        var vtoc = try readVTOC()

        // Free all sectors in the file chain
        var sector = entry.startSector
        var freed = 0

        while sector != 0 {
            let sectorData = try disk.readSector(Int(sector))
            let actualSize = disk.actualSectorSize(Int(sector))
            let link = SectorLink(bytes: sectorData, sectorSize: actualSize)

            vtoc.setSectorFree(Int(sector))
            freed += 1

            sector = link.nextSector
        }

        // Write updated VTOC
        try writeVTOC(vtoc)

        // Mark directory entry as deleted
        guard let entryIndex = entry.entryIndex else {
            throw FileSystemError.fileNotFound(name)
        }

        var deletedEntry = entry
        deletedEntry.flags = DirectoryFlags.deletedFile
        try writeDirectoryEntry(deletedEntry, at: entryIndex)
    }

    /// Renames a file.
    ///
    /// - Parameters:
    ///   - oldName: The current filename.
    ///   - newName: The new filename.
    /// - Throws: FileSystemError if file not found, locked, or new name exists.
    public func renameFile(from oldName: String, to newName: String) throws {
        guard let entry = try findFile(named: oldName) else {
            throw FileSystemError.fileNotFound(oldName)
        }

        guard !entry.isLocked else {
            throw FileSystemError.fileLocked(oldName)
        }

        // Check if new name already exists
        if let _ = try? findFile(named: newName) {
            throw FileSystemError.fileExists(newName)
        }

        // Validate and parse new filename
        let (newFilename, newExt) = parseFilename(newName)
        try validateFilename(newFilename, ext: newExt)

        // Update directory entry
        guard let entryIndex = entry.entryIndex else {
            throw FileSystemError.fileNotFound(oldName)
        }

        var renamedEntry = entry
        renamedEntry.filename = newFilename.padding(toLength: 8, withPad: " ", startingAt: 0)
        renamedEntry.ext = newExt.padding(toLength: 3, withPad: " ", startingAt: 0)
        try writeDirectoryEntry(renamedEntry, at: entryIndex)
    }

    /// Locks a file (makes it read-only).
    ///
    /// - Parameter name: The filename to lock.
    /// - Throws: FileSystemError if file not found.
    public func lockFile(named name: String) throws {
        guard let entry = try findFile(named: name) else {
            throw FileSystemError.fileNotFound(name)
        }

        guard let entryIndex = entry.entryIndex else {
            throw FileSystemError.fileNotFound(name)
        }

        var lockedEntry = entry
        lockedEntry.flags |= 0x02  // Set locked bit
        try writeDirectoryEntry(lockedEntry, at: entryIndex)
    }

    /// Unlocks a file (removes read-only).
    ///
    /// - Parameter name: The filename to unlock.
    /// - Throws: FileSystemError if file not found.
    public func unlockFile(named name: String) throws {
        guard let entry = try findFile(named: name) else {
            throw FileSystemError.fileNotFound(name)
        }

        guard let entryIndex = entry.entryIndex else {
            throw FileSystemError.fileNotFound(name)
        }

        var unlockedEntry = entry
        unlockedEntry.flags &= ~0x02  // Clear locked bit
        try writeDirectoryEntry(unlockedEntry, at: entryIndex)
    }

    // =========================================================================
    // MARK: - Disk Formatting
    // =========================================================================

    /// Formats the disk with an empty DOS 2.x file system.
    ///
    /// WARNING: This erases all data on the disk!
    ///
    /// - Throws: ATRError if sectors cannot be written.
    public func format() throws {
        guard let diskType = disk.diskType else {
            // Use single density as fallback
            try formatWithType(.singleDensity)
            return
        }

        try formatWithType(diskType)
    }

    /// Formats the disk with the specified type.
    private func formatWithType(_ diskType: ATRDiskType) throws {
        // Clear all sectors with zeros
        let emptyData = [UInt8](repeating: 0, count: disk.sectorSize)
        for sector in 1...disk.sectorCount {
            try disk.writeSector(sector, data: emptyData)
        }

        // Initialize VTOC
        let vtoc = VTOC.createEmpty(for: diskType)
        try writeVTOC(vtoc)

        // Initialize directory sectors (already zeros, which is correct)
    }

    // =========================================================================
    // MARK: - Utility Methods
    // =========================================================================

    /// Parses a filename into name and extension components.
    ///
    /// - Parameter fullName: The full filename (e.g., "GAME.COM").
    /// - Returns: Tuple of (name, extension), uppercased.
    private func parseFilename(_ fullName: String) -> (String, String) {
        let upper = fullName.uppercased()
        let parts = upper.split(separator: ".", maxSplits: 1)

        let name = String(parts[0]).prefix(8)
        let ext = parts.count > 1 ? String(parts[1]).prefix(3) : ""

        return (String(name), String(ext))
    }

    /// Validates a filename.
    ///
    /// - Parameters:
    ///   - name: The filename (without extension).
    ///   - ext: The extension.
    /// - Throws: FileSystemError.invalidFilename if invalid.
    private func validateFilename(_ name: String, ext: String) throws {
        guard !name.isEmpty else {
            throw FileSystemError.invalidFilename("Filename cannot be empty")
        }

        guard name.count <= 8 else {
            throw FileSystemError.invalidFilename("Filename too long (max 8 characters)")
        }

        guard ext.count <= 3 else {
            throw FileSystemError.invalidFilename("Extension too long (max 3 characters)")
        }

        // Check for valid characters (letters, numbers, some symbols)
        let validChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard name.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
            throw FileSystemError.invalidFilename("Invalid characters in filename")
        }

        if !ext.isEmpty {
            guard ext.unicodeScalars.allSatisfy({ validChars.contains($0) }) else {
                throw FileSystemError.invalidFilename("Invalid characters in extension")
            }
        }
    }

    /// Checks if a filename matches a wildcard pattern.
    ///
    /// Supports * (any characters) and ? (single character).
    private func matchesPattern(_ filename: String, pattern: String) -> Bool {
        let upperFilename = filename.uppercased()
        let upperPattern = pattern.uppercased()

        // Convert pattern to regex
        var regex = "^"
        for char in upperPattern {
            switch char {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            case ".":
                regex += "\\."
            default:
                regex += String(char)
            }
        }
        regex += "$"

        do {
            let re = try NSRegularExpression(pattern: regex, options: [])
            let range = NSRange(upperFilename.startIndex..., in: upperFilename)
            return re.firstMatch(in: upperFilename, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    /// Returns disk statistics.
    public func getDiskStats() throws -> DiskStats {
        let vtoc = try readVTOC()
        let files = try readDirectory()

        return DiskStats(
            totalSectors: Int(vtoc.totalSectors),
            freeSectors: Int(vtoc.freeSectors),
            usedSectors: Int(vtoc.totalSectors) - Int(vtoc.freeSectors),
            fileCount: files.count,
            diskType: disk.diskType
        )
    }
}

// =============================================================================
// MARK: - Supporting Types
// =============================================================================

/// Information about a single file.
public struct FileInfo: Sendable {
    public let name: String
    public let sectorCount: Int
    public let size: Int
    public let startSector: Int
    public let isLocked: Bool
    public let isDeleted: Bool
}

/// Statistics about a disk.
public struct DiskStats: Sendable {
    public let totalSectors: Int
    public let freeSectors: Int
    public let usedSectors: Int
    public let fileCount: Int
    public let diskType: ATRDiskType?
}
