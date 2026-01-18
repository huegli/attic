// =============================================================================
// ATRFileSystem.swift - Atari DOS File System Operations
// =============================================================================
//
// This file provides high-level file system operations for Atari DOS disks.
// It sits on top of ATRImage (which handles the container format) and provides
// directory listing, file reading, and other DOS-level operations.
//
// DOS 2.x Filesystem Structure:
// =============================
//
//   ┌─────────────────────────────────────────────────────────────────────┐
//   │  Sectors 1-3: Boot sectors (executable boot code)                   │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  Sectors 4-359: Data sectors (first batch)                          │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  Sector 360: VTOC (Volume Table of Contents - free sector bitmap)   │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  Sectors 361-368: Directory (8 sectors × 8 entries = 64 files max)  │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  Sectors 369-720: Data sectors (second batch)                       │
//   ├─────────────────────────────────────────────────────────────────────┤
//   │  Sectors 721-1040: Extended data (DOS 2.5 enhanced density only)    │
//   └─────────────────────────────────────────────────────────────────────┘
//
// File Storage:
// =============
// Files are stored as linked lists of sectors. Each data sector ends with
// 3 bytes of link information pointing to the next sector (or indicating
// this is the last sector).
//
// Phase 12 Implementation:
// ========================
// This phase implements read-only operations:
// - Directory listing
// - File reading
// - Disk information
// - Validation and recovery
//
// Write operations (create file, delete, format) will be added in later phases.
//
// Usage Example:
//
//     let disk = try ATRImage(url: diskURL)
//     let fs = try ATRFileSystem(disk: disk)
//
//     // List all files
//     for entry in try fs.listDirectory() {
//         print("\(entry.fullName) - \(entry.sectorCount) sectors")
//     }
//
//     // Read a file
//     let data = try fs.readFile("GAME.BAS")
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - File Info Structure
// =============================================================================

/// Information about a file on an Atari disk.
///
/// This structure combines directory entry information with additional
/// computed details for display and processing.
public struct ATRFileInfo: Sendable, Equatable {

    /// The directory entry for this file.
    public let entry: DirectoryEntry

    /// The actual size of the file in bytes.
    ///
    /// This is calculated by following the sector chain and counting
    /// actual data bytes, not just sector count × sector size.
    public let fileSize: Int

    /// Whether the file appears to be corrupted.
    ///
    /// True if the sector chain has issues (loops, invalid links, etc.)
    public let isCorrupted: Bool

    /// Description of any corruption detected.
    public let corruptionReason: String?

    /// The filename (without extension).
    public var filename: String {
        entry.trimmedFilename
    }

    /// The file extension.
    public var fileExtension: String {
        entry.trimmedExtension
    }

    /// The full filename with extension.
    public var fullName: String {
        entry.fullName
    }

    /// Whether the file is locked (read-only).
    public var isLocked: Bool {
        entry.isLocked
    }

    /// The number of sectors used by this file.
    public var sectorCount: Int {
        Int(entry.sectorCount)
    }

    /// The starting sector number.
    public var startSector: Int {
        Int(entry.startSector)
    }
}

// =============================================================================
// MARK: - Disk Info Structure
// =============================================================================

/// Information about an Atari disk.
public struct ATRDiskInfo: Sendable {
    /// The disk type (single, enhanced, double density).
    public let diskType: DiskType

    /// Total number of sectors on the disk.
    public let totalSectors: Int

    /// Number of free sectors available.
    public let freeSectors: Int

    /// Number of used sectors.
    public var usedSectors: Int {
        totalSectors - freeSectors
    }

    /// Number of files on the disk.
    public let fileCount: Int

    /// DOS version string.
    public let dosVersion: String

    /// Whether the VTOC appears valid.
    public let vtocValid: Bool

    /// Any validation warnings.
    public let warnings: [String]

    /// Free space in bytes (approximate).
    ///
    /// Note: This is the raw capacity. Actual usable space per sector
    /// is 3 bytes less due to link bytes.
    public var freeBytes: Int {
        freeSectors * diskType.sectorSize
    }

    /// Free space in kilobytes.
    public var freeKB: Double {
        Double(freeBytes) / 1024.0
    }
}

// =============================================================================
// MARK: - ATR File System Class
// =============================================================================

/// Provides high-level file system operations for Atari DOS disks.
///
/// ATRFileSystem interprets the DOS 2.x filesystem structure stored in
/// an ATR disk image, providing operations like directory listing and
/// file reading.
///
/// This class is currently read-only. Write operations will be added
/// in future implementation phases.
public final class ATRFileSystem: @unchecked Sendable {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The underlying ATR disk image.
    public let disk: ATRImage

