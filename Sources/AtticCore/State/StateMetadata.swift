// =============================================================================
// StateMetadata.swift - Emulator State File Metadata
// =============================================================================
//
// This file defines the metadata structure stored alongside emulator state
// snapshots. The metadata captures contextual information about the emulator
// session at save time, enabling meaningful state restoration.
//
// File Format (Version 2):
// ========================
//
// ┌────────────────────────────────────┐
// │ Header (16 bytes)                  │
// │   Magic: "ATTC" (4 bytes)          │
// │   Version: 0x02 (1 byte)           │
// │   Flags: (1 byte)                  │
// │   Reserved: (10 bytes)             │
// ├────────────────────────────────────┤
// │ Metadata Length (4 bytes, LE)      │
// ├────────────────────────────────────┤
// │ Metadata (JSON, UTF-8)             │
// │   - timestamp                      │
// │   - replMode                       │
// │   - mountedDisks                   │
// │   - basicVariant (if applicable)   │
// ├────────────────────────────────────┤
// │ State Tags (32 bytes)              │
// │   - libatari800 section offsets    │
// ├────────────────────────────────────┤
// │ State Flags (8 bytes)              │
// │   - selfTestEnabled, frameCount    │
// ├────────────────────────────────────┤
// │ libatari800 State Data             │
// │   - ~210KB opaque blob             │
// └────────────────────────────────────┘
//
// Design Notes:
// -------------
// - Metadata is JSON for easy inspection and forward compatibility
// - Disk paths are stored for reference only (Option C: no auto-remount)
// - Breakpoints are NOT stored (Option A: clear on load)
// - REPL mode IS restored (user's preference)
// - Version 2 is NOT backward compatible with version 1
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - State File Constants
// =============================================================================

/// Constants for state file format.
public enum StateFileConstants {
    /// Magic bytes identifying an Attic state file ("ATTC").
    public static let magic: [UInt8] = [0x41, 0x54, 0x54, 0x43]

    /// Current file format version.
    public static let version: UInt8 = 0x02

    /// Size of the file header in bytes.
    public static let headerSize: Int = 16

    /// Size of state tags structure in bytes.
    public static let tagsSize: Int = 32

    /// Size of state flags structure in bytes.
    /// StateFlags has Bool + UInt32, which Swift pads to 8 bytes.
    public static let flagsSize: Int = 8

    /// File extension for state files.
    public static let fileExtension = "attic"
}

// =============================================================================
// MARK: - State File Flags
// =============================================================================

/// Flags stored in the file header.
public struct StateFileFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// State includes BASIC program in memory.
    public static let hasBasicProgram = StateFileFlags(rawValue: 1 << 0)

    /// State was saved while emulator was paused.
    public static let wasPaused = StateFileFlags(rawValue: 1 << 1)

    /// Reserved for future use.
    public static let reserved2 = StateFileFlags(rawValue: 1 << 2)
    public static let reserved3 = StateFileFlags(rawValue: 1 << 3)
}

// =============================================================================
// MARK: - Mounted Disk Reference
// =============================================================================

/// Reference to a mounted disk at save time.
///
/// This stores the path and drive number for informational purposes.
/// Disks are NOT automatically remounted on load (per design decision).
public struct MountedDiskReference: Codable, Sendable, Equatable {
    /// The drive number (1-8).
    public let drive: Int

    /// The path to the ATR file at save time.
    public let path: String

    /// The disk type name (e.g., "SS/SD", "SS/ED").
    public let diskType: String

    /// Whether the disk was mounted read-only.
    public let readOnly: Bool

    public init(drive: Int, path: String, diskType: String, readOnly: Bool) {
        self.drive = drive
        self.path = path
        self.diskType = diskType
        self.readOnly = readOnly
    }
}

// =============================================================================
// MARK: - REPL Mode Reference
// =============================================================================

/// Serializable representation of REPL mode.
///
/// This mirrors `REPLMode` but uses simple types for JSON encoding.
public struct REPLModeReference: Codable, Sendable, Equatable {
    /// The mode type: "monitor", "basic", or "dos".
    public let mode: String

    /// For BASIC mode, the variant: "atari" or "turbo".
    public let basicVariant: String?

