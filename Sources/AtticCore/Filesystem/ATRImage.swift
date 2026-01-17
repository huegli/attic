// =============================================================================
// ATRImage.swift - ATR Disk Image Container
// =============================================================================
//
// This file defines the ATRImage class that handles reading and writing
// ATR disk image files. ATR is the standard disk image format for Atari 8-bit
// computers.
//
// ATR File Format:
// ================
// ATR files consist of a 16-byte header followed by sector data:
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │  16-byte Header                                              │
//   ├──────────────────────────────────────────────────────────────┤
//   │  Sector 1 (128 bytes)                                        │
//   ├──────────────────────────────────────────────────────────────┤
//   │  Sector 2 (128 bytes)                                        │
//   ├──────────────────────────────────────────────────────────────┤
//   │  Sector 3 (128 bytes)                                        │
//   ├──────────────────────────────────────────────────────────────┤
//   │  Sector 4+ (128 or 256 bytes depending on density)           │
//   ├──────────────────────────────────────────────────────────────┤
//   │  ...                                                         │
//   └──────────────────────────────────────────────────────────────┘
//
// Header Format (16 bytes):
// =========================
//   Offset  Size  Description
//   ------  ----  -----------
//   0-1     2     Magic number: $96 $02
//   2-3     2     Disk size in paragraphs (low word)
//   4-5     2     Sector size (128 or 256)
//   6       1     Disk size high byte (paragraphs >> 16)
//   7-10    4     CRC (optional, usually 0)
//   11-14   4     Unused
//   15      1     Flags
//
// Important Notes:
// ================
// 1. The first 3 sectors are ALWAYS 128 bytes, even on double-density disks.
//    This is for boot compatibility with the Atari's ROM bootstrap loader.
//
// 2. Sector numbering starts at 1, not 0. Sector 0 does not exist.
//
// 3. Disk size is stored in "paragraphs" (16-byte units), requiring some
//    math to convert to actual byte counts.
//
// Usage Example:
//
//     // Open existing disk image
//     let disk = try ATRImage(url: diskURL)
//     print("Disk type: \(disk.diskType.displayName)")
//
//     // Read a sector
//     let bootSector = disk.readSector(1)
//
//     // Create a new disk image
//     let newDisk = try ATRImage.create(at: newURL, type: .singleDensity)
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - ATR Header Structure
// =============================================================================

/// Represents the 16-byte ATR file header.
///
/// This structure holds the parsed header information from an ATR file.
/// It's primarily used internally by ATRImage for validation and metadata.
public struct ATRHeader: Sendable, Equatable {

    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// The expected magic bytes at the start of an ATR file.
    public static let magic: (UInt8, UInt8) = (0x96, 0x02)

    /// The size of the ATR header in bytes.
    public static let headerSize = 16

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The disk size in paragraphs (16-byte units).
    public let paragraphs: Int

    /// The sector size in bytes (128 or 256).
    public let sectorSize: Int

    /// The CRC value from the header (usually 0).
    public let crc: UInt32

    /// The flags byte from the header.
    public let flags: UInt8

