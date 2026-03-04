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
// - Coordinated mount/unmount with EmulatorEngine (libatari800)
// - Direct ATR file parsing for REPL file operations
// - File system operations on mounted disks
//
// Architecture Notes:
// - DiskManager is the SINGLE API for all disk mount/unmount operations.
// - When an EmulatorEngine is provided, mount() calls EmulatorEngine.mountDisk()
//   first (so libatari800 can access the disk), then parses the ATR for
//   Swift-side file operations. unmount() removes tracking then calls
//   EmulatorEngine.unmountDisk().
// - AtticServer and other callers should NEVER call EmulatorEngine.mountDisk()
//   or unmountDisk() directly — always go through DiskManager.
// - Without an emulator (standalone mode), only Swift-side parsing is done.
//
// Usage:
//
//     let manager = DiskManager(emulator: engine)
//
//     // Mount a disk (also mounts in the emulator)
//     try await manager.mount(drive: 1, path: "/path/to/disk.atr")
//
//     // List files
//     let files = try await manager.listDirectory(drive: 1)
//
//     // Read a file
//     let data = try await manager.readFile(drive: 1, name: "GAME.COM")
//
//     // Write a file
//     try await manager.writeFile(drive: 1, name: "HELLO.TXT", data: data)
//
//     // Unmount (also unmounts from the emulator)
//     try await manager.unmount(drive: 1)
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
    public let diskType: DiskType

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
    public let diskType: DiskType?

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
            let typeStr = diskType?.shortName ?? "???"
            let filename = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
            let roStr = isReadOnly ? " [R/O]" : ""
            let modStr = isModified ? "*" : ""
            return "D\(drive): \(filename) (\(typeStr), \(fileCount) files, \(freeSectors) free)\(roStr)\(modStr)"
        } else {
            return "D\(drive): (empty)"
        }
    }
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
/// DiskManager is the single API for all disk operations. When an EmulatorEngine
/// is provided, mount/unmount operations are coordinated with the emulator's
/// C library (libatari800) so that both the emulator and the Swift-side file
/// system view stay in sync.
///
/// Usage:
///   - For server/CLI use: `DiskManager(emulator: engine)` — mount/unmount
///     calls are forwarded to the emulator automatically.
///   - For standalone ATR inspection (no emulator): `DiskManager()` — only
///     Swift-side parsing is performed.
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
    private var mountedDisks: [Int: MountedDisk] = [:]

    /// The current drive for DOS mode operations.
    private(set) public var currentDrive: Int = 1

    /// Optional reference to the emulator engine.
    /// When set, mount/unmount operations are forwarded to the emulator
    /// so that libatari800's disk I/O stays in sync with DiskManager's
    /// file system view.
    private let emulator: EmulatorEngine?

    // =========================================================================
    // MARK: - Internal Types
    // =========================================================================

    /// Internal structure to hold disk and file system references.
    private struct MountedDisk {
        let image: ATRImage
        let fileSystem: ATRFileSystem
        let path: String
        let isReadOnly: Bool
    }

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new disk manager with no mounted disks.
    ///
    /// - Parameter emulator: Optional emulator engine. When provided,
    ///   mount/unmount operations are coordinated with the emulator's
    ///   C library so that disk I/O works from both the REPL and the
    ///   emulated Atari OS.
    public init(emulator: EmulatorEngine? = nil) {
        self.emulator = emulator
    }

    // =========================================================================
    // MARK: - Drive Operations
    // =========================================================================

    /// Mounts an ATR disk image in the specified drive.
    ///
    /// When an emulator is attached, the disk is first mounted in the emulator's
    /// C library (libatari800) so that the emulated Atari OS can access it. If
    /// the emulator mount fails, the operation is aborted. If the emulator mount
    /// succeeds but ATR parsing fails, the disk is unmounted from the emulator
    /// before the error is propagated.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8).
    ///   - path: The path to the ATR file.
    ///   - readOnly: Whether to mount read-only (default: false).
    /// - Returns: Information about the mounted disk.
    /// - Throws: DiskManagerError or ATRError.
    @discardableResult
    public func mount(drive: Int, path: String, readOnly: Bool = false) async throws -> MountedDiskInfo {
        // Validate drive number
        guard drive >= 1 && drive <= DiskManager.maxDrives else {
            throw DiskManagerError.invalidDrive(drive)
        }

        // Check if drive is already in use
        if mountedDisks[drive] != nil {
            throw DiskManagerError.driveInUse(drive)
        }

        // Expand path and check if file exists
        let expandedPath = path.expandingPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw DiskManagerError.pathNotFound(path)
        }

        // Step 1: Mount in the emulator (if attached) so libatari800 can access the disk.
        // This must succeed before we invest effort in ATR parsing.
        if let emulator = emulator {
            let ok = await emulator.mountDisk(drive: drive, path: expandedPath, readOnly: readOnly)
            guard ok else {
                throw DiskManagerError.mountFailed("Emulator rejected disk image at \(path)")
            }
        }

        // Step 2: Parse the ATR image on the Swift side for REPL file operations.
        let image: ATRImage
        do {
            image = try ATRImage(url: url, readOnly: readOnly)
        } catch {
            // ATR parse failed — roll back the emulator mount so drives stay in sync.
            if let emulator = emulator {
                await emulator.unmountDisk(drive: drive)
            }
            throw DiskManagerError.mountFailed(error.localizedDescription)
        }

        // Step 3: Create file system interface.
        let fileSystem: ATRFileSystem
        do {
            fileSystem = try ATRFileSystem(disk: image)
        } catch {
            if let emulator = emulator {
                await emulator.unmountDisk(drive: drive)
            }
            throw DiskManagerError.mountFailed(error.localizedDescription)
        }

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

    /// Registers a disk that was mounted externally (e.g. via `bootFile()`).
    ///
    /// When `libatari800_reboot_with_file()` boots a disk image, the C library
    /// mounts it on D1 internally. DiskManager doesn't know about this mount
    /// because it bypassed `mount()`. This method updates Swift-side tracking
    /// so `listDrives()` reports the booted disk correctly.
    ///
    /// Unlike `mount()`, this does NOT call `emulator.mountDisk()` since the
    /// C library already has the disk mounted.
    ///
    /// If ATR parsing fails (e.g. the file isn't a valid disk image), the
    /// tracking is silently skipped — the disk still works in the emulator,
    /// it just won't appear in `listDrives()`.
    ///
    /// - Parameters:
    ///   - drive: The drive number the file was mounted on (typically 1).
    ///   - path: The full path to the disk image file.
    public func trackBootedDisk(drive: Int, path: String) {
        guard drive >= 1 && drive <= DiskManager.maxDrives else { return }

        let expandedPath = path.expandingPath
        let url = URL(fileURLWithPath: expandedPath)

        // Clear any previous tracking for this drive
        mountedDisks.removeValue(forKey: drive)

        // Try to parse the ATR image — if it fails, the file isn't a valid
        // disk image (could be an XEX, BAS, etc.) so we just skip tracking.
        guard let image = try? ATRImage(url: url, readOnly: false) else { return }
        guard let fileSystem = try? ATRFileSystem(disk: image) else { return }

        mountedDisks[drive] = MountedDisk(
            image: image,
            fileSystem: fileSystem,
            path: expandedPath,
            isReadOnly: false
        )
    }

    /// Unmounts the disk in the specified drive.
    ///
    /// Removes Swift-side tracking first, then unmounts from the emulator
    /// (if attached) so that libatari800 stops accessing the disk image.
    ///
    /// - Parameter drive: The drive number (1-8).
    /// - Parameter save: Whether to save changes before unmounting (default: true).
    /// - Throws: DiskManagerError if drive is invalid or empty.
    public func unmount(drive: Int, save: Bool = true) async throws {
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

        // Remove from mounted disks (Swift-side tracking)
        mountedDisks.removeValue(forKey: drive)

        // Unmount from the emulator so libatari800 stops accessing the file
        if let emulator = emulator {
            await emulator.unmountDisk(drive: drive)
        }

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
                    let info = try mounted.fileSystem.getDiskInfo()
                    status.append(DriveStatus(
                        drive: drive,
                        mounted: true,
                        path: mounted.path,
                        diskType: mounted.image.diskType,
                        freeSectors: info.freeSectors,
                        fileCount: info.fileCount,
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

        let info = try mounted.fileSystem.getDiskInfo()
        let url = URL(fileURLWithPath: mounted.path)

        return MountedDiskInfo(
            drive: drive,
            path: mounted.path,
            filename: url.lastPathComponent,
            diskType: mounted.image.diskType,
            freeSectors: info.freeSectors,
            fileCount: info.fileCount,
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
    /// - Throws: DiskManagerError or ATRError.
    public func listDirectory(drive: Int? = nil, pattern: String? = nil) throws -> [DirectoryEntry] {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        if let pattern = pattern {
            return try mounted.fileSystem.listFiles(matching: pattern)
        } else {
            return try mounted.fileSystem.listDirectory()
        }
    }

    /// Gets information about a specific file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename.
    /// - Returns: File information.
    /// - Throws: DiskManagerError or ATRError.
    public func getFileInfo(drive: Int? = nil, name: String) throws -> ATRFileInfo {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        return try mounted.fileSystem.getFileInfo(name)
    }

    /// Reads a file's contents.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename.
    /// - Returns: The file data.
    /// - Throws: DiskManagerError or ATRError.
    public func readFile(drive: Int? = nil, name: String) throws -> Data {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        return try mounted.fileSystem.readFile(name)
    }

    /// Writes a file to the disk.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename.
    ///   - data: The file data.
    /// - Returns: The number of sectors used.
    /// - Throws: DiskManagerError or ATRError.
    @discardableResult
    public func writeFile(drive: Int? = nil, name: String, data: Data) throws -> Int {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        return try mounted.fileSystem.writeFile(name, data: data)
    }

    /// Deletes a file from the disk.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to delete.
    /// - Throws: DiskManagerError or ATRError.
    public func deleteFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.deleteFile(name)
    }

    /// Renames a file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - oldName: The current filename.
    ///   - newName: The new filename.
    /// - Throws: DiskManagerError or ATRError.
    public func renameFile(drive: Int? = nil, from oldName: String, to newName: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.renameFile(oldName, to: newName)
    }

    /// Locks a file (makes it read-only).
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to lock.
    /// - Throws: DiskManagerError or ATRError.
    public func lockFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.lockFile(name)
    }

    /// Unlocks a file.
    ///
    /// - Parameters:
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to unlock.
    /// - Throws: DiskManagerError or ATRError.
    public func unlockFile(drive: Int? = nil, name: String) throws {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        guard !mounted.isReadOnly else {
            throw DiskManagerError.diskReadOnly(driveNum)
        }

        try mounted.fileSystem.unlockFile(name)
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
    /// - Throws: DiskManagerError, ATRError, or file write error.
    @discardableResult
    public func exportFile(drive: Int? = nil, name: String, to hostPath: String) throws -> Int {
        let driveNum = drive ?? currentDrive

        guard let mounted = mountedDisks[driveNum] else {
            throw DiskManagerError.driveEmpty(driveNum)
        }

        // Read file from disk
        let data = try mounted.fileSystem.readFile(name)

        // Expand path and write to host
        let expandedPath = hostPath.expandingPath
        let url = URL(fileURLWithPath: expandedPath)

        try data.write(to: url)

        return data.count
    }

    /// Imports a file from the host file system to the disk.
    ///
    /// - Parameters:
    ///   - hostPath: The source path on the host.
    ///   - drive: The drive number (1-8), or nil for current drive.
    ///   - name: The filename to use on the disk.
    /// - Returns: The number of sectors used.
    /// - Throws: DiskManagerError, ATRError, or file read error.
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
        let expandedPath = hostPath.expandingPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw DiskManagerError.pathNotFound(hostPath)
        }

        return try mounted.fileSystem.importFile(from: url, as: name)
    }

    /// Copies a file from one disk to another.
    ///
    /// - Parameters:
    ///   - sourceDrive: The source drive number (1-8).
    ///   - sourceName: The source filename.
    ///   - destDrive: The destination drive number (1-8).
    ///   - destName: The destination filename (optional, defaults to source name).
    /// - Returns: The number of sectors used.
    /// - Throws: DiskManagerError or ATRError.
    @discardableResult
    public func copyFile(
        from sourceDrive: Int,
        name sourceName: String,
        to destDrive: Int,
        as destName: String? = nil
    ) throws -> Int {
        guard let sourceMount = mountedDisks[sourceDrive] else {
            throw DiskManagerError.driveEmpty(sourceDrive)
        }

        guard let destMount = mountedDisks[destDrive] else {
            throw DiskManagerError.driveEmpty(destDrive)
        }

        guard !destMount.isReadOnly else {
            throw DiskManagerError.diskReadOnly(destDrive)
        }

        // Read from source
        let data = try sourceMount.fileSystem.readFile(sourceName)

        // Write to destination
        let targetName = destName ?? sourceName
        return try destMount.fileSystem.writeFile(targetName, data: data)
    }

    // =========================================================================
    // MARK: - Disk Creation
    // =========================================================================

    /// Creates a new, empty ATR disk image.
    ///
    /// - Parameters:
    ///   - path: The path where the ATR should be created.
    ///   - type: The disk type (default: single density).
    /// - Returns: The URL of the created disk.
    /// - Throws: ATRError if creation fails.
    @discardableResult
    public func createDisk(at path: String, type: DiskType = .singleDensity) throws -> URL {
        let expandedPath = path.expandingPath
        let url = URL(fileURLWithPath: expandedPath)

        // Create formatted disk
        _ = try ATRImage.createFormatted(at: url, type: type)

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
