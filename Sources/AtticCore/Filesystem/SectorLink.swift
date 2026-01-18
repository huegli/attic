// =============================================================================
// SectorLink.swift - Atari DOS Sector Link Structure
// =============================================================================
//
// This file defines the SectorLink structure used in Atari DOS file storage.
// Every data sector in an Atari DOS file ends with 3 bytes of link information
// that chains sectors together to form a complete file.
//
// Sector Link Format (last 3 bytes of each data sector):
// ======================================================
//
// For 128-byte sectors (offsets 125-127):
//   Byte 125: File ID (bits 7-2) | Next sector high bits (bits 1-0)
//   Byte 126: Next sector low byte (or byte count in last sector)
//   Byte 127: Unused (always 0)
//
// For 256-byte sectors (offsets 253-255):
//   Byte 253: File ID (full byte)
//   Byte 254: Next sector low byte (or byte count in last sector)
//   Byte 255: Next sector high byte (bits 1-0 only)
//
// File Chain:
// -----------
// Files are stored as linked lists of sectors:
//   Directory Entry → Sector 1 → Sector 2 → ... → Last Sector
//
// The last sector is identified by having a next sector value of 0.
// In this case, byte 126 (or 254) contains the count of valid data bytes
// in that final sector.
//
// File ID:
// --------
// The file ID is the directory entry index (0-63) for the file.
// This allows the DOS to verify sector ownership and detect corruption.
//
// Usage Example:
//
//     let sectorData = atr.readSector(45)
//     let link = SectorLink(sectorData: sectorData, sectorSize: 128)
//
//     if link.isLastSector {
//         print("Last sector, contains \(link.bytesInSector) bytes")
//     } else {
//         print("Next sector: \(link.nextSector)")
//     }
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Sector Link Structure
// =============================================================================

/// Represents the link bytes at the end of an Atari DOS data sector.
///
/// Each data sector contains 3 bytes of link information that chain
/// sectors together to form files. This structure parses those bytes
/// and provides easy access to the link information.
///
/// The link bytes serve multiple purposes:
/// 1. Chain to the next sector in the file
/// 2. Identify the file that owns this sector
/// 3. Indicate the last sector in the chain
/// 4. Track how many valid bytes are in the last sector
public struct SectorLink: Sendable, Equatable {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The file ID (directory entry index) that owns this sector.
    ///
    /// This is a 6-bit value (0-63) that matches the file's position
    /// in the directory. The DOS uses this to verify sector ownership.
    ///
    /// For 128-byte sectors, the file ID is in bits 7-2 of byte 125.
    /// For 256-byte sectors, the file ID is the full byte 253.
    public let fileID: UInt8

    /// The next sector number in the file chain.
    ///
    /// This is a 10-bit value (0-1023) that points to the next sector.
    /// A value of 0 indicates this is the last sector in the file.
    ///
    /// The 10-bit value is split across bytes:
    /// - For 128-byte: bits 1-0 of byte 125 (high) + byte 126 (low)
    /// - For 256-byte: bits 1-0 of byte 255 (high) + byte 254 (low)
    public let nextSector: UInt16

    /// Whether this is the last sector in the file chain.
    ///
    /// True if nextSector is 0, indicating the file ends here.
    public let isLastSector: Bool

    /// The number of valid data bytes in this sector.
    ///
    /// For intermediate sectors, this is always (sectorSize - 3).
    /// For the last sector, this is the count from the link bytes,
    /// indicating how many bytes of actual file data are present.
    public let bytesInSector: Int

    /// The sector size this link was parsed from.
    ///
    /// Either 128 or 256 bytes. Needed to correctly interpret the link format.
    public let sectorSize: Int

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a SectorLink by parsing the link bytes from sector data.
    ///
    /// - Parameters:
    ///   - sectorData: The complete sector data (128 or 256 bytes).
    ///   - sectorSize: The sector size (128 or 256).
    ///   - isKnownLastSector: If true, interprets the data as a last sector
    ///     where the forward pointer field contains the byte count. If nil,
    ///     uses heuristics to detect last sectors (byte count <= max data bytes
    ///     with high bits = 0).
    ///
    /// - Important: The sectorData must be at least sectorSize bytes.
    ///   If smaller, the behavior is undefined.
    ///
    /// Usage:
    ///
    ///     let rawSector = disk.readSector(45)
    ///     let link = SectorLink(sectorData: rawSector, sectorSize: 128)
    ///
    ///     // When you know it's the last sector from directory entry:
    ///     let lastLink = SectorLink(sectorData: rawSector, sectorSize: 128, isKnownLastSector: true)
    ///
    public init(sectorData: [UInt8], sectorSize: Int, isKnownLastSector: Bool? = nil) {
        self.sectorSize = sectorSize

        // The link bytes are at the end of the sector
        let linkOffset = sectorSize - 3

        // Ensure we have enough data
        guard sectorData.count >= sectorSize else {
            // Invalid data - create an empty link
            self.fileID = 0
            self.nextSector = 0
            self.isLastSector = true
            self.bytesInSector = 0
            return
        }

        if sectorSize == 128 {
            // 128-byte sector format:
            // Byte 125: File ID (bits 7-2) | Next sector high (bits 1-0)
            // Byte 126: Next sector low (or byte count if last)
            // Byte 127: Unused

            let byte125 = sectorData[linkOffset]
            let byte126 = sectorData[linkOffset + 1]

            // Extract file ID from bits 7-2
            self.fileID = byte125 >> 2

            // Extract forward pointer bits
            let nextHigh = byte125 & 0x03
            let nextValue = UInt16(nextHigh) << 8 | UInt16(byte126)
            let maxDataBytes = sectorSize - 3  // 125 for 128-byte sectors

            // Determine if this is a last sector
            let isLast: Bool
            if let known = isKnownLastSector {
                // Caller knows whether this is the last sector
                isLast = known
            } else {
                // Heuristic: if forward pointer is 0, it's the last sector
                // Also treat as last if high bits are 0 and byte126 <= max data bytes
                // (this handles the common case where byte count < max data bytes)
                isLast = nextValue == 0 || (nextHigh == 0 && byte126 <= maxDataBytes)
            }

            if isLast {
                self.isLastSector = true
                self.nextSector = 0
                self.bytesInSector = Int(byte126)
            } else {
                self.isLastSector = false
                self.nextSector = nextValue
                self.bytesInSector = maxDataBytes
            }
        } else {
            // 256-byte sector format:
            // Byte 253: File ID (full byte)
            // Byte 254: Next sector low (or byte count if last)
            // Byte 255: Next sector high (bits 1-0 only)

            let byte253 = sectorData[linkOffset]
            let byte254 = sectorData[linkOffset + 1]
            let byte255 = sectorData[linkOffset + 2]

            // File ID is the full first byte
            self.fileID = byte253

            // Extract forward pointer bits
            let nextHigh = byte255 & 0x03
            let nextValue = UInt16(nextHigh) << 8 | UInt16(byte254)
            let maxDataBytes = sectorSize - 3  // 253 for 256-byte sectors

            // Determine if this is a last sector
            let isLast: Bool
            if let known = isKnownLastSector {
                isLast = known
            } else {
                isLast = nextValue == 0 || (nextHigh == 0 && byte254 <= maxDataBytes)
            }

            if isLast {
                self.isLastSector = true
                self.nextSector = 0
                self.bytesInSector = Int(byte254)
            } else {
                self.isLastSector = false
                self.nextSector = nextValue
                self.bytesInSector = maxDataBytes
            }
        }
    }