    public init(mode: String, basicVariant: String? = nil) {
        self.mode = mode
        self.basicVariant = basicVariant
    }

    /// Creates a reference from a REPLMode.
    public init(from replMode: REPLMode) {
        switch replMode {
        case .monitor:
            self.mode = "monitor"
            self.basicVariant = nil
        case .basic(let variant):
            self.mode = "basic"
            switch variant {
            case .atari:
                self.basicVariant = "atari"
            case .turbo:
                self.basicVariant = "turbo"
            }
        case .dos:
            self.mode = "dos"
            self.basicVariant = nil
        }
    }

    /// Converts back to a REPLMode.
    public func toREPLMode() -> REPLMode {
        switch mode {
        case "monitor":
            return .monitor
        case "basic":
            let variant: REPLMode.BasicVariant = (basicVariant == "turbo") ? .turbo : .atari
            return .basic(variant: variant)
        case "dos":
            return .dos
        default:
            // Default to BASIC if unknown
            return .basic(variant: .atari)
        }
    }
}

// =============================================================================
// MARK: - State Metadata
// =============================================================================

/// Metadata stored alongside emulator state.
///
/// This captures contextual information about the emulator session at save
/// time. The metadata is encoded as JSON within the state file.
public struct StateMetadata: Codable, Sendable {
    /// ISO 8601 timestamp when the state was saved.
    public let timestamp: String

    /// The REPL mode at save time.
    public let replMode: REPLModeReference

    /// Disks that were mounted at save time (for reference only).
    public let mountedDisks: [MountedDiskReference]

    /// Optional description/note from user.
    public let note: String?

    /// Application version that created this state file.
    public let appVersion: String

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    public init(
        timestamp: String,
        replMode: REPLModeReference,
        mountedDisks: [MountedDiskReference],
        note: String? = nil,
        appVersion: String = "1.0.0"
    ) {
        self.timestamp = timestamp
        self.replMode = replMode
        self.mountedDisks = mountedDisks
        self.note = note
        self.appVersion = appVersion
    }

    /// Creates metadata with current timestamp.
    public static func create(
        replMode: REPLMode,
        mountedDisks: [MountedDiskReference],
        note: String? = nil
    ) -> StateMetadata {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        return StateMetadata(
            timestamp: timestamp,
            replMode: REPLModeReference(from: replMode),
            mountedDisks: mountedDisks,
            note: note
        )
    }

    // =========================================================================
    // MARK: - JSON Encoding
    // =========================================================================

    /// Encodes the metadata to JSON data.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]  // Deterministic output
        return try encoder.encode(self)
    }

    /// Decodes metadata from JSON data.
    public static func decode(from data: Data) throws -> StateMetadata {
        let decoder = JSONDecoder()
        return try decoder.decode(StateMetadata.self, from: data)
    }
}

// =============================================================================
// MARK: - State File Errors
// =============================================================================

/// Errors that can occur during state file operations.
public enum StateFileError: Error, LocalizedError, Sendable {
    /// The file does not have the correct magic bytes.
    case invalidMagic

    /// The file version is not supported.
    case unsupportedVersion(UInt8)

    /// The file is truncated or corrupted.
    case truncatedFile(expected: Int, actual: Int)

    /// Failed to parse metadata JSON.
    case invalidMetadata(String)

    /// The state data is invalid or corrupted.
    case invalidStateData(String)

    /// Failed to write state file.
    case writeFailed(String)

    /// Failed to read state file.
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMagic:
            return "Invalid state file: missing ATTC magic bytes"
        case .unsupportedVersion(let version):
            return "Unsupported state file version: \(version) (expected \(StateFileConstants.version))"
        case .truncatedFile(let expected, let actual):
            return "Truncated state file: expected at least \(expected) bytes, got \(actual)"
        case .invalidMetadata(let reason):
            return "Invalid state metadata: \(reason)"
        case .invalidStateData(let reason):
            return "Invalid state data: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write state file: \(reason)"
        case .readFailed(let reason):
            return "Failed to read state file: \(reason)"
        }
    }
}

// =============================================================================
// MARK: - State File Reader/Writer
// =============================================================================

/// Handles reading and writing state files in v2 format.
public struct StateFileHandler {

