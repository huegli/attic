// =============================================================================
// VTOC.swift - Volume Table of Contents Management
// =============================================================================
//
// This file defines the VTOC (Volume Table of Contents) structure used by
// Atari DOS to track which sectors are free or in use on a disk.
//
// VTOC Location:
// ==============
// The VTOC is stored in sector 360 of the disk. It's a single sector (128 bytes
// for single/enhanced density, or the first 128 bytes of a 256-byte sector
// for double density).
//
// VTOC Structure (DOS 2.x):
// =========================
//
//   Offset  Size  Description
//   ------  ----  -----------
//   0       1     DOS code (0 = DOS 2.0, 2 = DOS 2.5)
//   1       2     Total sectors (little-endian)
//   3       2     Free sectors (little-endian)
//   5       5     Reserved
//   10      90    Sector bitmap for sectors 0-719
//   100     28    Extended bitmap for sectors 720-1039 (DOS 2.5 only)
//
// Bitmap Format:
// ==============
// Each bit represents one sector:
//   - Bit = 1: Sector is free (available for allocation)
//   - Bit = 0: Sector is in use (allocated to a file or system)
//
// Bits are numbered MSB-first within each byte:
//   - Byte 10, bit 7 = Sector 0
//   - Byte 10, bit 6 = Sector 1
//   - Byte 10, bit 0 = Sector 7
//   - Byte 11, bit 7 = Sector 8
//   - etc.
//
// System Sectors (always marked in use):
// =====================================
// - Sectors 1-3: Boot sectors
// - Sector 360: VTOC itself
// - Sectors 361-368: Directory
//
// DOS 2.5 Extended Area:
// ======================
// Enhanced density disks (1040 sectors) use an extended bitmap area starting
// at offset 100 to track sectors 720-1039. The extended bitmap uses the same
// bit ordering as the main bitmap.
//
// Usage Example:
//
//     let vtocData = disk.readSector(360)
//     let vtoc = try VTOC(data: vtocData, diskType: .singleDensity)
//
//     print("Free sectors: \(vtoc.freeSectorCount)")
//     print("Sector 100 free: \(vtoc.isSectorFree(100))")
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - VTOC Structure
// =============================================================================

/// Represents the Volume Table of Contents for an Atari DOS disk.
///
/// The VTOC tracks which sectors are free or in use via a bitmap.
/// It also stores basic disk information like total and free sector counts.
///
/// This is a read-only representation for Phase 12. Write support will be
/// added in future phases when file writing is implemented.
public struct VTOC: Sendable {

    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// The sector number where the VTOC is stored.
    public static let vtocSector = 360

    /// Offset of the main bitmap (sectors 0-719) within the VTOC.
    public static let bitmapOffset = 10

    /// Size of the main bitmap in bytes (covers 720 sectors).
    public static let bitmapSize = 90

    /// Offset of the extended bitmap (sectors 720-1039) within the VTOC.
    public static let extendedBitmapOffset = 100

    /// Size of the extended bitmap in bytes (covers 320 sectors).
    public static let extendedBitmapSize = 28

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The DOS version code from the VTOC.
    ///
    /// Common values:
    /// - 0: DOS 2.0
    /// - 2: DOS 2.5
    public let dosCode: UInt8

    /// The total number of sectors on the disk (from VTOC header).
    ///
    /// This should match the actual disk size, but may differ on
    /// corrupted or non-standard disks.
    public let totalSectors: UInt16

    /// The number of free sectors (from VTOC header).
    ///
    /// This is the count stored in the VTOC. Use `countFreeSectors()`
    /// to calculate the actual count from the bitmap.
    public let freeSectorCount: UInt16

    /// The disk type this VTOC is for.
    public let diskType: DiskType

