// =============================================================================
// DiskType.swift - Atari Disk Format Definitions
// =============================================================================
//
// This file defines the various Atari disk formats supported by the emulator.
// The Atari 8-bit computers supported several disk density configurations:
//
// Physical Formats:
// -----------------
// - Single Density (SD): 90KB, 720 sectors × 128 bytes
// - Enhanced Density (ED): 130KB, 1040 sectors × 128 bytes (DOS 2.5)
// - Double Density (DD): 180KB, 720 sectors × 256 bytes
// - Quad Density (QD): 360KB, double-sided (read-only support)
//
// ATR File Structure:
// -------------------
// All ATR files start with a 16-byte header, followed by sector data.
// Important quirk: In double density disks, the first 3 sectors are still
// 128 bytes each (for boot compatibility), while sectors 4+ are 256 bytes.
//
// Size Calculations:
// ------------------
// ATR headers store disk size in "paragraphs" (16-byte units):
//   Single Density:   720 × 128 = 92,160 bytes = 5,760 paragraphs
//   Enhanced Density: 1040 × 128 = 133,120 bytes = 8,320 paragraphs
//   Double Density:   3 × 128 + 717 × 256 = 184,320 bytes = 11,520 paragraphs
//
// Usage Example:
//
//     let diskType = DiskType.singleDensity
//     print("Creating \(diskType.displayName) disk")
//     print("Total size: \(diskType.totalSize) bytes")
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Disk Type Enumeration
// =============================================================================

/// Represents the various Atari disk format types.
///
/// Each disk type defines the sector size, sector count, and total capacity.
/// The emulator supports creating single, enhanced, and double density disks,
/// and can read (but not create) quad density disks.
///
/// Historical Context:
/// - Single Density (SD) was the original Atari 810 drive format
/// - Enhanced Density (ED) was added with DOS 2.5 for the 1050 drive
/// - Double Density (DD) was used by third-party drives and the XF551
/// - Quad Density required a double-sided drive (rare)
public enum DiskType: String, Sendable, CaseIterable {

    // =========================================================================
    // MARK: - Supported Disk Types
    // =========================================================================

    /// Single Density (SS/SD) - 90KB capacity.
    ///
    /// The original Atari 810 disk drive format:
    /// - 720 sectors total
    /// - 128 bytes per sector
    /// - 92,160 bytes (90KB) capacity
    /// - Most compatible format, works with all Atari DOS versions
    case singleDensity = "ss/sd"

    /// Enhanced Density (SS/ED) - 130KB capacity.
    ///
    /// Introduced with DOS 2.5 for the Atari 1050 drive:
    /// - 1040 sectors total (720 standard + 320 extended)
    /// - 128 bytes per sector
    /// - 133,120 bytes (130KB) capacity
    /// - Requires DOS 2.5 or compatible
    ///
    /// Note: The extra 320 sectors (721-1040) use a separate VTOC bitmap
    /// area starting at VTOC offset 100.
    case enhancedDensity = "ss/ed"

    /// Double Density (SS/DD) - 180KB capacity.
    ///
    /// Used by third-party drives and the Atari XF551:
    /// - 720 sectors total
    /// - 256 bytes per sector (except boot sectors 1-3 which are 128 bytes)
    /// - 184,320 bytes (180KB) capacity
    /// - Requires double-density capable DOS
    ///
    /// Important: The first 3 sectors are always 128 bytes for boot compatibility.
    /// This is a quirk of the ATR format that must be handled specially.
    case doubleDensity = "ss/dd"

    /// Quad Density (DS/DD) - 360KB capacity (read-only support).
    ///
    /// Double-sided, double-density format:
    /// - 1440 sectors total
    /// - 256 bytes per sector
    /// - 368,640 bytes (360KB) capacity
    /// - Read-only support - cannot create or format
    ///
    /// This format was rare and required special hardware.
    /// We support reading these images but not creating them.
    case quadDensity = "ds/dd"

    // =========================================================================
    // MARK: - Computed Properties
    // =========================================================================

    /// The number of bytes per sector for this disk type.
    ///
    /// Note: For double/quad density, this is the "normal" sector size.
    /// The first 3 boot sectors are always 128 bytes regardless of this value.
    public var sectorSize: Int {
        switch self {
        case .singleDensity, .enhancedDensity:
            return 128
        case .doubleDensity, .quadDensity:
            return 256
        }
    }

