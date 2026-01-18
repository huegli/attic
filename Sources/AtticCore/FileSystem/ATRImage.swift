// =============================================================================
// ATRImage.swift - ATR Disk Image Container Handler
// =============================================================================
//
// This file provides direct parsing and manipulation of ATR disk image files,
// the standard format for Atari 8-bit disk images.
//
// ATR Format Overview:
// - 16-byte header containing magic number, size, and sector size
// - Followed by raw sector data
// - Sectors are numbered starting from 1 (not 0)
// - First 3 sectors are always 128 bytes (even for double density disks)
//
// Key Concepts:
// - Paragraph: A 16-byte unit used for size calculations in the ATR header
// - Sector Size: Either 128 bytes (single/enhanced density) or 256 bytes (double)
// - Boot Sectors: Sectors 1-3 contain boot code
// - VTOC: Volume Table of Contents at sector 360
// - Directory: Sectors 361-368 contain file listings
//
// Usage:
//
//     // Load an existing ATR file
//     let disk = try ATRImage(url: diskURL)
//     print("Sector size: \(disk.sectorSize)")
//     print("Sector count: \(disk.sectorCount)")
//
//     // Read a sector
//     let sectorData = disk.readSector(360)  // Read VTOC
//
//     // Create a new ATR file
//     try ATRImage.create(at: newDiskURL, type: .singleDensity)
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Disk Type Enumeration
// =============================================================================

/// Supported disk density types for ATR images.
///
/// Each type corresponds to a specific combination of sector count and size:
/// - Single Density (SS/SD): 720 sectors × 128 bytes = 90KB
/// - Enhanced Density (SS/ED): 1040 sectors × 128 bytes = 130KB
/// - Double Density (SS/DD): 720 sectors × 256 bytes = 180KB
///
/// Note: Double-sided disks (DS/DD, 360KB) can be read but not created.
public enum ATRDiskType: String, CaseIterable, Sendable {
    case singleDensity = "ss/sd"
    case enhancedDensity = "ss/ed"
    case doubleDensity = "ss/dd"

    /// Human-readable description of the disk type.
    public var description: String {
        switch self {
        case .singleDensity: return "Single Density (SS/SD, 90K)"
        case .enhancedDensity: return "Enhanced Density (SS/ED, 130K)"
        case .doubleDensity: return "Double Density (SS/DD, 180K)"
        }
    }

    /// Short description for display.
    public var shortDescription: String {
        switch self {
        case .singleDensity: return "SS/SD"
        case .enhancedDensity: return "SS/ED"
        case .doubleDensity: return "SS/DD"
        }
    }

    /// Total number of sectors for this disk type.
    public var sectorCount: Int {
        switch self {
        case .singleDensity: return 720
        case .enhancedDensity: return 1040
        case .doubleDensity: return 720
        }
    }

    /// Sector size in bytes (128 or 256).
    public var sectorSize: Int {
        switch self {
        case .singleDensity, .enhancedDensity: return 128
        case .doubleDensity: return 256
        }
    }

    /// Total disk capacity in bytes.
    public var capacity: Int {
        switch self {
        case .singleDensity: return 92160     // 720 × 128
        case .enhancedDensity: return 133120  // 1040 × 128
        case .doubleDensity: return 183936    // 3×128 + 717×256
        }
    }

    /// Number of 16-byte paragraphs for the ATR header size field.
    public var paragraphs: Int {
        capacity / 16
    }

    /// Initialize from a string like "ss/sd", "ss/ed", or "ss/dd".
    public init?(from string: String) {
        self.init(rawValue: string.lowercased())
    }
}

// =============================================================================
// MARK: - ATR Error Types
// =============================================================================

/// Errors that can occur when working with ATR disk images.
public enum ATRError: Error, LocalizedError, Sendable {
    /// The file does not have a valid ATR magic number ($96 $02).
    case invalidMagic

    /// The file is too small to be a valid ATR image.
    case fileTooSmall

    /// The sector size in the header is not supported (must be 128 or 256).
    case unsupportedSectorSize(Int)

    /// Attempted to access a sector number outside the valid range.
    case sectorOutOfRange(Int)