    /// The calculated total disk size in bytes.
    public var diskSize: Int {
        paragraphs * 16
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates an ATRHeader by parsing raw header bytes.
    ///
    /// - Parameter data: At least 16 bytes of header data.
    /// - Throws: ATRError if the header is invalid.
    public init(data: Data) throws {
        guard data.count >= ATRHeader.headerSize else {
            throw ATRError.headerTooShort
        }

        // Validate magic bytes
        guard data[0] == ATRHeader.magic.0 && data[1] == ATRHeader.magic.1 else {
            throw ATRError.invalidMagic
        }

        // Parse paragraphs (bytes 2-3 low word, byte 6 high byte)
        let lowWord = Int(data[2]) | (Int(data[3]) << 8)
        let highByte = Int(data[6]) << 16
        self.paragraphs = lowWord | highByte

        // Parse sector size (bytes 4-5)
        self.sectorSize = Int(data[4]) | (Int(data[5]) << 8)

        // Validate sector size
        guard sectorSize == 128 || sectorSize == 256 else {
            throw ATRError.invalidSectorSize(sectorSize)
        }

        // Parse CRC (bytes 7-10)
        self.crc = UInt32(data[7]) |
                   (UInt32(data[8]) << 8) |
                   (UInt32(data[9]) << 16) |
                   (UInt32(data[10]) << 24)

        // Parse flags (byte 15)
        self.flags = data[15]
    }

    /// Creates an ATRHeader for a new disk.
    ///
    /// - Parameter diskType: The type of disk to create a header for.
    public init(diskType: DiskType) {
        self.paragraphs = diskType.paragraphs
        self.sectorSize = diskType.sectorSize
        self.crc = 0
        self.flags = 0
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Encodes the header into 16 bytes for writing.
    ///
    /// - Returns: A 16-byte Data containing the encoded header.
    public func encode() -> Data {
        var data = Data(count: ATRHeader.headerSize)

        // Magic bytes
        data[0] = ATRHeader.magic.0
        data[1] = ATRHeader.magic.1

        // Paragraphs (low word in bytes 2-3, high byte in byte 6)
        data[2] = UInt8(paragraphs & 0xFF)
        data[3] = UInt8((paragraphs >> 8) & 0xFF)
        data[6] = UInt8((paragraphs >> 16) & 0xFF)

        // Sector size
        data[4] = UInt8(sectorSize & 0xFF)
        data[5] = UInt8((sectorSize >> 8) & 0xFF)

        // CRC
        data[7] = UInt8(crc & 0xFF)
        data[8] = UInt8((crc >> 8) & 0xFF)
        data[9] = UInt8((crc >> 16) & 0xFF)
        data[10] = UInt8((crc >> 24) & 0xFF)

        // Unused (bytes 11-14) - already zeroed

        // Flags
        data[15] = flags

        return data
    }
}

// =============================================================================
// MARK: - ATR Image Class
// =============================================================================

/// Represents an ATR disk image file.
///
/// ATRImage provides low-level access to ATR disk images, handling the
/// container format (header parsing, sector offset calculations) while
/// leaving filesystem interpretation to ATRFileSystem.
///
/// This class is designed for read-only operations in Phase 12.
/// Write support will be added in future phases.
///
/// Thread Safety:
/// This class is NOT thread-safe. If you need concurrent access,
/// synchronize externally or use actor isolation.
public final class ATRImage: @unchecked Sendable {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The URL of the ATR file (nil for in-memory images).
    public let url: URL?

    /// The parsed ATR header.
    public let header: ATRHeader

    /// The detected disk type.
    public let diskType: DiskType

    /// The total number of sectors on the disk.
    public let sectorCount: Int

    /// The sector size in bytes (128 or 256).
    public var sectorSize: Int {
        header.sectorSize
    }

    /// The raw disk image data (header + sectors).
    private var data: Data

    /// Whether the image has been modified since loading.
    public private(set) var isModified: Bool = false

    /// Whether the image is read-only.
    public let isReadOnly: Bool

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Opens an existing ATR disk image from a file.
    ///
    /// - Parameters:
    ///   - url: The URL of the ATR file to open.
    ///   - readOnly: If true, the image cannot be modified.
    ///   - validationMode: How strictly to validate the image.
    /// - Throws: ATRError if the file cannot be opened or is invalid.
    ///
    /// Usage:
    ///
    ///     let disk = try ATRImage(url: diskURL)
    ///     print("Opened \(disk.diskType.displayName) disk")
    ///
    public init(
        url: URL,
        readOnly: Bool = false,
        validationMode: ATRValidationMode = .lenient
    ) throws {
        self.url = url
        self.isReadOnly = readOnly

        // Read file data
        do {
            self.data = try Data(contentsOf: url)
        } catch {
            throw ATRError.readFailed(error.localizedDescription)
        }

        // Parse header
        self.header = try ATRHeader(data: data)

        // Calculate sector count
        let diskSize = header.diskSize
        if header.sectorSize == 256 {
            // First 3 sectors are 128 bytes, rest are 256
            // diskSize = 3*128 + (n-3)*256
            // n = (diskSize - 384) / 256 + 3
            self.sectorCount = (diskSize - 3 * 128) / 256 + 3
        } else {
            self.sectorCount = diskSize / 128
        }

        // Detect disk type
        if let detected = DiskType.detect(sectorSize: header.sectorSize, sectorCount: sectorCount) {
            self.diskType = detected
        } else {
            if validationMode == .strict {
                throw ATRError.unsupportedFormat(
                    "Unknown format: \(sectorCount) sectors × \(header.sectorSize) bytes"
                )
            }
            // Default to single density for unknown formats
            self.diskType = .singleDensity
        }

        // Validate size matches
        let expectedSize = ATRHeader.headerSize + header.diskSize
        if data.count < expectedSize {
            if validationMode == .strict {
                throw ATRError.sizeMismatch(expected: expectedSize, actual: data.count)
            }
            // Pad with zeros for lenient mode
            let padding = Data(count: expectedSize - data.count)
            self.data.append(padding)
        }
    }

    /// Creates an ATR image from raw data (in-memory).
    ///
    /// - Parameters:
    ///   - data: The raw ATR file data.
    ///   - validationMode: How strictly to validate the image.
    /// - Throws: ATRError if the data is invalid.
    public init(data: Data, validationMode: ATRValidationMode = .lenient) throws {
        self.url = nil
        self.isReadOnly = false
        self.data = data

        // Parse header
        self.header = try ATRHeader(data: data)

        // Calculate sector count
        let diskSize = header.diskSize
        if header.sectorSize == 256 {
            self.sectorCount = (diskSize - 3 * 128) / 256 + 3
        } else {
            self.sectorCount = diskSize / 128
        }

        // Detect disk type
        if let detected = DiskType.detect(sectorSize: header.sectorSize, sectorCount: sectorCount) {
            self.diskType = detected
        } else {
            self.diskType = .singleDensity
        }
    }

    // =========================================================================
    // MARK: - Static Factory Methods
    // =========================================================================

    /// Creates a new blank ATR disk image.
    ///
    /// This creates a new, empty (all zeros) disk image file.
    /// Use ATRFileSystem.format() to initialize it with a DOS filesystem.
    ///
    /// - Parameters:
    ///   - url: Where to create the file.
    ///   - type: The disk type to create.
    /// - Returns: The newly created ATRImage.
    /// - Throws: ATRError if creation fails.
    ///
    /// Usage:
    ///
    ///     let disk = try ATRImage.create(at: diskURL, type: .singleDensity)
    ///     try ATRFileSystem.format(disk)  // Optional: initialize DOS filesystem
    ///
    public static func create(at url: URL, type: DiskType) throws -> ATRImage {
        guard type.isCreatable else {
            throw ATRError.unsupportedFormat(
                "\(type.displayName) disks cannot be created (read-only support)"
            )
        }

        // Create header
        let header = ATRHeader(diskType: type)
        var data = header.encode()

        // Add empty sector data
        let sectorData = Data(count: type.totalSize)
        data.append(sectorData)

        // Write to file
        do {
            try data.write(to: url)
        } catch {
            throw ATRError.writeFailed(error.localizedDescription)
        }

        // Return the new image
        return try ATRImage(url: url, readOnly: false)
    }

    /// Creates a new formatted ATR disk image with DOS filesystem.
    ///
    /// This creates a new disk image AND initializes it with a DOS 2.x
    /// filesystem (boot sectors, VTOC, empty directory).
    ///
    /// - Parameters:
    ///   - url: Where to create the file.
    ///   - type: The disk type to create.
    /// - Returns: The newly created and formatted ATRImage.
    /// - Throws: ATRError if creation fails.
    public static func createFormatted(at url: URL, type: DiskType) throws -> ATRImage {
        // Create blank image
        let image = try create(at: url, type: type)

        // Initialize VTOC
        let vtoc = VTOC.createEmpty(for: type)
        try image.writeSector(DOSLayout.vtocSector, data: vtoc.encode())

        // Initialize directory sectors (all zeros is fine - means "never used")
        let emptyDirectory = [UInt8](repeating: 0, count: 128)
        for sector in DOSLayout.firstDirectorySector...DOSLayout.lastDirectorySector {
            try image.writeSector(sector, data: emptyDirectory)
        }

        // Save changes
        try image.save()

        return image
    }

    // =========================================================================
    // MARK: - Sector Access
    // =========================================================================

    /// Calculates the byte offset of a sector within the ATR file.
    ///
    /// This accounts for:
    /// - The 16-byte header
    /// - First 3 sectors always being 128 bytes (even on DD disks)
    ///
    /// - Parameter sector: The sector number (1-based).
    /// - Returns: The byte offset in the file.
    private func sectorOffset(_ sector: Int) -> Int {
        precondition(sector >= 1, "Sector numbers start at 1")

        if header.sectorSize == 128 {
            // All sectors are 128 bytes
            return ATRHeader.headerSize + (sector - 1) * 128
        } else {
            // First 3 sectors are 128 bytes, rest are 256
            if sector <= 3 {
                return ATRHeader.headerSize + (sector - 1) * 128
            } else {
                return ATRHeader.headerSize + 3 * 128 + (sector - 4) * 256
            }
        }
    }

    /// Returns the actual size of a sector in bytes.
    ///
    /// For double-density disks, sectors 1-3 are 128 bytes,
    /// while sectors 4+ are 256 bytes.
    ///
    /// - Parameter sector: The sector number (1-based).
    /// - Returns: The sector size in bytes.
    public func actualSectorSize(_ sector: Int) -> Int {
        if header.sectorSize == 256 && sector > 3 {
            return 256
        }
        return 128
    }

    /// Reads a sector from the disk image.
    ///
    /// - Parameter sector: The sector number to read (1-based).
    /// - Returns: The sector data as a byte array.
    /// - Throws: ATRError if the sector number is invalid.
    ///
    /// Usage:
    ///
    ///     let bootSector = try disk.readSector(1)
    ///     let vtoc = try disk.readSector(360)
    ///
    public func readSector(_ sector: Int) throws -> [UInt8] {
        guard sector >= 1 && sector <= sectorCount else {
            throw ATRError.sectorOutOfRange(sector: sector, maxSector: sectorCount)
        }

        let offset = sectorOffset(sector)
        let size = actualSectorSize(sector)

        // Ensure we have enough data
        guard offset + size <= data.count else {
            throw ATRError.sectorReadError("Sector \(sector) extends beyond file")
        }

        return Array(data[offset..<(offset + size)])
    }

    /// Reads multiple consecutive sectors.
    ///
    /// - Parameters:
    ///   - startSector: The first sector to read.
    ///   - count: The number of sectors to read.
    /// - Returns: An array of sector data arrays.
    /// - Throws: ATRError if any sector is invalid.
    public func readSectors(_ startSector: Int, count: Int) throws -> [[UInt8]] {
        var sectors: [[UInt8]] = []
        for i in 0..<count {
            sectors.append(try readSector(startSector + i))
        }
        return sectors
    }

    /// Writes a sector to the disk image.
    ///
    /// The data is padded or truncated to match the sector size.
    ///
    /// - Parameters:
    ///   - sector: The sector number to write (1-based).
    ///   - sectorData: The data to write.
    /// - Throws: ATRError if the image is read-only or sector invalid.
    public func writeSector(_ sector: Int, data sectorData: [UInt8]) throws {
        guard !isReadOnly else {
            throw ATRError.readOnly
        }

        guard sector >= 1 && sector <= sectorCount else {
            throw ATRError.sectorOutOfRange(sector: sector, maxSector: sectorCount)
        }

        let offset = sectorOffset(sector)
        let size = actualSectorSize(sector)

        // Prepare data (pad or truncate to sector size)
        var writeData = sectorData
        if writeData.count < size {
            writeData.append(contentsOf: [UInt8](repeating: 0, count: size - writeData.count))
        } else if writeData.count > size {
            writeData = Array(writeData.prefix(size))
        }

        // Write to data buffer
        data.replaceSubrange(offset..<(offset + size), with: writeData)
        isModified = true
    }

    // =========================================================================
    // MARK: - File Operations
    // =========================================================================

    /// Saves changes to the disk image file.
    ///
    /// - Throws: ATRError if save fails or no URL is set.
    public func save() throws {
        guard let url = url else {
            throw ATRError.writeFailed("No URL set for in-memory image")
        }

        guard !isReadOnly else {
            throw ATRError.readOnly
        }

        do {
            try data.write(to: url)
            isModified = false
        } catch {
            throw ATRError.writeFailed(error.localizedDescription)
        }
    }

    /// Saves the disk image to a new location.
    ///
    /// - Parameter newURL: The new file location.
    /// - Returns: A new ATRImage for the saved file.
    /// - Throws: ATRError if save fails.
    public func saveAs(_ newURL: URL) throws -> ATRImage {
        do {
            try data.write(to: newURL)
        } catch {
            throw ATRError.writeFailed(error.localizedDescription)
        }

        return try ATRImage(url: newURL, readOnly: false)
    }

    /// Returns the raw image data.
    ///
    /// - Returns: The complete ATR file data (header + sectors).
    public func getRawData() -> Data {
        return data
    }

    // =========================================================================
    // MARK: - Disk Information
    // =========================================================================

    /// Returns a summary of the disk image.
    public var summary: String {
        var lines: [String] = []

        if let url = url {
            lines.append("File: \(url.lastPathComponent)")
        } else {
            lines.append("File: (in-memory)")
        }

        lines.append("Type: \(diskType.displayName)")
        lines.append("Sectors: \(sectorCount)")
        lines.append("Sector Size: \(sectorSize) bytes")
        lines.append("Total Size: \(data.count) bytes")

        if isModified {
            lines.append("Status: Modified (unsaved)")
        } else if isReadOnly {
            lines.append("Status: Read-only")
        } else {
            lines.append("Status: OK")
        }

        return lines.joined(separator: "\n")
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension ATRImage: CustomStringConvertible {
    /// A human-readable description of the disk image.
    public var description: String {
        let name = url?.lastPathComponent ?? "(memory)"
        return "ATRImage(\(name), \(diskType.shortName), \(sectorCount) sectors)"
    }
}