    /// The total number of sectors on the disk.
    ///
    /// This is the logical sector count, numbered 1 through sectorCount.
    /// Note that sector numbering starts at 1, not 0.
    public var sectorCount: Int {
        switch self {
        case .singleDensity:
            return 720
        case .enhancedDensity:
            return 1040
        case .doubleDensity:
            return 720
        case .quadDensity:
            return 1440
        }
    }

    /// The total disk size in bytes (content only, not including ATR header).
    ///
    /// For double density, this accounts for the first 3 sectors being 128 bytes.
    public var totalSize: Int {
        switch self {
        case .singleDensity:
            // 720 sectors × 128 bytes
            return 720 * 128
        case .enhancedDensity:
            // 1040 sectors × 128 bytes
            return 1040 * 128
        case .doubleDensity:
            // First 3 sectors are 128 bytes, rest are 256 bytes
            // 3 × 128 + 717 × 256 = 384 + 183,936 = 184,320
            return 3 * 128 + (720 - 3) * 256
        case .quadDensity:
            // First 3 sectors are 128 bytes, rest are 256 bytes
            // 3 × 128 + 1437 × 256 = 384 + 367,872 = 368,256
            return 3 * 128 + (1440 - 3) * 256
        }
    }

    /// The disk size in paragraphs (16-byte units) for the ATR header.
    ///
    /// This value is stored in the ATR header bytes 2-3 (low word) and byte 6 (high byte).
    public var paragraphs: Int {
        totalSize / 16
    }

    /// The number of usable data bytes per sector.
    ///
    /// Each sector reserves 3 bytes for the file link (file ID + next sector pointer).
    /// This is the actual space available for file data.
    public var bytesPerSectorForData: Int {
        sectorSize - 3
    }

    /// Human-readable display name for UI and messages.
    public var displayName: String {
        switch self {
        case .singleDensity:
            return "Single Density (90K)"
        case .enhancedDensity:
            return "Enhanced Density (130K)"
        case .doubleDensity:
            return "Double Density (180K)"
        case .quadDensity:
            return "Quad Density (360K)"
        }
    }

    /// Short format string for compact display (e.g., "SS/SD").
    public var shortName: String {
        rawValue.uppercased()
    }

    /// Whether this disk type can be created/formatted by the emulator.
    ///
    /// We support creating single, enhanced, and double density disks.
    /// Quad density is read-only because it was rare and complex.
    public var isCreatable: Bool {
        switch self {
        case .singleDensity, .enhancedDensity, .doubleDensity:
            return true
        case .quadDensity:
            return false
        }
    }

    /// Whether this disk type uses the extended VTOC area (DOS 2.5 format).
    ///
    /// Enhanced density disks have additional sectors (721-1040) that need
    /// a separate bitmap area starting at VTOC offset 100.
    public var usesExtendedVTOC: Bool {
        self == .enhancedDensity
    }

    // =========================================================================
    // MARK: - Static Factory Methods
    // =========================================================================

    /// Detects the disk type from an ATR header.
    ///
    /// This examines the sector size and calculated sector count to determine
    /// what type of disk the ATR file represents.
    ///
    /// - Parameters:
    ///   - sectorSize: The sector size from the ATR header.
    ///   - sectorCount: The calculated total sector count.
    /// - Returns: The detected disk type, or nil if unrecognized.
    ///
    /// Usage:
    ///
    ///     guard let diskType = DiskType.detect(sectorSize: 128, sectorCount: 720) else {
    ///         throw ATRError.unsupportedFormat("Unknown disk format")
    ///     }
    ///
    public static func detect(sectorSize: Int, sectorCount: Int) -> DiskType? {
        switch (sectorSize, sectorCount) {
        case (128, 720):
            return .singleDensity
        case (128, 1040):
            return .enhancedDensity
        case (128, let count) where count > 720 && count <= 1040:
            // Possibly a truncated enhanced density disk, treat as enhanced
            return .enhancedDensity
        case (256, 720):
            return .doubleDensity
        case (256, 1440):
            return .quadDensity
        case (256, let count) where count > 720 && count < 1440:
            // Possibly a truncated quad density disk
            return .quadDensity
        default:
            return nil
        }
    }