    /// The raw VTOC sector data (128 bytes minimum).
    private let data: [UInt8]

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a VTOC by parsing raw sector data.
    ///
    /// - Parameters:
    ///   - data: The raw VTOC sector data (at least 128 bytes).
    ///   - diskType: The disk type to interpret the VTOC for.
    ///   - validationMode: How strictly to validate the VTOC.
    /// - Throws: ATRError if the VTOC is invalid and validation is strict.
    ///
    /// Usage:
    ///
    ///     let vtocSector = disk.readSector(360)
    ///     let vtoc = try VTOC(data: vtocSector, diskType: .singleDensity)
    ///
    public init(
        data: [UInt8],
        diskType: DiskType,
        validationMode: ATRValidationMode = .lenient
    ) throws {
        // Ensure we have at least 128 bytes
        guard data.count >= 128 else {
            if validationMode == .strict {
                throw ATRError.invalidVTOC("VTOC sector too short (\(data.count) bytes)")
            }
            // Pad with zeros for lenient mode
            self.data = data + Array(repeating: 0, count: 128 - data.count)
            self.dosCode = 0
            self.totalSectors = 0
            self.freeSectorCount = 0
            self.diskType = diskType
            return
        }

        self.data = Array(data.prefix(128))
        self.diskType = diskType

        // Parse VTOC header
        self.dosCode = data[0]
        self.totalSectors = UInt16(data[1]) | (UInt16(data[2]) << 8)
        self.freeSectorCount = UInt16(data[3]) | (UInt16(data[4]) << 8)

        // Validate DOS code
        if validationMode == .strict {
            if dosCode != 0 && dosCode != 2 {
                throw ATRError.unsupportedDOS(Int(dosCode))
            }
        }
    }

    /// Creates an empty VTOC for a new disk.
    ///
    /// This initializes a VTOC with all data sectors marked as free
    /// and system sectors (boot, VTOC, directory) marked as used.
    ///
    /// - Parameter diskType: The disk type to create a VTOC for.
    /// - Returns: A new VTOC initialized for the specified disk type.
    public static func createEmpty(for diskType: DiskType) -> VTOC {
        var data = [UInt8](repeating: 0, count: 128)

        // DOS code: 2 for DOS 2.5 (supports both SD and ED)
        data[0] = diskType == .enhancedDensity ? 2 : 2

        // Total sectors
        let totalSectors = UInt16(diskType.sectorCount)
        data[1] = UInt8(totalSectors & 0xFF)
        data[2] = UInt8((totalSectors >> 8) & 0xFF)

        // Calculate free sectors (total - boot - VTOC - directory)
        let systemSectors = 3 + 1 + 8  // boot(3) + VTOC(1) + directory(8)
        let freeSectors = UInt16(diskType.sectorCount - systemSectors)
        data[3] = UInt8(freeSectors & 0xFF)
        data[4] = UInt8((freeSectors >> 8) & 0xFF)

        // Initialize bitmap with all sectors free
        for i in VTOC.bitmapOffset..<(VTOC.bitmapOffset + VTOC.bitmapSize) {
            data[i] = 0xFF
        }

        // For enhanced density, also initialize extended bitmap
        if diskType.usesExtendedVTOC {
            for i in VTOC.extendedBitmapOffset..<(VTOC.extendedBitmapOffset + VTOC.extendedBitmapSize) {
                data[i] = 0xFF
            }
        }

        // Mark system sectors as used
        var vtoc = try! VTOC(data: data, diskType: diskType, validationMode: .lenient)

        // Create a mutable copy and mark system sectors
        var mutableData = data

        // Mark boot sectors (1-3) as used
        for sector in 1...3 {
            VTOC.markSectorInBitmap(&mutableData, sector: sector, free: false)
        }

        // Mark VTOC sector (360) as used
        VTOC.markSectorInBitmap(&mutableData, sector: 360, free: false)

        // Mark directory sectors (361-368) as used
        for sector in 361...368 {
            VTOC.markSectorInBitmap(&mutableData, sector: sector, free: false)
        }

        // Update free sector count
        let actualFree = VTOC.countFreeSectorsInBitmap(mutableData, diskType: diskType)
        mutableData[3] = UInt8(actualFree & 0xFF)
        mutableData[4] = UInt8((actualFree >> 8) & 0xFF)

        return try! VTOC(data: mutableData, diskType: diskType, validationMode: .lenient)
    }