    /// The parsed VTOC.
    private var vtoc: VTOC

    /// Cached directory entries.
    private var directoryCache: [DirectoryEntry]?

    /// Validation mode for error handling.
    public let validationMode: ATRValidationMode

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a filesystem interface for an ATR disk image.
    ///
    /// - Parameters:
    ///   - disk: The ATR disk image to operate on.
    ///   - validationMode: How strictly to validate filesystem structures.
    /// - Throws: ATRError if the disk doesn't contain a valid DOS filesystem.
    ///
    /// Usage:
    ///
    ///     let disk = try ATRImage(url: diskURL)
    ///     let fs = try ATRFileSystem(disk: disk)
    ///
    public init(disk: ATRImage, validationMode: ATRValidationMode = .lenient) throws {
        self.disk = disk
        self.validationMode = validationMode

        // Read and parse VTOC
        let vtocData = try disk.readSector(DOSLayout.vtocSector)
        self.vtoc = try VTOC(data: vtocData, diskType: disk.diskType, validationMode: validationMode)
    }

    // =========================================================================
    // MARK: - Directory Operations
    // =========================================================================

    /// Lists all files in the directory.
    ///
    /// - Parameter includeDeleted: If true, also returns deleted entries.
    /// - Returns: An array of directory entries.
    /// - Throws: ATRError if the directory cannot be read.
    ///
    /// Usage:
    ///
    ///     let files = try fs.listDirectory()
    ///     for file in files {
    ///         print("\(file.fullName) - \(file.sectorCount) sectors")
    ///     }
    ///
    public func listDirectory(includeDeleted: Bool = false) throws -> [DirectoryEntry] {
        // Return cached if available
        if let cached = directoryCache, !includeDeleted {
            return cached.filter { $0.isInUse }
        }

        var entries: [DirectoryEntry] = []
        var entryIndex = 0

        // Read all 8 directory sectors
        for sector in DOSLayout.firstDirectorySector...DOSLayout.lastDirectorySector {
            let sectorData = try disk.readSector(sector)

            // Each sector has 8 entries of 16 bytes each
            for i in 0..<DOSLayout.entriesPerSector {
                let offset = i * DirectoryEntry.entrySize
                guard offset + DirectoryEntry.entrySize <= sectorData.count else { continue }

                let entryBytes = Array(sectorData[offset..<(offset + DirectoryEntry.entrySize)])
                let entry = DirectoryEntry(bytes: entryBytes, entryIndex: entryIndex)

                // Stop at first "never used" entry (optimization)
                if entry.isNeverUsed && !includeDeleted {
                    directoryCache = entries
                    return entries
                }

                if entry.isInUse || (includeDeleted && entry.isDeleted) {
                    entries.append(entry)
                }

                entryIndex += 1
            }
        }

        directoryCache = entries.filter { $0.isInUse }
        return includeDeleted ? entries : directoryCache!
    }

    /// Lists files matching a wildcard pattern.
    ///
    /// - Parameter pattern: Wildcard pattern (e.g., "*.BAS", "GAME?.*").
    /// - Returns: Matching directory entries.
    /// - Throws: ATRError if the directory cannot be read.
    public func listFiles(matching pattern: String) throws -> [DirectoryEntry] {
        try listDirectory().filter { $0.matchesPattern(pattern) }
    }

    /// Finds a file by name.
    ///
    /// - Parameter name: The filename to find (e.g., "GAME.BAS").
    /// - Returns: The directory entry if found.
    /// - Throws: ATRError.fileNotFound if the file doesn't exist.
    public func findFile(_ name: String) throws -> DirectoryEntry {
        guard let (searchName, searchExt) = DirectoryEntry.parseFilename(name) else {
            throw ATRError.invalidFilename(filename: name, reason: "Cannot parse filename")
        }

        for entry in try listDirectory() {
            if entry.trimmedFilename.uppercased() == searchName.uppercased() &&
               entry.trimmedExtension.uppercased() == searchExt.uppercased() {
                return entry
            }
        }

        throw ATRError.fileNotFound(name)
    }

    /// Gets detailed information about a file.
    ///
    /// - Parameter name: The filename to get info for.
    /// - Returns: Detailed file information.
    /// - Throws: ATRError if the file is not found.
    public func getFileInfo(_ name: String) throws -> ATRFileInfo {
        let entry = try findFile(name)
        return try getFileInfo(entry)
    }

