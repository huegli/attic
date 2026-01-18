// =============================================================================
// DiskManager.swift - Mounted Disk Management for DOS Mode
// =============================================================================
//
// This file provides thread-safe management of mounted ATR disk images.
// The DiskManager actor maintains the state of up to 8 virtual disk drives
// (D1: through D8:) and provides operations for mounting, unmounting, and
// accessing files on the mounted disks.
//
// Key Features:
// - Thread-safe disk operations via Swift actor isolation
// - Support for 8 virtual drives (matching Atari's drive numbering)
// - Direct ATR file parsing (independent of emulator's disk handling)
// - File system operations on mounted disks
//
// Architecture Notes:
// - DiskManager provides direct host access to ATR contents
// - This is separate from the emulator's disk I/O (which goes through libatari800)
// - Use DiskManager for REPL disk operations (dir, type, export, etc.)
// - Use EmulatorEngine.mountDisk for emulator disk access (BASIC OPEN, etc.)
//
// Usage:
//
//     let manager = DiskManager()
//
//     // Mount a disk
//     try await manager.mount(drive: 1, path: "/path/to/disk.atr")
//
//     // List files
//     let files = try await manager.listDirectory(drive: 1)
//
//     // Read a file
//     let data = try await manager.readFile(drive: 1, name: "GAME.COM")
//
//     // Unmount
//     await manager.unmount(drive: 1)
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Disk Manager Error Types
// =============================================================================

/// Errors specific to disk management operations.
public enum DiskManagerError: Error, LocalizedError, Sendable {
    /// The specified drive number is out of range (must be 1-8).
    case invalidDrive(Int)

    /// No disk is mounted in the specified drive.
    case driveEmpty(Int)

    /// A disk is already mounted in the specified drive.
    case driveInUse(Int)

    /// Failed to mount the disk image.
    case mountFailed(String)

    /// The specified path does not exist or is not accessible.
    case pathNotFound(String)

    /// Cannot perform operation on read-only disk.
    case diskReadOnly(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDrive(let drive):
            return "Invalid drive number: \(drive) (must be 1-8)"
        case .driveEmpty(let drive):
            return "Drive D\(drive): is empty"
        case .driveInUse(let drive):
            return "Drive D\(drive): already has a disk mounted"
        case .mountFailed(let reason):
            return "Failed to mount disk: \(reason)"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .diskReadOnly(let drive):
            return "Disk in D\(drive): is read-only"
        }
    }
}

// =============================================================================
// MARK: - Mounted Disk Information
// =============================================================================

/// Information about a mounted disk.
public struct MountedDiskInfo: Sendable {
    /// The drive number (1-8).
    public let drive: Int

    /// The full path to the ATR file.
    public let path: String

    /// The filename only (no directory).
    public let filename: String

    /// The disk type (SS/SD, SS/ED, SS/DD, etc.).
    public let diskType: ATRDiskType?

    /// Number of free sectors.
    public let freeSectors: Int

    /// Number of files on the disk.
    public let fileCount: Int

    /// Whether the disk is mounted read-only.
    public let isReadOnly: Bool

    /// Whether the disk has unsaved changes.
    public let isModified: Bool
}

// =============================================================================
// MARK: - Disk Manager Actor
// =============================================================================