    // =========================================================================
    // MARK: - Sector Status Queries
    // =========================================================================

    /// Checks if a sector is free (available for allocation).
    ///
    /// - Parameter sector: The sector number to check (1-based).
    /// - Returns: True if the sector is free, false if in use or invalid.
    public func isSectorFree(_ sector: Int) -> Bool {
        guard sector >= 1 && sector <= diskType.sectorCount else {
            return false
        }

        if sector <= 720 {
            // Main bitmap area (sectors 1-720)
            // Use 0-based indexing: sector 1 maps to bit 0
            let bitPosition = sector - 1
            let byteIndex = VTOC.bitmapOffset + (bitPosition / 8)
            let bitIndex = 7 - (bitPosition % 8)

            guard byteIndex < data.count else { return false }
            return (data[byteIndex] & (1 << bitIndex)) != 0
        } else if diskType.usesExtendedVTOC && sector <= 1040 {
            // Extended bitmap area (DOS 2.5, sectors 721-1040)
            // Use 0-based indexing: sector 721 maps to bit 0
            let extBitPosition = sector - 721
            let byteIndex = VTOC.extendedBitmapOffset + (extBitPosition / 8)
            let bitIndex = 7 - (extBitPosition % 8)

            // Extended bitmap only covers 28 bytes (224 sectors: 721-944)
            // Sectors beyond 944 are considered free (can't be tracked)
            guard byteIndex < data.count else { return true }
            return (data[byteIndex] & (1 << bitIndex)) != 0
        } else {
            return false
        }
    }

    /// Checks if a sector is in use (allocated).
    ///
    /// - Parameter sector: The sector number to check (1-based).
    /// - Returns: True if the sector is in use.
    public func isSectorUsed(_ sector: Int) -> Bool {
        !isSectorFree(sector)
    }

    /// Counts the actual number of free sectors by scanning the bitmap.
    ///
    /// - Returns: The number of free sectors according to the bitmap.
    ///
    /// Note: This may differ from `freeSectorCount` if the VTOC is corrupted
    /// or out of sync with the actual bitmap.
    public func countFreeSectors() -> Int {
        VTOC.countFreeSectorsInBitmap(data, diskType: diskType)
    }

    /// Returns a list of all free sector numbers.
    ///
    /// - Returns: An array of free sector numbers, sorted ascending.
    public func getFreeSectors() -> [Int] {
        var freeSectors: [Int] = []

        for sector in 1...diskType.sectorCount {
            if isSectorFree(sector) {
                freeSectors.append(sector)
            }
        }

        return freeSectors
    }

