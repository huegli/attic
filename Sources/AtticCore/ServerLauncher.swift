// =============================================================================
// ServerLauncher.swift - AtticServer Auto-Launch Utility
// =============================================================================
//
// This file provides a shared utility for launching AtticServer as a subprocess.
// It is used by AtticCLI, AtticGUI, and AtticMCP to auto-start the server when
// one isn't already running.
//
// Usage:
//   let launcher = ServerLauncher()
//   if let socketPath = launcher.launchServer(silent: true) {
//       // Connect to socketPath
//   }
//
// The launcher searches for AtticServer in several locations:
// 1. Same directory as the current executable
// 2. PATH environment variable
// 3. Common installation locations (/usr/local/bin, /opt/homebrew/bin, etc.)
//
// =============================================================================

import Foundation

// MARK: - Server Launcher

/// Configuration options for launching AtticServer.
public struct ServerLaunchOptions: Sendable {
    /// Whether to disable audio output.
    public var silent: Bool

    /// Custom ROM path (optional).
    public var romPath: String?

    /// Whether to suppress stdout/stderr from the server process.
    public var suppressOutput: Bool

    /// Creates launch options with defaults.
    public init(
        silent: Bool = false,
        romPath: String? = nil,
        suppressOutput: Bool = true
    ) {
        self.silent = silent
        self.romPath = romPath
        self.suppressOutput = suppressOutput
    }
}

/// Result of a server launch attempt.
public enum ServerLaunchResult: Sendable {
    /// Server launched successfully.
    /// - socketPath: Path to the CLI socket.
    /// - pid: Process ID of the server.
    case success(socketPath: String, pid: Int32)

    /// Server executable not found.
    case executableNotFound

    /// Failed to start the process.
    case launchFailed(Error)

    /// Server started but socket didn't appear in time.
    case socketTimeout(pid: Int32)
}

/// Utility for finding and launching AtticServer.
///
/// This class provides methods to:
/// - Find an existing running AtticServer
/// - Launch a new AtticServer instance
/// - Wait for the server to be ready
///
/// Example usage:
/// ```swift
/// let launcher = ServerLauncher()
///
/// // Try to find existing server first
/// if let socketPath = launcher.discoverExistingServer() {
///     print("Found existing server at \(socketPath)")
/// } else {
///     // Launch new server
///     switch launcher.launchServer() {
///     case .success(let socketPath, let pid):
///         print("Launched server (PID: \(pid)) at \(socketPath)")
///     case .executableNotFound:
///         print("AtticServer not found")
///     case .launchFailed(let error):
///         print("Launch failed: \(error)")
///     case .socketTimeout(let pid):
///         print("Server started but socket not ready")
///     }
/// }
/// ```
public final class ServerLauncher: Sendable {

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    public init() {}

    // =========================================================================
    // MARK: - Server Discovery
    // =========================================================================

    /// Discovers an existing running AtticServer.
    ///
    /// Scans `/tmp/attic-*.sock` for available sockets.
    ///
    /// - Returns: Path to an existing socket, or nil if none found.
    public func discoverExistingServer() -> String? {
        let client = CLISocketClient()
        return client.discoverSocket()
    }

    // =========================================================================
    // MARK: - Server Launch
    // =========================================================================

    /// Launches AtticServer as a subprocess.
    ///
    /// This method:
    /// 1. Finds the AtticServer executable
    /// 2. Launches it with the specified options
    /// 3. Waits for the CLI socket to appear
    ///
    /// - Parameter options: Launch configuration options.
    /// - Returns: The launch result indicating success or failure mode.
    public func launchServer(options: ServerLaunchOptions = ServerLaunchOptions()) -> ServerLaunchResult {
        // Find the server executable
        guard let serverPath = findServerExecutable() else {
            return .executableNotFound
        }

        // Build arguments
        var arguments: [String] = []
        if options.silent {
            arguments.append("--silent")
        }
        if let romPath = options.romPath {
            arguments.append("--rom-path")
            arguments.append(romPath)
        }

        // Create and configure the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = arguments

        // Suppress output if requested
        if options.suppressOutput {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        // Launch the process
        do {
            try process.run()
        } catch {
            return .launchFailed(error)
        }

        let pid = process.processIdentifier
        let socketPath = CLIProtocolConstants.socketPath(for: pid)

        // Wait for socket to appear (with timeout)
        let maxRetries = 20  // 4 seconds total
        let retryInterval: TimeInterval = 0.2

        for _ in 0..<maxRetries {
            if FileManager.default.fileExists(atPath: socketPath) {
                return .success(socketPath: socketPath, pid: pid)
            }
            Thread.sleep(forTimeInterval: retryInterval)
        }

        return .socketTimeout(pid: pid)
    }

    /// Convenience method that discovers or launches a server.
    ///
    /// First tries to find an existing server. If none found, launches a new one.
    ///
    /// - Parameter options: Launch options if a new server needs to be started.
    /// - Returns: Socket path on success, nil on failure.
    public func ensureServerRunning(options: ServerLaunchOptions = ServerLaunchOptions()) -> String? {
        // Try to find existing server first
        if let existingSocket = discoverExistingServer() {
            return existingSocket
        }

        // Launch new server
        switch launchServer(options: options) {
        case .success(let socketPath, _):
            return socketPath
        case .executableNotFound, .launchFailed, .socketTimeout:
            return nil
        }
    }

    // =========================================================================
    // MARK: - Executable Discovery
    // =========================================================================

    /// Finds the AtticServer executable.
    ///
    /// Searches in several locations:
    /// 1. Same directory as the current executable
    /// 2. PATH environment variable
    /// 3. Common installation locations
    ///
    /// - Returns: Path to AtticServer executable, or nil if not found.
    public func findServerExecutable() -> String? {
        let fileManager = FileManager.default

        // Get the directory containing the current executable
        let executablePath = CommandLine.arguments[0]
        let executableDir = (executablePath as NSString).deletingLastPathComponent

        // Check in same directory as current executable
        let sameDirPath = (executableDir as NSString).appendingPathComponent("AtticServer")
        if fileManager.isExecutableFile(atPath: sameDirPath) {
            return sameDirPath
        }

        // Check in PATH environment variable
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let path = (String(dir) as NSString).appendingPathComponent("AtticServer")
                if fileManager.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        // Check common installation locations
        let commonPaths = [
            "/usr/local/bin/AtticServer",
            "/opt/homebrew/bin/AtticServer",
            "~/.local/bin/AtticServer"
        ]

        for path in commonPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expandedPath) {
                return expandedPath
            }
        }

        return nil
    }
}