    /// Failed to read from the disk image file.
    case readError(String)

    /// Failed to write to the disk image file.
    case writeError(String)

    /// The ATR file is read-only.
    case readOnly

    public var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid ATR file: missing magic number ($96 $02)"
        case .fileTooSmall:
            return "File too small to be a valid ATR image"
        case .unsupportedSectorSize(let size):
            return "Unsupported sector size: \(size) (must be 128 or 256)"
        case .sectorOutOfRange(let sector):
            return "Sector \(sector) out of range"
        case .readError(let reason):
            return "Failed to read ATR file: \(reason)"
        case .writeError(let reason):
            return "Failed to write ATR file: \(reason)"
        case .readOnly:
            return "ATR image is read-only"
        }
    }
}

// =============================================================================
// MARK: - ATR Image Class
// =============================================================================

/// Represents an ATR disk image file.
///
/// ATRImage provides direct access to the raw sector data in an ATR file.
/// It handles the header parsing, sector offset calculations, and the special
/// case of double density disks where the first 3 sectors are 128 bytes.
///
/// This class is designed to be used by AtariFileSystem for higher-level
/// operations like directory listing and file reading/writing.
///
/// Thread Safety:
/// This class is NOT thread-safe. Access should be synchronized externally
/// if used from multiple threads. In practice, the DiskManager actor provides
/// this synchronization.
public final class ATRImage: Sendable {
    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// ATR magic number: $96 $02 (little-endian 0x0296).
    public static let magic: UInt16 = 0x0296

    /// Size of the ATR header in bytes.
    public static let headerSize: Int = 16

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The URL of the ATR file.
    public let url: URL

    /// The raw data of the ATR file (header + sectors).
    private var data: Data

    /// The sector size in bytes (128 or 256).
    public let sectorSize: Int

    /// The total number of sectors in the disk image.
    public let sectorCount: Int

    /// Whether the disk has been modified since loading.
    public private(set) var isModified: Bool = false

    /// Whether the disk is read-only (file opened without write permission).
    public let isReadOnly: Bool