    /// Gets detailed information about a directory entry.
    ///
    /// - Parameter entry: The directory entry to analyze.
    /// - Returns: Detailed file information.
    /// - Throws: ATRError if the file chain cannot be read.
    public func getFileInfo(_ entry: DirectoryEntry) throws -> ATRFileInfo {
        // Follow sector chain to calculate actual file size
        var totalBytes = 0
        var sector = Int(entry.startSector)
        var sectorsVisited: Set<Int> = []
        var isCorrupted = false
        var corruptionReason: String?
        var sectorIndex = 0
        let expectedSectorCount = Int(entry.sectorCount)

        let maxIterations = disk.sectorCount  // Prevent infinite loops

        while sector != 0 && sectorsVisited.count < maxIterations {
            // Check for loops
            if sectorsVisited.contains(sector) {
                isCorrupted = true
                corruptionReason = "Circular sector chain at sector \(sector)"
                break
            }
            sectorsVisited.insert(sector)

            // Validate sector number
            guard sector >= 1 && sector <= disk.sectorCount else {
                isCorrupted = true
                corruptionReason = "Invalid sector number \(sector) in chain"
                break
            }

            // Read sector and parse link
            do {
                let sectorData = try disk.readSector(sector)
                let sectorSize = disk.actualSectorSize(sector)

                // Determine if this is the last sector based on directory entry's sector count
                sectorIndex += 1
                let isKnownLast = (sectorIndex == expectedSectorCount)
                let link = SectorLink(sectorData: sectorData, sectorSize: sectorSize, isKnownLastSector: isKnownLast)

                totalBytes += link.bytesInSector
                sector = Int(link.nextSector)
            } catch {
                isCorrupted = true
                corruptionReason = "Cannot read sector \(sector): \(error.localizedDescription)"
                break
            }
        }

        return ATRFileInfo(
            entry: entry,
            fileSize: totalBytes,
            isCorrupted: isCorrupted,
            corruptionReason: corruptionReason
        )
    }

    // =========================================================================
    // MARK: - File Reading
    // =========================================================================

    /// Reads the contents of a file.
    ///
    /// - Parameter name: The filename to read.
    /// - Returns: The file data.
    /// - Throws: ATRError if the file cannot be read.
    ///
    /// Usage:
    ///
    ///     let data = try fs.readFile("GAME.BAS")
    ///     print("File size: \(data.count) bytes")
    ///
    public func readFile(_ name: String) throws -> Data {
        let entry = try findFile(name)
        return try readFile(entry)
    }

    /// Reads the contents of a file from its directory entry.
    ///
    /// - Parameter entry: The directory entry for the file.
    /// - Returns: The file data.
    /// - Throws: ATRError if the file cannot be read.
    public func readFile(_ entry: DirectoryEntry) throws -> Data {
        var data = Data()
        var sector = Int(entry.startSector)
        var sectorsVisited: Set<Int> = []
        let maxIterations = disk.sectorCount
        var sectorIndex = 0
        let expectedSectorCount = Int(entry.sectorCount)

        while sector != 0 && sectorsVisited.count < maxIterations {
            // Check for loops
            if sectorsVisited.contains(sector) {
                throw ATRError.fileChainCorrupted(
                    filename: entry.fullName,
                    reason: "Circular chain at sector \(sector)"
                )
            }
            sectorsVisited.insert(sector)

            // Validate sector
            guard sector >= 1 && sector <= disk.sectorCount else {
                throw ATRError.fileChainCorrupted(
                    filename: entry.fullName,
                    reason: "Invalid sector \(sector)"
                )
            }

            // Read sector
            let sectorData = try disk.readSector(sector)
            let sectorSize = disk.actualSectorSize(sector)

            // Determine if this is the last sector based on directory entry's sector count
            sectorIndex += 1
            let isKnownLast = (sectorIndex == expectedSectorCount)
            let link = SectorLink(sectorData: sectorData, sectorSize: sectorSize, isKnownLastSector: isKnownLast)

            // Validate file ID
            if validationMode == .strict && link.fileID != entry.entryIndex {
                throw ATRError.fileChainCorrupted(
                    filename: entry.fullName,
                    reason: "Sector \(sector) belongs to file \(link.fileID), not \(entry.entryIndex)"
                )
            }

            // Append data bytes
            let dataBytes = sectorData.prefix(link.bytesInSector)
            data.append(contentsOf: dataBytes)

            // Move to next sector
            sector = Int(link.nextSector)
        }

        return data
    }