    /// Creates a SectorLink with explicit values.
    ///
    /// This initializer is useful for constructing link bytes when writing files.
    ///
    /// - Parameters:
    ///   - fileID: The file ID (directory entry index, 0-63).
    ///   - nextSector: The next sector number (0 for last sector).
    ///   - bytesInSector: For last sector, the valid byte count.
    ///   - sectorSize: The sector size (128 or 256).
    public init(fileID: UInt8, nextSector: UInt16, bytesInSector: Int, sectorSize: Int) {
        self.fileID = fileID
        self.nextSector = nextSector
        self.isLastSector = nextSector == 0
        self.bytesInSector = bytesInSector
        self.sectorSize = sectorSize
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Encodes the link into 3 bytes for writing to a sector.
    ///
    /// - Returns: A 3-byte array containing the encoded link bytes.
    ///
    /// Usage:
    ///
    ///     let link = SectorLink(fileID: 5, nextSector: 47, bytesInSector: 125, sectorSize: 128)
    ///     let bytes = link.encode()
    ///     sectorData[125...127] = bytes
    ///
    public func encode() -> [UInt8] {
        if sectorSize == 128 {
            // 128-byte sector format
            if isLastSector {
                // Last sector: byte 126 contains valid data count
                let byte125 = (fileID << 2) & 0xFC  // File ID in bits 7-2, bits 1-0 = 0
                let byte126 = UInt8(bytesInSector & 0xFF)
                return [byte125, byte126, 0]
            } else {
                // Intermediate sector: encode next sector
                let byte125 = (fileID << 2) | UInt8((nextSector >> 8) & 0x03)
                let byte126 = UInt8(nextSector & 0xFF)
                return [byte125, byte126, 0]
            }
        } else {
            // 256-byte sector format
            if isLastSector {
                // Last sector: byte 254 contains valid data count
                let byte253 = fileID
                let byte254 = UInt8(bytesInSector & 0xFF)
                return [byte253, byte254, 0]
            } else {
                // Intermediate sector: encode next sector
                let byte253 = fileID
                let byte254 = UInt8(nextSector & 0xFF)
                let byte255 = UInt8((nextSector >> 8) & 0x03)
                return [byte253, byte254, byte255]
            }
        }
    }

    // =========================================================================
    // MARK: - Validation
    // =========================================================================

    /// Validates the link against expected values.
    ///
    /// - Parameters:
    ///   - expectedFileID: The expected file ID for this sector.
    ///   - maxSector: The maximum valid sector number on the disk.
    /// - Returns: An error description if invalid, nil if valid.
    ///
    /// This can detect:
    /// - Wrong file ID (sector belongs to different file)
    /// - Next sector out of range
    /// - Invalid byte count in last sector
    public func validate(expectedFileID: UInt8, maxSector: Int) -> String? {
        // Check file ID matches
        if fileID != expectedFileID {
            return "Sector belongs to file \(fileID), expected \(expectedFileID)"
        }

        // Check next sector is valid
        if !isLastSector && nextSector > UInt16(maxSector) {
            return "Next sector \(nextSector) exceeds disk size \(maxSector)"
        }

        // Check byte count in last sector is valid
        if isLastSector {
            let maxBytes = sectorSize - 3
            if bytesInSector > maxBytes {
                return "Invalid byte count \(bytesInSector) for \(sectorSize)-byte sector"
            }
        }

        return nil
    }
}

// =============================================================================
// MARK: - CustomStringConvertible
// =============================================================================

extension SectorLink: CustomStringConvertible {
    /// A human-readable description of the sector link.
    public var description: String {
        if isLastSector {
            return "SectorLink(fileID: \(fileID), LAST, bytes: \(bytesInSector))"
        } else {
            return "SectorLink(fileID: \(fileID), next: \(nextSector))"
        }
    }
}