    // =========================================================================
    // MARK: - Writing
    // =========================================================================

    /// Writes a complete state file.
    ///
    /// - Parameters:
    ///   - url: The destination file URL.
    ///   - metadata: The session metadata.
    ///   - state: The emulator state from libatari800.
    ///   - flags: Optional file flags.
    /// - Throws: StateFileError if writing fails.
    public static func write(
        to url: URL,
        metadata: StateMetadata,
        state: EmulatorState,
        flags: StateFileFlags = []
    ) throws {
        var fileData = Data()

        // -----------------------------------------------------------------
        // Header (16 bytes)
        // -----------------------------------------------------------------

        // Magic bytes "ATTC"
        fileData.append(contentsOf: StateFileConstants.magic)

        // Version
        fileData.append(StateFileConstants.version)

        // Flags
        fileData.append(flags.rawValue)

        // Reserved (10 bytes)
        fileData.append(contentsOf: [UInt8](repeating: 0, count: 10))

        // -----------------------------------------------------------------
        // Metadata (length-prefixed JSON)
        // -----------------------------------------------------------------

        let metadataJSON: Data
        do {
            metadataJSON = try metadata.encode()
        } catch {
            throw StateFileError.invalidMetadata(error.localizedDescription)
        }

        // Write length as 4-byte little-endian
        var metadataLength = UInt32(metadataJSON.count)
        withUnsafeBytes(of: &metadataLength) { fileData.append(contentsOf: $0) }

        // Write JSON data
        fileData.append(metadataJSON)

        // -----------------------------------------------------------------
        // State Tags (32 bytes)
        // -----------------------------------------------------------------

        var tags = state.tags
        withUnsafeBytes(of: &tags) { fileData.append(contentsOf: $0) }

        // -----------------------------------------------------------------
        // State Flags (8 bytes from EmulatorState, padded to 40)
        // -----------------------------------------------------------------

        var stateFlags = state.flags
        withUnsafeBytes(of: &stateFlags) { fileData.append(contentsOf: $0) }

        // -----------------------------------------------------------------
        // State Data (opaque libatari800 blob)
        // -----------------------------------------------------------------

        fileData.append(contentsOf: state.data)

        // -----------------------------------------------------------------
        // Write to file
        // -----------------------------------------------------------------

        do {
            try fileData.write(to: url)
        } catch {
            throw StateFileError.writeFailed(error.localizedDescription)
        }
    }

    // =========================================================================
    // MARK: - Reading
    // =========================================================================

    /// Reads a complete state file.
    ///
    /// - Parameter url: The source file URL.
    /// - Returns: A tuple containing the metadata and emulator state.
    /// - Throws: StateFileError if reading fails.
    public static func read(from url: URL) throws -> (metadata: StateMetadata, state: EmulatorState) {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw StateFileError.readFailed(error.localizedDescription)
        }

        // -----------------------------------------------------------------
        // Validate minimum size for header
        // -----------------------------------------------------------------

        guard fileData.count >= StateFileConstants.headerSize + 4 else {
            throw StateFileError.truncatedFile(
                expected: StateFileConstants.headerSize + 4,
                actual: fileData.count
            )
        }

        // -----------------------------------------------------------------
        // Validate magic bytes
        // -----------------------------------------------------------------

        let magic = Array(fileData.prefix(4))
        guard magic == StateFileConstants.magic else {
            throw StateFileError.invalidMagic
        }

        // -----------------------------------------------------------------
        // Check version
        // -----------------------------------------------------------------

        let version = fileData[4]
        guard version == StateFileConstants.version else {
            throw StateFileError.unsupportedVersion(version)
        }

        // Flags at offset 5 (currently unused on read)
        // Reserved at offsets 6-15

        var offset = StateFileConstants.headerSize

        // -----------------------------------------------------------------
        // Read metadata length and JSON
        // -----------------------------------------------------------------

        guard fileData.count >= offset + 4 else {
            throw StateFileError.truncatedFile(expected: offset + 4, actual: fileData.count)
        }

        let metadataLength = fileData.subdata(in: offset..<(offset + 4))
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4

        guard fileData.count >= offset + Int(metadataLength) else {
            throw StateFileError.truncatedFile(
                expected: offset + Int(metadataLength),
                actual: fileData.count
            )
        }