    /// Reads a file as a string (assuming ATASCII encoding).
    ///
    /// - Parameters:
    ///   - name: The filename to read.
    ///   - convertLineEndings: If true, convert ATASCII EOL ($9B) to Unix newline.
    /// - Returns: The file contents as a string.
    /// - Throws: ATRError if the file cannot be read.
    public func readFileAsString(_ name: String, convertLineEndings: Bool = true) throws -> String {
        var data = try readFile(name)

        if convertLineEndings {
            // Convert ATASCII EOL ($9B) to Unix newline ($0A)
            data = Data(data.map { $0 == 0x9B ? 0x0A : $0 })
        }

        // Try to decode as ASCII/Latin1 (ATASCII is mostly ASCII-compatible)
        guard let string = String(data: data, encoding: .isoLatin1) else {
            throw ATRError.sectorReadError("Cannot decode file as text")
        }

        return string
    }

    /// Returns the list of sectors used by a file.
    ///
    /// - Parameter entry: The directory entry for the file.
    /// - Returns: An array of sector numbers in chain order.
    /// - Throws: ATRError if the chain cannot be followed.
    public func getFileSectors(_ entry: DirectoryEntry) throws -> [Int] {
        var sectors: [Int] = []
        var sector = Int(entry.startSector)
        var sectorsVisited: Set<Int> = []
        let expectedSectorCount = Int(entry.sectorCount)

        while sector != 0 && sectorsVisited.count < disk.sectorCount {
            if sectorsVisited.contains(sector) {
                break  // Loop detected
            }
            sectorsVisited.insert(sector)
            sectors.append(sector)

            guard sector >= 1 && sector <= disk.sectorCount else {
                break  // Invalid sector
            }

            let sectorData = try disk.readSector(sector)
            let sectorSize = disk.actualSectorSize(sector)

            // Determine if this is the last sector based on directory entry's sector count
            let isKnownLast = (sectors.count == expectedSectorCount)
            let link = SectorLink(sectorData: sectorData, sectorSize: sectorSize, isKnownLastSector: isKnownLast)

            sector = Int(link.nextSector)
        }

        return sectors
    }

    // =========================================================================
    // MARK: - Disk Information
    // =========================================================================

    /// Gets information about the disk.
    ///
    /// - Returns: Disk information structure.
    public func getDiskInfo() throws -> ATRDiskInfo {
        let files = try listDirectory()
        let warnings = vtoc.validate()

        let dosVersion: String
        switch vtoc.dosCode {
        case 0: dosVersion = "DOS 2.0"
        case 2: dosVersion = "DOS 2.5"
        default: dosVersion = "Unknown (code \(vtoc.dosCode))"
        }

        return ATRDiskInfo(
            diskType: disk.diskType,
            totalSectors: disk.sectorCount,
            freeSectors: vtoc.countFreeSectors(),
            fileCount: files.count,
            dosVersion: dosVersion,
            vtocValid: warnings.isEmpty,
            warnings: warnings
        )
    }

    /// Refreshes the VTOC from disk.
    ///
    /// Call this if the disk may have been modified externally.
    public func refreshVTOC() throws {
        let vtocData = try disk.readSector(DOSLayout.vtocSector)
        self.vtoc = try VTOC(data: vtocData, diskType: disk.diskType, validationMode: validationMode)
        self.directoryCache = nil
    }