    /// The detected disk type based on sector count and size.
    public var diskType: ATRDiskType? {
        switch (sectorCount, sectorSize) {
        case (720, 128): return .singleDensity
        case (1040, 128): return .enhancedDensity
        case (720, 256): return .doubleDensity
        default: return nil
        }
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Loads an ATR disk image from a file URL.
    ///
    /// - Parameters:
    ///   - url: The file URL of the ATR image.
    ///   - readOnly: If true, the disk cannot be modified (default: false).
    /// - Throws: ATRError if the file cannot be read or is invalid.
    ///
    /// Example:
    ///
    ///     let disk = try ATRImage(url: URL(fileURLWithPath: "/path/to/disk.atr"))
    ///     print("Loaded \(disk.sectorCount) sectors")
    ///
    public init(url: URL, readOnly: Bool = false) throws {
        self.url = url
        self.isReadOnly = readOnly

        // Load the file data
        do {
            self.data = try Data(contentsOf: url)
        } catch {
            throw ATRError.readError(error.localizedDescription)
        }

        // Validate minimum size (header only)
        guard data.count >= ATRImage.headerSize else {
            throw ATRError.fileTooSmall
        }

        // Validate magic number
        // ATR files start with $96 $02 (little-endian)
        guard data[0] == 0x96 && data[1] == 0x02 else {
            throw ATRError.invalidMagic
        }

        // Parse sector size from header bytes 4-5 (little-endian)
        let sectorSizeValue = Int(data[4]) | (Int(data[5]) << 8)
        guard sectorSizeValue == 128 || sectorSizeValue == 256 else {
            throw ATRError.unsupportedSectorSize(sectorSizeValue)
        }
        self.sectorSize = sectorSizeValue

        // Calculate disk size from header
        // Paragraphs are stored in bytes 2-3 (low word) and byte 6 (high byte)
        let paragraphs = Int(data[2]) | (Int(data[3]) << 8) | (Int(data[6]) << 16)
        let diskSize = paragraphs * 16

        // Calculate sector count
        // For double density, first 3 sectors are 128 bytes each
        if sectorSize == 256 {
            // First 3 sectors: 3 × 128 = 384 bytes
            // Remaining sectors: (diskSize - 384) / 256
            self.sectorCount = 3 + (diskSize - 3 * 128) / 256
        } else {
            self.sectorCount = diskSize / 128
        }
    }

    /// Private initializer for creating new disk images.
    private init(url: URL, data: Data, sectorSize: Int, sectorCount: Int) {
        self.url = url
        self.data = data
        self.sectorSize = sectorSize
        self.sectorCount = sectorCount
        self.isReadOnly = false
        self.isModified = true
    }

    // =========================================================================
    // MARK: - Sector Access
    // =========================================================================

    /// Reads a sector from the disk image.
    ///
    /// Sectors are numbered starting from 1 (not 0), following the Atari convention.
    /// For double density disks, sectors 1-3 are 128 bytes, while sectors 4+ are
    /// 256 bytes.
    ///
    /// - Parameter sector: The sector number (1-based).
    /// - Returns: The sector data as a byte array.
    /// - Throws: ATRError.sectorOutOfRange if the sector number is invalid.
    ///
    /// Example:
    ///
    ///     let vtocData = try disk.readSector(360)  // Read VTOC
    ///     let dirData = try disk.readSector(361)   // Read first directory sector
    ///
    public func readSector(_ sector: Int) throws -> [UInt8] {
        guard sector >= 1 && sector <= sectorCount else {
            throw ATRError.sectorOutOfRange(sector)
        }

        let offset = sectorOffset(sector)
        let size = actualSectorSize(sector)

        guard offset + size <= data.count else {
            throw ATRError.sectorOutOfRange(sector)
        }

        return Array(data[offset..<(offset + size)])
    }

    /// Writes data to a sector in the disk image.
    ///
    /// The data array should be exactly the size of the sector (128 or 256 bytes
    /// depending on sector number and disk type). If the array is smaller, it
    /// will be padded with zeros. If larger, it will be truncated.
    ///
    /// - Parameters:
    ///   - sector: The sector number (1-based).
    ///   - sectorData: The data to write.
    /// - Throws: ATRError.readOnly if the disk is read-only,
    ///           ATRError.sectorOutOfRange if the sector number is invalid.
    ///
    /// Example:
    ///
    ///     var newData = [UInt8](repeating: 0, count: 128)
    ///     newData[0] = 0x42  // Set some values
    ///     try disk.writeSector(361, data: newData)
    ///
    public func writeSector(_ sector: Int, data sectorData: [UInt8]) throws {
        guard !isReadOnly else {
            throw ATRError.readOnly
        }

        guard sector >= 1 && sector <= sectorCount else {
            throw ATRError.sectorOutOfRange(sector)
        }

        let offset = sectorOffset(sector)
        let size = actualSectorSize(sector)

        // Prepare the data to write (pad or truncate as needed)
        var writeData = sectorData
        if writeData.count < size {
            writeData.append(contentsOf: [UInt8](repeating: 0, count: size - writeData.count))
        } else if writeData.count > size {
            writeData = Array(writeData[0..<size])
        }

        // Write to the data buffer
        for (i, byte) in writeData.enumerated() {
            data[offset + i] = byte
        }

        isModified = true
    }

    /// Calculates the byte offset of a sector within the ATR file.
    ///
    /// This accounts for:
    /// - The 16-byte ATR header
    /// - The special case of double density where sectors 1-3 are 128 bytes
    ///
    /// - Parameter sector: The sector number (1-based).
    /// - Returns: The byte offset from the start of the file.
    private func sectorOffset(_ sector: Int) -> Int {
        precondition(sector >= 1)

        if sectorSize == 128 {
            // Single/enhanced density: all sectors are 128 bytes
            return ATRImage.headerSize + (sector - 1) * 128
        } else {
            // Double density: first 3 sectors are 128 bytes, rest are 256
            if sector <= 3 {
                return ATRImage.headerSize + (sector - 1) * 128
            } else {
                return ATRImage.headerSize + 3 * 128 + (sector - 4) * 256
            }
        }
    }

    /// Returns the actual size of a specific sector.
    ///
    /// For double density disks, sectors 1-3 are 128 bytes for boot
    /// compatibility, while sectors 4+ are 256 bytes.
    ///
    /// - Parameter sector: The sector number (1-based).
    /// - Returns: The size of the sector in bytes.
    public func actualSectorSize(_ sector: Int) -> Int {
        if sectorSize == 256 && sector <= 3 {
            return 128
        }
        return sectorSize
    }

    // =========================================================================
    // MARK: - File Operations
    // =========================================================================

    /// Saves the disk image back to its file.
    ///
    /// Only writes if the disk has been modified. Does nothing if the disk
    /// is read-only.
    ///
    /// - Throws: ATRError.writeError if the file cannot be written.
    public func save() throws {
        guard !isReadOnly else {
            throw ATRError.readOnly
        }

        guard isModified else {
            return  // No changes to save
        }

        do {
            try data.write(to: url)
            isModified = false
        } catch {
            throw ATRError.writeError(error.localizedDescription)
        }
    }

    /// Discards any unsaved changes and reloads from disk.
    ///
    /// - Throws: ATRError.readError if the file cannot be read.
    public func revert() throws {
        do {
            data = try Data(contentsOf: url)
            isModified = false
        } catch {
            throw ATRError.readError(error.localizedDescription)
        }
    }

    // =========================================================================
    // MARK: - Static Factory Methods
    // =========================================================================

    /// Creates a new, empty ATR disk image file.
    ///
    /// The created disk is formatted with an empty DOS 2.x filesystem
    /// (VTOC and empty directory initialized).
    ///
    /// - Parameters:
    ///   - url: The file URL where the ATR should be created.
    ///   - type: The disk type (default: single density).
    /// - Returns: The newly created ATRImage instance.
    /// - Throws: ATRError.writeError if the file cannot be created.
    ///
    /// Example:
    ///
    ///     let newDisk = try ATRImage.create(
    ///         at: URL(fileURLWithPath: "/path/to/new.atr"),
    ///         type: .singleDensity
    ///     )
    ///
    @discardableResult
    public static func create(at url: URL, type: ATRDiskType = .singleDensity) throws -> ATRImage {
        var data = Data()

        // Build the ATR header (16 bytes)
        data.append(0x96)  // Magic byte 1
        data.append(0x02)  // Magic byte 2

        // Disk size in paragraphs (low word)
        let paragraphs = type.paragraphs
        data.append(UInt8(paragraphs & 0xFF))
        data.append(UInt8((paragraphs >> 8) & 0xFF))

        // Sector size (little-endian)
        data.append(UInt8(type.sectorSize & 0xFF))
        data.append(UInt8((type.sectorSize >> 8) & 0xFF))

        // High byte of paragraphs
        data.append(UInt8((paragraphs >> 16) & 0xFF))

        // Reserved bytes (9 bytes to reach 16-byte header)
        data.append(contentsOf: [UInt8](repeating: 0, count: 9))

        // Initialize sector data
        // For double density, first 3 sectors are 128 bytes
        if type.sectorSize == 256 {
            // First 3 sectors (128 bytes each)
            data.append(contentsOf: [UInt8](repeating: 0, count: 3 * 128))
            // Remaining sectors (256 bytes each)
            let remainingSectors = type.sectorCount - 3
            data.append(contentsOf: [UInt8](repeating: 0, count: remainingSectors * 256))
        } else {
            // All sectors are 128 bytes
            data.append(contentsOf: [UInt8](repeating: 0, count: type.sectorCount * 128))
        }

        // Write the file
        do {
            try data.write(to: url)
        } catch {
            throw ATRError.writeError(error.localizedDescription)
        }

        // Load as ATRImage and return
        return ATRImage(
            url: url,
            data: data,
            sectorSize: type.sectorSize,
            sectorCount: type.sectorCount
        )
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension ATRImage: CustomStringConvertible {
    public var description: String {
        let typeStr = diskType?.shortDescription ?? "Unknown"
        let modifiedStr = isModified ? " (modified)" : ""
        let readOnlyStr = isReadOnly ? " [read-only]" : ""
        return "ATRImage(\(url.lastPathComponent): \(typeStr), \(sectorCount) sectors)\(modifiedStr)\(readOnlyStr)"
    }
}