/// Manages mounted ATR disk images for DOS mode operations.
///
/// DiskManager is an actor that provides thread-safe access to up to 8 virtual
/// disk drives. It handles mounting/unmounting disks and provides file system
/// operations on the mounted disks.
///
/// This is separate from the emulator's disk handling - DiskManager provides
/// direct host-side access to ATR file contents for REPL commands, while the
/// emulator handles its own disk I/O through libatari800.
public actor DiskManager {
    // =========================================================================
    // MARK: - Constants
    // =========================================================================

    /// Maximum number of drives (1-8).
    public static let maxDrives = 8

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Mounted disks indexed by drive number (1-8).
    /// Index 0 is unused to match Atari's 1-based drive numbering.
    private var mountedDisks: [Int: MountedDisk] = [:]

    /// The current drive for DOS mode operations.
    private(set) public var currentDrive: Int = 1

    // =========================================================================
    // MARK: - Internal Types
    // =========================================================================

    /// Internal structure to hold disk and file system references.
    private struct MountedDisk {
        let image: ATRImage
        let fileSystem: AtariFileSystem
        let path: String
        let isReadOnly: Bool
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new disk manager with no mounted disks.
    public init() {}

    // =========================================================================
    // MARK: - Drive Operations
    // =========================================================================

    /// Mounts an ATR disk image in the specified drive.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8).
    ///   - path: The path to the ATR file.
    ///   - readOnly: Whether to mount read-only (default: false).
    /// - Returns: Information about the mounted disk.
    /// - Throws: DiskManagerError or ATRError.
    @discardableResult
    public func mount(drive: Int, path: String, readOnly: Bool = false) throws -> MountedDiskInfo {
        // Validate drive number
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            throw DiskManagerError.invalidDrive(drive)
        }

        // Check if drive is already in use
        if mountedDisks[drive] != nil {
            throw DiskManagerError.driveInUse(drive)
        }

        // Expand path and check if file exists
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw DiskManagerError.pathNotFound(path)
        }

        // Load the ATR image
        let image: ATRImage
        do {
            image = try ATRImage(url: url, readOnly: readOnly)
        } catch {
            throw DiskManagerError.mountFailed(error.localizedDescription)
        }

        // Create file system interface
        let fileSystem = AtariFileSystem(disk: image)

        // Store the mounted disk
        mountedDisks[drive] = MountedDisk(
            image: image,
            fileSystem: fileSystem,
            path: expandedPath,
            isReadOnly: readOnly
        )

        // Return info about the mounted disk
        return try getInfo(drive: drive)
    }

    /// Unmounts the disk in the specified drive.
    ///
    /// - Parameter drive: The drive number (1-8).
    /// - Parameter save: Whether to save changes before unmounting (default: true).
    /// - Throws: DiskManagerError if drive is invalid or empty.
    public func unmount(drive: Int, save: Bool = true) throws {
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            throw DiskManagerError.invalidDrive(drive)
        }

        guard let mounted = mountedDisks[drive] else {
            throw DiskManagerError.driveEmpty(drive)
        }

        // Save changes if requested and disk is modified
        if save && mounted.image.isModified && !mounted.isReadOnly {
            try mounted.image.save()
        }

        // Remove from mounted disks
        mountedDisks.removeValue(forKey: drive)

        // If current drive was unmounted, switch to drive 1
        if currentDrive == drive {
            currentDrive = 1
        }
    }

    /// Changes the current drive.
    ///
    /// - Parameter drive: The drive number (1-8).
    /// - Throws: DiskManagerError if drive is invalid or empty.
    public func changeDrive(to drive: Int) throws {
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            throw DiskManagerError.invalidDrive(drive)
        }

        guard mountedDisks[drive] != nil else {
            throw DiskManagerError.driveEmpty(drive)
        }

        currentDrive = drive
    }

    /// Returns information about all mounted drives.
    ///
    /// - Returns: Array of drive information for all 8 drives.
    public func listDrives() -> [DriveStatus] {
        var status: [DriveStatus] = []

        for drive in 1...DiskManager.maxDrives {
            if let mounted = mountedDisks[drive] {
                do {
                    let stats = try mounted.fileSystem.getDiskStats()
                    status.append(DriveStatus(
                        drive: drive,
                        mounted: true,
                        path: mounted.path,
                        diskType: mounted.image.diskType,
                        freeSectors: stats.freeSectors,
                        fileCount: stats.fileCount,
                        isReadOnly: mounted.isReadOnly,
                        isModified: mounted.image.isModified
                    ))
                } catch {
                    // If we can't read stats, still report as mounted
                    status.append(DriveStatus(
                        drive: drive,
                        mounted: true,
                        path: mounted.path,
                        diskType: mounted.image.diskType,
                        freeSectors: 0,
                        fileCount: 0,
                        isReadOnly: mounted.isReadOnly,
                        isModified: mounted.image.isModified
                    ))
                }
            } else {
                status.append(DriveStatus(
                    drive: drive,
                    mounted: false,
                    path: nil,
                    diskType: nil,
                    freeSectors: 0,
                    fileCount: 0,
                    isReadOnly: false,
                    isModified: false
                ))
            }
        }

        return status
    }

    /// Gets detailed information about a mounted disk.
    ///
    /// - Parameter drive: The drive number (1-8).
    /// - Returns: Information about the mounted disk.
    /// - Throws: DiskManagerError if drive is invalid or empty.
    public func getInfo(drive: Int) throws -> MountedDiskInfo {
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            throw DiskManagerError.invalidDrive(drive)
        }

        guard let mounted = mountedDisks[drive] else {
            throw DiskManagerError.driveEmpty(drive)
        }

        let stats = try mounted.fileSystem.getDiskStats()
        let url = URL(fileURLWithPath: mounted.path)

        return MountedDiskInfo(
            drive: drive,
            path: mounted.path,
            filename: url.lastPathComponent,
            diskType: mounted.image.diskType,
            freeSectors: stats.freeSectors,
            fileCount: stats.fileCount,
            isReadOnly: mounted.isReadOnly,
            isModified: mounted.image.isModified
        )
    }

    // =========================================================================
    // MARK: - File System Operations
    // =========================================================================

    /// Lists files in the specified drive.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - pattern: Optional wildcard pattern (e.g., "*.COM").
    /// - Returns: Array of directory entries.
    /// - Throws: DiskManagerError or FileSystemError.
    public func listDirectory(drive: Int? = nil, pattern: String? = nil) throws -> [DirectoryEntry] {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        return try mounted.fileSystem.listFiles(matching: pattern)
    }

    /// Gets information about a specific file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename.
    /// - Returns: File information.
    /// - Throws: DiskManagerError or FileSystemError.
    public func getFileInfo(drive: Int? = nil, name: String) throws -> FileInfo {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        return try mounted.fileSystem.getFileInfo(named: name)
    }

    /// Reads a file's contents.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename.
    /// - Returns: The file data.
    /// - Throws: DiskManagerError or FileSystemError.
    public func readFile(drive: Int? = nil, name: String) throws -> Data {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        return try mounted.fileSystem.readFile(named: name)
    }

    /// Deletes a file from the disk.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to delete.
    /// - Throws: DiskManagerError or FileSystemError.
    public func deleteFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.deleteFile(named: name)
    }

    /// Renames a file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - oldName: The current filename.
    ///   - newName: The new filename.
    /// - Throws: DiskManagerError or FileSystemError.
    public func renameFile(drive: Int? = nil, from oldName: String, to newName: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.renameFile(from: oldName, to: newName)
    }

    /// Locks a file (makes it read-only).
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to lock.
    /// - Throws: DiskManagerError or FileSystemError.
    public func lockFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.lockFile(named: name)
    }

    /// Unlocks a file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to unlock.
    /// - Throws: DiskManagerError or FileSystemError.
    public func unlockFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.unlockFile(named: name)
    }

    // =========================================================================
    // MARK: - Host Transfer Operations
    // =========================================================================

    /// Exports a file from the disk to the host file system.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename on the disk.
    ///   - hostPath: The destination path on the host.
    /// - Returns: The number of bytes exported.
    /// - Throws: DiskManagerError, FileSystemError, or file write error.
    @discardableResult
    public func exportFile(drive: Int? = nil, name: String, to hostPath: String) throws -> Int {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        // Read file from disk
        let data = try mounted.fileSystem.readFile(named: name)

        // Expand path and write to host
        let expandedPath = NSString(string: hostPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        try data.write(to: url)

        return data.count
    }

    /// Imports a file from the host file system to the disk.
    ///
    /// Note: This is a placeholder for Phase 13 - full implementation requires
    /// file writing support in AtariFileSystem.
    ///
    /// - Parameters:
    ///   - hostPath: The source path on the host.
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to use on the disk.
    /// - Returns: The number of bytes imported.
    /// - Throws: DiskManagerError, FileSystemError, or file read error.
    @discardableResult
    public func importFile(from hostPath: String, drive: Int? = nil, name: String) throws -> Int {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        // Read file from host
        let expandedPath = NSString(string: hostPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw DiskManagerError.pathNotFound(hostPath)
        }

        let data = try Data(contentsOf: url)

        // TODO: Implement file writing in AtariFileSystem
        // For now, throw a not-implemented error
        throw FileSystemError.invalidFilename("File import not yet implemented (requires Phase 12 write support)")
    }

    // =========================================================================
    // MARK: - Disk Creation
    // =========================================================================

    /// Creates a new, empty ATR disk image.
    ///
    /// - Parameters:
    ///   - path: The path where the ATR should be created.
    ///   - type: The disk type (default: single density).
    /// - Returns: Information about the created disk.
    /// - Throws: ATRError if creation fails.
    @discardableResult
    public func createDisk(at path: String, type: ATRDiskType = .singleDensity) throws -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Create the ATR image
        let image = try ATRImage.create(at: url, type: type)

        // Format with DOS 2.x filesystem
        let fs = AtariFileSystem(disk: image)
        try fs.format()

        // Save changes
        try image.save()

        return url
    }

    /// Formats the disk in the specified drive.
    ///
    /// WARNING: This erases all data on the disk!
    ///
    /// - Parameter drive: The drive number (1-8), or nil for current drive.
    /// - Throws: DiskManagerError or ATRError.
    public func formatDisk(drive: Int? = nil) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.format()
    }

    // =========================================================================
    // MARK: - Save Operations
    // =========================================================================

    /// Saves changes to the disk in the specified drive.
    ///
    /// - Parameter drive: The drive number (1-8), or nil for current drive.
    /// - Throws: DiskManagerError or ATRError.
    public func saveDisk(drive: Int? = nil) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.image.save()
    }

    /// Saves all modified disks.
    ///
    /// - Returns: Number of disks saved.
    @discardableResult
    public func saveAllDisks() throws -> Int {
        var saved = 0

        for (_, mounted) in mountedDisks {
            if mounted.image.isModified && !mounted.isReadOnly {
                try mounted.image.save()
                saved += 1
            }
        }

        return saved
    }

    /// Checks if the specified drive has a disk mounted.
    ///
    /// - Parameter drive: The drive number (1-8).
    /// - Returns: True if a disk is mounted.
    public func isDriveMounted(_ drive: Int) -> Bool {
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            return false
        }
        return mountedDisks[drive] != nil
    }
}

// =============================================================================
// MARK: - Drive Status Structure
// =============================================================================

/// Status information for a drive.
public struct DriveStatus: Sendable {
    /// The drive number (1-8).
    public let drive: Int

    /// Whether a disk is mounted in this drive.
    public let mounted: Bool

    /// The path to the mounted ATR file (nil if empty).
    public let path: String?

    /// The disk type (nil if empty or unknown).
    public let diskType: ATRDiskType?

    /// Number of free sectors (0 if empty).
    public let freeSectors: Int

    /// Number of files on the disk (0 if empty).
    public let fileCount: Int

    /// Whether the disk is mounted read-only.
    public let isReadOnly: Bool

    /// Whether the disk has unsaved changes.
    public let isModified: Bool

    /// Formatted description for display.
    public var displayString: String {
        if mounted {
            let typeStr = diskType?.shortDescription ?? "???"
            let filename = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
            let roStr = isReadOnly ? " [R/O]" : ""
            let modStr = isModified ? "*" : ""
            return "D\(drive): \(filename) (\(typeStr), \(fileCount) files, \(freeSectors) free)\(roStr)\(modStr)"
        } else {
            return "D\(drive): (empty)"
        }
    }
}