    /// Creates a disk type from a command-line format string.
    ///
    /// Accepts various formats like "ss/sd", "sd", "single", etc.
    ///
    /// - Parameter string: The format string to parse.
    /// - Returns: The disk type, or nil if unrecognized.
    ///
    /// Supported input formats:
    /// - Single density: "ss/sd", "sd", "single", "90k"
    /// - Enhanced density: "ss/ed", "ed", "enhanced", "130k"
    /// - Double density: "ss/dd", "dd", "double", "180k"
    /// - Quad density: "ds/dd", "qd", "quad", "360k"
    ///
    public static func fromString(_ string: String) -> DiskType? {
        switch string.lowercased() {
        case "ss/sd", "sd", "single", "90k":
            return .singleDensity
        case "ss/ed", "ed", "enhanced", "130k":
            return .enhancedDensity
        case "ss/dd", "dd", "double", "180k":
            return .doubleDensity
        case "ds/dd", "qd", "quad", "360k":
            return .quadDensity
        default:
            return nil
        }
    }
}

// =============================================================================
// MARK: - DOS Sector Layout Constants
// =============================================================================

/// Constants defining the standard Atari DOS 2.x disk layout.
///
/// These define where system sectors are located on a standard DOS disk.
/// Different DOS variants may use different layouts, but these are the
/// standard DOS 2.x locations.
public enum DOSLayout {

    // =========================================================================
    // MARK: - System Sector Locations
    // =========================================================================

    /// The number of boot sectors at the start of the disk.
    ///
    /// Sectors 1-3 are reserved for the boot code. These sectors are
    /// always 128 bytes even on double-density disks.
    public static let bootSectorCount = 3

    /// The first sector available for data files.
    ///
    /// Sectors 1-3 are boot sectors, so data starts at sector 4.
    public static let firstDataSector = 4

    /// The VTOC (Volume Table of Contents) sector number.
    ///
    /// The VTOC at sector 360 contains the free sector bitmap and
    /// disk information. This is standard for DOS 2.x.
    public static let vtocSector = 360

    /// The first directory sector number.
    ///
    /// The directory occupies sectors 361-368 (8 sectors × 8 entries = 64 max files).
    public static let firstDirectorySector = 361

    /// The last directory sector number.
    public static let lastDirectorySector = 368

    /// The number of directory sectors.
    public static let directorySectorCount = 8

    /// The number of file entries per directory sector.
    ///
    /// Each directory sector holds 8 entries × 16 bytes = 128 bytes.
    public static let entriesPerSector = 8

    /// The maximum number of files a DOS 2.x disk can hold.
    ///
    /// 8 directory sectors × 8 entries per sector = 64 files maximum.
    public static let maxFiles = directorySectorCount * entriesPerSector

    // =========================================================================
    // MARK: - Sector Ranges
    // =========================================================================

    /// Returns true if the sector is a boot sector.
    public static func isBootSector(_ sector: Int) -> Bool {
        sector >= 1 && sector <= bootSectorCount
    }

    /// Returns true if the sector is the VTOC.
    public static func isVTOCSector(_ sector: Int) -> Bool {
        sector == vtocSector
    }

    /// Returns true if the sector is a directory sector.
    public static func isDirectorySector(_ sector: Int) -> Bool {
        sector >= firstDirectorySector && sector <= lastDirectorySector
    }

    /// Returns true if the sector is available for file data.
    ///
    /// Data sectors are anything that's not boot, VTOC, or directory.
    public static func isDataSector(_ sector: Int, totalSectors: Int) -> Bool {
        guard sector >= 1 && sector <= totalSectors else { return false }
        return !isBootSector(sector) && !isVTOCSector(sector) && !isDirectorySector(sector)
    }

    // =========================================================================
    // MARK: - Enhanced Density Extensions
    // =========================================================================

    /// The first sector in the enhanced density extended area.
    ///
    /// DOS 2.5 extended the disk to include sectors 721-1040.
    /// These use a separate VTOC bitmap area.
    public static let enhancedFirstSector = 721

    /// The last sector in the enhanced density extended area.
    public static let enhancedLastSector = 1040

    /// Returns true if the sector is in the enhanced density extended area.
    public static func isEnhancedSector(_ sector: Int) -> Bool {
        sector >= enhancedFirstSector && sector <= enhancedLastSector
    }
}