    /// Returns the VTOC.
    public func getVTOC() -> VTOC {
        vtoc
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    /// Validates the entire filesystem.
    ///
    /// Checks:
    /// - VTOC integrity
    /// - Directory entries
    /// - File sector chains
    /// - Free sector bitmap consistency
    ///
    /// - Returns: A list of issues found, empty if valid.
    public func validate() throws -> [String] {
        var issues: [String] = []

        // Validate VTOC
        issues.append(contentsOf: vtoc.validate())

        // Validate directory entries and file chains
        let entries = try listDirectory()

        var usedSectors: Set<Int> = []

        // Mark system sectors as used
        for s in 1...3 { usedSectors.insert(s) }
        usedSectors.insert(DOSLayout.vtocSector)
        for s in DOSLayout.firstDirectorySector...DOSLayout.lastDirectorySector {
            usedSectors.insert(s)
        }

        // Check each file
        for entry in entries {
            do {
                let fileSectors = try getFileSectors(entry)

                // Check for conflicts
                for sector in fileSectors {
                    if usedSectors.contains(sector) {
                        issues.append("Sector \(sector) used by multiple files (including \(entry.fullName))")
                    }
                    usedSectors.insert(sector)

                    // Check VTOC agrees
                    if vtoc.isSectorFree(sector) {
                        issues.append("File \(entry.fullName) uses sector \(sector) marked as free in VTOC")
                    }
                }

                // Check sector count matches
                if fileSectors.count != Int(entry.sectorCount) {
                    issues.append("File \(entry.fullName): directory says \(entry.sectorCount) sectors, chain has \(fileSectors.count)")
                }

            } catch {
                issues.append("File \(entry.fullName): \(error.localizedDescription)")
            }
        }

        // Check for allocated sectors not in any file
        for sector in vtoc.getUsedSectors() {
            if !usedSectors.contains(sector) && DOSLayout.isDataSector(sector, totalSectors: disk.sectorCount) {
                issues.append("Sector \(sector) marked used in VTOC but not in any file (orphan)")
            }
        }

        return issues
    }

    // =========================================================================
    // MARK: - Formatting (for creating new disks)
    // =========================================================================

    /// Formats the disk with an empty DOS 2.x filesystem.
    ///
    /// This initializes:
    /// - Boot sectors (minimal)
    /// - VTOC with free sector bitmap
    /// - Empty directory
    ///
    /// WARNING: This erases all data on the disk!
    ///
    /// - Throws: ATRError if the disk is read-only.
    public func format() throws {
        guard !disk.isReadOnly else {
            throw ATRError.readOnly
        }

        // Clear all sectors (optional, but cleaner)
        let emptySector = [UInt8](repeating: 0, count: 128)
        let emptyDDSector = [UInt8](repeating: 0, count: 256)

        for sector in 1...disk.sectorCount {
            let sectorData = disk.actualSectorSize(sector) == 128 ? emptySector : emptyDDSector
            try disk.writeSector(sector, data: sectorData)
        }

        // Write VTOC
        let newVTOC = VTOC.createEmpty(for: disk.diskType)
        try disk.writeSector(DOSLayout.vtocSector, data: newVTOC.encode())

        // Refresh our VTOC copy
        try refreshVTOC()
    }

    // =========================================================================
    // MARK: - Export to Host
    // =========================================================================

    /// Exports a file from the disk to the host filesystem.
    ///
    /// - Parameters:
    ///   - name: The filename on the Atari disk.
    ///   - destinationURL: Where to save the file on the host.
    ///   - convertLineEndings: If true and file appears to be text, convert ATASCII EOL.
    /// - Throws: ATRError or file system errors.
    public func exportFile(
        _ name: String,
        to destinationURL: URL,
        convertLineEndings: Bool = false
    ) throws {
        var data = try readFile(name)

        if convertLineEndings {
            // Convert ATASCII EOL ($9B) to Unix newline ($0A)
            data = Data(data.map { $0 == 0x9B ? 0x0A : $0 })
        }

        try data.write(to: destinationURL)
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension ATRFileSystem: CustomStringConvertible {
    /// A human-readable description of the filesystem.
    public var description: String {
        let info = try? getDiskInfo()
        let fileCount = info?.fileCount ?? 0
        let free = info?.freeSectors ?? 0

        return "ATRFileSystem(\(disk.diskType.shortName), \(fileCount) files, \(free) free sectors)"
    }
}

// =============================================================================
// MARK: - ATRFileInfo Extension
// =============================================================================

extension ATRFileInfo: CustomStringConvertible {
    /// A human-readable description of the file.
    public var description: String {
        var result = "\(fullName.padding(toLength: 12, withPad: " ", startingAt: 0)) \(sectorCount) sectors"
        if isLocked {
            result += " [LOCKED]"
        }
        if isCorrupted {
            result += " [CORRUPTED]"
        }
        return result
    }

    /// A detailed description for the `info` command.
    public var detailedDescription: String {
        var lines: [String] = []
        lines.append("Filename: \(fullName)")
        lines.append("Size: \(sectorCount) sectors (\(fileSize) bytes)")
        lines.append("Start sector: \(startSector)")

        var flags: [String] = []
        if isLocked { flags.append("Locked") }
        if entry.isOpenForWrite { flags.append("Open for write") }
        if entry.isDOS25Extended { flags.append("DOS 2.5 extended") }
        if isCorrupted { flags.append("CORRUPTED") }

        lines.append("Flags: \(flags.isEmpty ? "Normal" : flags.joined(separator: ", "))")

        if let reason = corruptionReason {
            lines.append("Corruption: \(reason)")
        }

        return lines.joined(separator: "\n")
    }
}