    /// Returns a list of all used sector numbers.
    ///
    /// - Returns: An array of used sector numbers, sorted ascending.
    public func getUsedSectors() -> [Int] {
        var usedSectors: [Int] = []

        for sector in 1...diskType.sectorCount {
            if isSectorUsed(sector) {
                usedSectors.append(sector)
            }
        }

        return usedSectors
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    /// Validates the VTOC for consistency.
    ///
    /// Checks that:
    /// - The stored free sector count matches the bitmap
    /// - System sectors are marked as used
    /// - No invalid data is present
    ///
    /// - Returns: A list of validation issues, empty if valid.
    public func validate() -> [String] {
        var issues: [String] = []

        // Check free sector count matches bitmap
        let actualFree = countFreeSectors()
        if actualFree != Int(freeSectorCount) {
            issues.append("Free sector count mismatch: header says \(freeSectorCount), bitmap has \(actualFree)")
        }

        // Check system sectors are marked used
        for sector in 1...3 {
            if isSectorFree(sector) {
                issues.append("Boot sector \(sector) marked as free")
            }
        }

        if isSectorFree(360) {
            issues.append("VTOC sector 360 marked as free")
        }

        for sector in 361...368 {
            if isSectorFree(sector) {
                issues.append("Directory sector \(sector) marked as free")
            }
        }

        // Check total sectors matches disk type
        if Int(totalSectors) != diskType.sectorCount {
            issues.append("Total sectors mismatch: VTOC says \(totalSectors), disk type has \(diskType.sectorCount)")
        }

        return issues
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Returns the raw VTOC data for writing to disk.
    ///
    /// - Returns: A 128-byte array containing the VTOC sector data.
    public func encode() -> [UInt8] {
        Array(data.prefix(128))
    }

    // =========================================================================
    // MARK: - Static Helper Methods
    // =========================================================================

    /// Marks a sector as free or used in a bitmap array.
    ///
    /// This is a static helper for modifying bitmap data directly.
    ///
    /// - Parameters:
    ///   - data: The VTOC data array to modify (must be mutable).
    ///   - sector: The sector number to mark (1-based).
    ///   - free: True to mark as free, false to mark as used.
    private static func markSectorInBitmap(_ data: inout [UInt8], sector: Int, free: Bool) {
        guard sector >= 1 && sector <= 1040 else { return }

        let byteIndex: Int
        let bitIndex: Int

        if sector <= 720 {
            // Main bitmap: use 0-based indexing (sector 1 = bit 0)
            let bitPosition = sector - 1
            byteIndex = bitmapOffset + (bitPosition / 8)
            bitIndex = 7 - (bitPosition % 8)
        } else {
            // Extended bitmap: use 0-based indexing (sector 721 = bit 0)
            let extBitPosition = sector - 721
            byteIndex = extendedBitmapOffset + (extBitPosition / 8)
            bitIndex = 7 - (extBitPosition % 8)
        }

        guard byteIndex < data.count else { return }

        if free {
            data[byteIndex] |= (1 << bitIndex)
        } else {
            data[byteIndex] &= ~(1 << bitIndex)
        }
    }

    /// Counts free sectors in a bitmap array.
    ///
    /// - Parameters:
    ///   - data: The VTOC data array.
    ///   - diskType: The disk type to determine sector count.
    /// - Returns: The number of free sectors.
    private static func countFreeSectorsInBitmap(_ data: [UInt8], diskType: DiskType) -> Int {
        var count = 0
        let maxSector = min(diskType.sectorCount, 720)

        // Count main bitmap area (sectors 1-720)
        for sector in 1...maxSector {
            let bitPosition = sector - 1
            let byteIndex = bitmapOffset + (bitPosition / 8)
            let bitIndex = 7 - (bitPosition % 8)

            if byteIndex < data.count && (data[byteIndex] & (1 << bitIndex)) != 0 {
                count += 1
            }
        }

        // Count extended bitmap area (DOS 2.5, sectors 721-1040)
        if diskType.usesExtendedVTOC && diskType.sectorCount > 720 {
            for sector in 721...diskType.sectorCount {
                let extBitPosition = sector - 721
                let byteIndex = extendedBitmapOffset + (extBitPosition / 8)
                let bitIndex = 7 - (extBitPosition % 8)

                // Sectors beyond trackable range (945-1040) are considered free
                if byteIndex >= data.count {
                    count += 1
                } else if (data[byteIndex] & (1 << bitIndex)) != 0 {
                    count += 1
                }
            }
        }

        return count
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension VTOC: CustomStringConvertible {
    /// A human-readable description of the VTOC.
    public var description: String {
        let dosVersion = dosCode == 2 ? "DOS 2.5" : "DOS 2.0"
        let actualFree = countFreeSectors()
        let match = actualFree == Int(freeSectorCount) ? "" : " (actual: \(actualFree))"

        return "VTOC(\(dosVersion), total: \(totalSectors), free: \(freeSectorCount)\(match))"
    }
}