        let metadataJSON = fileData.subdata(in: offset..<(offset + Int(metadataLength)))
        offset += Int(metadataLength)

        let metadata: StateMetadata
        do {
            metadata = try StateMetadata.decode(from: metadataJSON)
        } catch {
            throw StateFileError.invalidMetadata(error.localizedDescription)
        }

        // -----------------------------------------------------------------
        // Read state tags (32 bytes)
        // -----------------------------------------------------------------

        guard fileData.count >= offset + StateFileConstants.tagsSize else {
            throw StateFileError.truncatedFile(
                expected: offset + StateFileConstants.tagsSize,
                actual: fileData.count
            )
        }

        var state = EmulatorState()
        let tagsData = fileData.subdata(in: offset..<(offset + StateFileConstants.tagsSize))
        tagsData.withUnsafeBytes { ptr in
            state.tags.size = ptr.load(fromByteOffset: 0, as: UInt32.self)
            state.tags.cpu = ptr.load(fromByteOffset: 4, as: UInt32.self)
            state.tags.pc = ptr.load(fromByteOffset: 8, as: UInt32.self)
            state.tags.baseRam = ptr.load(fromByteOffset: 12, as: UInt32.self)
            state.tags.antic = ptr.load(fromByteOffset: 16, as: UInt32.self)
            state.tags.gtia = ptr.load(fromByteOffset: 20, as: UInt32.self)
            state.tags.pia = ptr.load(fromByteOffset: 24, as: UInt32.self)
            state.tags.pokey = ptr.load(fromByteOffset: 28, as: UInt32.self)
        }
        offset += StateFileConstants.tagsSize

        // -----------------------------------------------------------------
        // Read state flags (40 bytes)
        // -----------------------------------------------------------------

        guard fileData.count >= offset + StateFileConstants.flagsSize else {
            throw StateFileError.truncatedFile(
                expected: offset + StateFileConstants.flagsSize,
                actual: fileData.count
            )
        }

        let flagsData = fileData.subdata(in: offset..<(offset + StateFileConstants.flagsSize))
        flagsData.withUnsafeBytes { ptr in
            state.flags.selfTestEnabled = ptr.load(fromByteOffset: 0, as: UInt8.self) != 0
            state.flags.frameCount = ptr.load(fromByteOffset: 4, as: UInt32.self)
        }
        offset += StateFileConstants.flagsSize

        // -----------------------------------------------------------------
        // Read state data (rest of file)
        // -----------------------------------------------------------------

        state.data = Array(fileData.suffix(from: offset))

        return (metadata, state)
    }

    // =========================================================================
    // MARK: - Metadata Only
    // =========================================================================

    /// Reads only the metadata from a state file (faster, no state parsing).
    ///
    /// - Parameter url: The source file URL.
    /// - Returns: The state metadata.
    /// - Throws: StateFileError if reading fails.
    public static func readMetadata(from url: URL) throws -> StateMetadata {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw StateFileError.readFailed(error.localizedDescription)
        }

        // Validate minimum size
        guard fileData.count >= StateFileConstants.headerSize + 4 else {
            throw StateFileError.truncatedFile(
                expected: StateFileConstants.headerSize + 4,
                actual: fileData.count
            )
        }

        // Validate magic
        let magic = Array(fileData.prefix(4))
        guard magic == StateFileConstants.magic else {
            throw StateFileError.invalidMagic
        }

        // Check version
        let version = fileData[4]
        guard version == StateFileConstants.version else {
            throw StateFileError.unsupportedVersion(version)
        }

        // Read metadata length
        var offset = StateFileConstants.headerSize
        let metadataLength = fileData.subdata(in: offset..<(offset + 4))
            .withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4

        guard fileData.count >= offset + Int(metadataLength) else {
            throw StateFileError.truncatedFile(
                expected: offset + Int(metadataLength),
                actual: fileData.count
            )
        }

        let metadataJSON = fileData.subdata(in: offset..<(offset + Int(metadataLength)))

        do {
            return try StateMetadata.decode(from: metadataJSON)
        } catch {
            throw StateFileError.invalidMetadata(error.localizedDescription)
        }
    }
}
