// =============================================================================
// CLISocketClient.swift - Unix Socket Client for CLI Protocol
// =============================================================================
//
// This file implements a Unix domain socket client that connects to AtticServer
// via the CLI text protocol. The client:
//
// - Discovers running AtticServer instances via /tmp/attic-*.sock
// - Connects to the server socket
// - Sends text commands and receives responses
// - Handles async events from the server
//
// Usage:
//
//     let client = CLISocketClient()
//
//     // Discover and connect to an existing server
//     if let socketPath = client.discoverSocket() {
//         try await client.connect(to: socketPath)
//     }
//
//     // Or connect to a specific socket
//     try await client.connect(to: "/tmp/attic-12345.sock")
//
//     // Send commands
//     let response = try await client.send(.pause)
//
//     // Disconnect
//     await client.disconnect()
//
// =============================================================================

import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// =============================================================================
// MARK: - CLI Socket Client Delegate
// =============================================================================

/// Protocol for receiving async events from the server.
///
/// Implement this protocol to handle events like breakpoint hits or errors
/// that arrive asynchronously while the emulator is running.
public protocol CLISocketClientDelegate: AnyObject, Sendable {
    /// Called when an async event is received from the server.
    ///
    /// - Parameters:
    ///   - client: The client that received the event.
    ///   - event: The received event.
    func client(_ client: CLISocketClient, didReceiveEvent event: CLIEvent) async

    /// Called when the connection to the server is lost.
    ///
    /// - Parameters:
    ///   - client: The client.
    ///   - error: The error that caused the disconnection, if any.
    func client(_ client: CLISocketClient, didDisconnectWithError error: Error?) async
}

// =============================================================================
// MARK: - CLI Socket Client
// =============================================================================

/// A Unix domain socket client for connecting to AtticServer.
///
/// This client implements the CLI text protocol for sending commands to the
/// emulator server and receiving responses. It also handles async events
/// like breakpoint notifications.
///
/// Thread Safety:
/// The client uses an actor to ensure thread-safe access to its state.
/// All public methods are async and can be safely called from any context.
///
public actor CLISocketClient {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The delegate for receiving async events.
    public weak var delegate: CLISocketClientDelegate?

    /// Sets the delegate for receiving async events from the server.
    /// This method provides a way to set the delegate from outside the actor.
    public func setDelegate(_ delegate: CLISocketClientDelegate?) {
        self.delegate = delegate
    }

    /// The socket file descriptor.
    private var socket: Int32 = -1

    /// Whether the client is connected.
    private(set) public var isConnected: Bool = false

    /// Path to the connected socket.
    private var connectedPath: String?

    /// Command parser (for building commands).
    private let commandParser = CLICommandParser()

    /// Response parser.
    private let responseParser = CLIResponseParser()

    /// Background task for reading events.
    private var eventReaderTask: Task<Void, Never>?

    /// Pending response (for synchronous request/response).
    private var pendingResponse: CheckedContinuation<CLIResponse, Error>?

    /// Request ID for matching timeouts to the correct request.
    /// This prevents a timeout for request A from affecting request B.
    private var currentRequestId: UInt64 = 0

    /// Read buffer for partial data.
    private var readBuffer = Data()

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new CLI socket client.
    public init() {}

    deinit {
        if socket >= 0 {
            close(socket)
        }
    }

    // =========================================================================
    // MARK: - Socket Discovery
    // =========================================================================

    /// Discovers available AtticServer sockets.
    ///
    /// Scans /tmp for attic-*.sock files and returns the paths of valid sockets.
    /// Only returns sockets whose server process is still running (validates PID).
    /// Sockets are sorted by modification time (most recent first).
    ///
    /// - Returns: Array of socket paths, or empty if none found.
    public nonisolated func discoverSockets() -> [String] {
        let fileManager = FileManager.default
        let tmpPath = "/tmp"

        guard let files = try? fileManager.contentsOfDirectory(atPath: tmpPath) else {
            return []
        }

        var sockets: [(path: String, modified: Date)] = []

        for file in files {
            if file.hasPrefix("attic-") && file.hasSuffix(".sock") {
                let fullPath = (tmpPath as NSString).appendingPathComponent(file)

                // Extract PID from filename (attic-<PID>.sock)
                // and verify the process is still running
                guard isServerProcessRunning(socketFilename: file) else {
                    // Stale socket - server process no longer running
                    // Clean up the stale socket file
                    try? fileManager.removeItem(atPath: fullPath)
                    continue
                }

                // Check if socket exists and get modification time
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let modified = attrs[.modificationDate] as? Date {
                    sockets.append((path: fullPath, modified: modified))
                }
            }
        }

        // Sort by modification time (most recent first)
        sockets.sort { $0.modified > $1.modified }

        return sockets.map { $0.path }
    }

    /// Checks if the server process for a socket file is still running.
    ///
    /// Extracts the PID from the socket filename (format: attic-<PID>.sock)
    /// and checks if that process is still alive.
    ///
    /// - Parameter socketFilename: The socket filename (e.g., "attic-1234.sock").
    /// - Returns: True if the process is running, false otherwise.
    private nonisolated func isServerProcessRunning(socketFilename: String) -> Bool {
        // Extract PID from filename: attic-<PID>.sock
        let withoutPrefix = socketFilename.dropFirst("attic-".count)
        let withoutSuffix = withoutPrefix.dropLast(".sock".count)

        guard let pid = Int32(withoutSuffix) else {
            return false
        }

        // Check if process is running using kill(pid, 0)
        // This doesn't send a signal, just checks if the process exists
        return kill(pid, 0) == 0
    }

    /// Discovers the most recently active AtticServer socket.
    ///
    /// - Returns: Path to the socket, or nil if none found.
    public nonisolated func discoverSocket() -> String? {
        discoverSockets().first
    }

    // =========================================================================
    // MARK: - Connection
    // =========================================================================

    /// Connects to an AtticServer socket.
    ///
    /// - Parameter path: Path to the Unix socket.
    /// - Throws: CLIProtocolError if connection fails.
    public func connect(to path: String) async throws {
        guard !isConnected else {
            throw CLIProtocolError.connectionFailed("Already connected")
        }

        // Create Unix domain socket
        socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw CLIProtocolError.connectionFailed("Failed to create socket: \(errno)")
        }

        // Build address structure
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
            let destPtr = rawPtr.assumingMemoryBound(to: CChar.self)
            for (i, byte) in pathBytes.enumerated() {
                if i < sunPathSize - 1 {
                    destPtr[i] = byte
                }
            }
        }

        // Connect to server
        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(socket)
            socket = -1
            throw CLIProtocolError.connectionFailed("Failed to connect: \(errno)")
        }

        isConnected = true
        connectedPath = path
        readBuffer = Data()

        // Start event reader task as detached so it can run concurrently with send()
        // The event reader uses blocking I/O (select/read), so it must run independently
        eventReaderTask = Task.detached { [weak self] in
            await self?.eventReaderLoop()
        }

        // Give the event reader task time to start and enter its read loop
        // Multiple yields help ensure the detached task has a chance to begin
        for _ in 0..<3 {
            await Task.yield()
        }

        // Verify connection with ping using a short timeout (pingTimeout)
        // This prevents hanging for 30 seconds if the server is unresponsive
        do {
            let response = try await send(.ping, timeout: CLIProtocolConstants.pingTimeout)
            guard case .ok(let data) = response, data == "pong" else {
                await disconnect()
                throw CLIProtocolError.connectionFailed("Server ping failed")
            }
        } catch {
            await disconnect()
            throw error
        }

        print("[CLIClient] Connected to \(path)")
    }

    /// Disconnects from the server.
    public func disconnect() async {
        guard isConnected else { return }

        isConnected = false

        // Cancel event reader
        eventReaderTask?.cancel()
        eventReaderTask = nil

        // Cancel pending response
        if let continuation = pendingResponse {
            pendingResponse = nil
            continuation.resume(throwing: CLIProtocolError.connectionFailed("Disconnected"))
        }

        // Close socket
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }

        connectedPath = nil
        print("[CLIClient] Disconnected")
    }

    // =========================================================================
    // MARK: - Command Sending
    // =========================================================================

    /// Sends a command to the server and waits for a response.
    ///
    /// - Parameter command: The command to send.
    /// - Returns: The server's response.
    /// - Throws: CLIProtocolError if sending fails or times out.
    public func send(_ command: CLICommand) async throws -> CLIResponse {
        try await send(command, timeout: CLIProtocolConstants.commandTimeout)
    }

    /// Sends a command to the server with a custom timeout.
    ///
    /// - Parameters:
    ///   - command: The command to send.
    ///   - timeout: The timeout in seconds.
    /// - Returns: The server's response.
    /// - Throws: CLIProtocolError if sending fails or times out.
    public func send(_ command: CLICommand, timeout: TimeInterval) async throws -> CLIResponse {
        guard isConnected else {
            throw CLIProtocolError.connectionFailed("Not connected")
        }

        // Format command
        let commandStr = formatCommand(command)
        let line = "\(CLIProtocolConstants.commandPrefix)\(commandStr)\n"

        guard let data = line.data(using: .utf8) else {
            throw CLIProtocolError.connectionFailed("Failed to encode command")
        }

        // Capture socket for use in detached task
        let socketFd = self.socket

        // Wait for response with timeout
        // IMPORTANT: Set up pendingResponse BEFORE sending to avoid race condition
        return try await withCheckedThrowingContinuation { continuation in
            // Increment request ID to track this specific request
            self.currentRequestId &+= 1
            let requestId = self.currentRequestId

            // Set pending response synchronously (we're on the actor)
            self.pendingResponse = continuation

            // Send command
            let bytesSent = data.withUnsafeBytes { ptr in
                write(socketFd, ptr.baseAddress, data.count)
            }

            if bytesSent != data.count {
                // Send failed - clear pending and resume with error
                self.pendingResponse = nil
                continuation.resume(throwing: CLIProtocolError.connectionFailed("Failed to send command: \(errno)"))
                return
            }

            // Start timeout task as detached to ensure it fires reliably
            // even if there are actor scheduling issues
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                // If still pending after timeout AND same request, fail
                // The request ID check prevents a timeout for request A from
                // affecting request B if B started before A's timeout fired
                await self?.timeoutPendingResponse(requestId: requestId)
            }
        }
    }

    /// Sends a raw command string to the server.
    ///
    /// - Parameter commandLine: The raw command line (without CMD: prefix).
    /// - Returns: The server's response.
    /// - Throws: CLIProtocolError if sending fails.
    public func sendRaw(_ commandLine: String) async throws -> CLIResponse {
        try await sendRaw(commandLine, timeout: CLIProtocolConstants.commandTimeout)
    }

    /// Sends a raw command string to the server with a custom timeout.
    ///
    /// - Parameters:
    ///   - commandLine: The raw command line (without CMD: prefix).
    ///   - timeout: The timeout in seconds.
    /// - Returns: The server's response.
    /// - Throws: CLIProtocolError if sending fails.
    public func sendRaw(_ commandLine: String, timeout: TimeInterval) async throws -> CLIResponse {
        guard isConnected else {
            throw CLIProtocolError.connectionFailed("Not connected")
        }

        let line = "\(CLIProtocolConstants.commandPrefix)\(commandLine)\n"

        guard let data = line.data(using: .utf8) else {
            throw CLIProtocolError.connectionFailed("Failed to encode command")
        }

        // Capture socket for use in detached task
        let socketFd = self.socket

        // Wait for response with timeout
        // IMPORTANT: Set up pendingResponse BEFORE sending to avoid race condition
        return try await withCheckedThrowingContinuation { continuation in
            // Increment request ID to track this specific request
            self.currentRequestId &+= 1
            let requestId = self.currentRequestId

            // Set pending response synchronously (we're on the actor)
            self.pendingResponse = continuation

            // Send command
            let bytesSent = data.withUnsafeBytes { ptr in
                write(socketFd, ptr.baseAddress, data.count)
            }

            if bytesSent != data.count {
                // Send failed - clear pending and resume with error
                self.pendingResponse = nil
                continuation.resume(throwing: CLIProtocolError.connectionFailed("Failed to send command: \(errno)"))
                return
            }

            // Start timeout task as detached to ensure it fires reliably
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                // If still pending after timeout AND same request, fail
                await self?.timeoutPendingResponse(requestId: requestId)
            }
        }
    }

    // =========================================================================
    // MARK: - Private Implementation
    // =========================================================================

    /// Formats a command for transmission.
    private func formatCommand(_ command: CLICommand) -> String {
        switch command {
        case .ping:
            return "ping"
        case .version:
            return "version"
        case .quit:
            return "quit"
        case .shutdown:
            return "shutdown"
        case .pause:
            return "pause"
        case .resume:
            return "resume"
        case .step(let count):
            return count == 1 ? "step" : "step \(count)"
        case .reset(let cold):
            return cold ? "reset cold" : "reset warm"
        case .status:
            return "status"
        case .read(let address, let count):
            return "read $\(String(format: "%04X", address)) \(count)"
        case .write(let address, let data):
            let hexBytes = data.map { String(format: "%02X", $0) }.joined(separator: ",")
            return "write $\(String(format: "%04X", address)) \(hexBytes)"
        case .registers(let modifications):
            if let mods = modifications {
                let modStrs = mods.map { "\($0.0)=$\(String(format: "%04X", $0.1))" }
                return "registers \(modStrs.joined(separator: " "))"
            }
            return "registers"
        case .breakpointSet(let address):
            return "breakpoint set $\(String(format: "%04X", address))"
        case .breakpointClear(let address):
            return "breakpoint clear $\(String(format: "%04X", address))"
        case .breakpointClearAll:
            return "breakpoint clearall"
        case .breakpointList:
            return "breakpoint list"
        case .mount(let drive, let path):
            return "mount \(drive) \(path)"
        case .unmount(let drive):
            return "unmount \(drive)"
        case .drives:
            return "drives"
        case .boot(let path):
            return "boot \(path)"
        case .stateSave(let path):
            return "state save \(path)"
        case .stateLoad(let path):
            return "state load \(path)"
        case .screenshot(let path):
            if let path = path {
                return "screenshot \(path)"
            }
            return "screenshot"
        case .injectBasic(let base64Data):
            return "inject basic \(base64Data)"
        case .injectKeys(let text):
            // Escape special characters (including space to prevent parser issues)
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: " ", with: "\\s")
            return "inject keys \(escaped)"
        case .disassemble(let address, let lines):
            // Format: disassemble [address] [lines]
            var cmd = "disassemble"
            if let addr = address {
                cmd += " $\(String(format: "%04X", addr))"
            }
            if let count = lines {
                // Only include lines if we have an address, or use default address marker
                if address == nil {
                    cmd += " . \(count)"  // '.' typically means current PC
                } else {
                    cmd += " \(count)"
                }
            }
            return cmd

        // Phase 11 Monitor commands
        case .assemble(let address):
            return "assemble $\(String(format: "%04X", address))"
        case .assembleLine(let address, let instruction):
            return "assemble $\(String(format: "%04X", address)) \(instruction)"
        case .assembleInput(let instruction):
            return "asm input \(instruction)"
        case .assembleEnd:
            return "asm end"
        case .stepOver:
            return "stepover"
        case .runUntil(let address):
            return "until $\(String(format: "%04X", address))"
        case .memoryFill(let start, let end, let value):
            return "fill $\(String(format: "%04X", start)) $\(String(format: "%04X", end)) $\(String(format: "%02X", value))"

        // Phase 14 BASIC commands
        case .basicLine(let line):
            return "basic \(line)"
        case .basicNew:
            return "basic NEW"
        case .basicRun:
            return "basic RUN"
        case .basicList:
            return "basic LIST"

        // BASIC editing commands
        case .basicDelete(let lineOrRange):
            return "basic DEL \(lineOrRange)"
        case .basicStop:
            return "basic STOP"
        case .basicCont:
            return "basic CONT"
        case .basicVars:
            return "basic VARS"
        case .basicVar(let name):
            return "basic VAR \(name)"
        case .basicInfo:
            return "basic INFO"
        case .basicExport(let path):
            return "basic EXPORT \(path)"
        case .basicImport(let path):
            return "basic IMPORT \(path)"
        case .basicDir(let drive):
            if let d = drive {
                return "basic DIR \(d)"
            }
            return "basic DIR"
        case .basicRenumber(let start, let step):
            var cmd = "basic RENUM"
            if let s = start { cmd += " \(s)" }
            if let st = step { cmd += " \(st)" }
            return cmd
        case .basicSave(let drive, let filename):
            if let d = drive {
                return "basic SAVE D\(d):\(filename)"
            }
            return "basic SAVE D:\(filename)"
        case .basicLoad(let drive, let filename):
            if let d = drive {
                return "basic LOAD D\(d):\(filename)"
            }
            return "basic LOAD D:\(filename)"

        // DOS mode commands
        case .dosChangeDrive(let drive):
            return "dos cd \(drive)"
        case .dosDirectory(let pattern):
            if let p = pattern { return "dos dir \(p)" }
            return "dos dir"
        case .dosFileInfo(let filename):
            return "dos info \(filename)"
        case .dosType(let filename):
            return "dos type \(filename)"
        case .dosDump(let filename):
            return "dos dump \(filename)"
        case .dosCopy(let source, let destination):
            return "dos copy \(source) \(destination)"
        case .dosRename(let oldName, let newName):
            return "dos rename \(oldName) \(newName)"
        case .dosDelete(let filename):
            return "dos delete \(filename)"
        case .dosLock(let filename):
            return "dos lock \(filename)"
        case .dosUnlock(let filename):
            return "dos unlock \(filename)"
        case .dosExport(let filename, let hostPath):
            return "dos export \(filename) \(hostPath)"
        case .dosImport(let hostPath, let filename):
            return "dos import \(hostPath) \(filename)"
        case .dosNewDisk(let path, let type):
            if let t = type { return "dos newdisk \(path) \(t)" }
            return "dos newdisk \(path)"
        case .dosFormat:
            return "dos format"
        }
    }

    /// Event reader loop - reads responses and events from the server.
    /// Note: This runs in a detached task to allow concurrent operation with send().
    private func eventReaderLoop() async {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }

        while isConnected && !Task.isCancelled {
            // Use select with short timeout to allow responsive cancellation
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(socket, &readSet)

            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)  // 100ms timeout
            let selectResult = select(socket + 1, &readSet, nil, nil, &timeout)

            if selectResult < 0 {
                // Error
                await handleDisconnect(error: CLIProtocolError.connectionFailed("Read error: \(errno)"))
                break
            } else if selectResult == 0 {
                // Timeout - yield to allow other tasks to run
                await Task.yield()
                continue
            }

            // Read from socket
            let bytesRead = read(socket, buffer, 4096)
            if bytesRead <= 0 {
                // EOF or error
                await handleDisconnect(error: bytesRead == 0 ? nil : CLIProtocolError.connectionFailed("Read error"))
                break
            }

            // Append to buffer
            readBuffer.append(buffer, count: bytesRead)

            // Process complete lines
            while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
                let lineData = readBuffer[..<newlineIndex]
                readBuffer = Data(readBuffer[readBuffer.index(after: newlineIndex)...])

                if let line = String(data: lineData, encoding: .utf8) {
                    await processLine(line)
                }
            }

            // Yield after processing to allow other tasks to run
            await Task.yield()
        }
    }

    /// Processes a received line.
    private func processLine(_ line: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let parsed = try responseParser.parse(trimmed)

            switch parsed {
            case .response(let response):
                // Complete pending request
                if let continuation = pendingResponse {
                    pendingResponse = nil
                    continuation.resume(returning: response)
                }

            case .event(let event):
                // Notify delegate
                await delegate?.client(self, didReceiveEvent: event)
            }
        } catch {
            // Parse error - log but don't fail
            print("[CLIClient] Failed to parse response: \(error)")
        }
    }

    /// Handles disconnection.
    private func handleDisconnect(error: Error?) async {
        guard isConnected else { return }

        isConnected = false

        if let continuation = pendingResponse {
            pendingResponse = nil
            continuation.resume(throwing: error ?? CLIProtocolError.connectionFailed("Disconnected"))
        }

        await delegate?.client(self, didDisconnectWithError: error)
    }

    /// Sets the pending response continuation.
    private func setPendingResponse(_ continuation: CheckedContinuation<CLIResponse, Error>) {
        pendingResponse = continuation
    }

    /// Times out the pending response if it matches the given request ID.
    ///
    /// This method handles the timeout entirely within the actor's isolation,
    /// ensuring that the check and resume happen atomically. This prevents
    /// race conditions where a timeout for request A could affect request B.
    ///
    /// - Parameter requestId: The request ID to match.
    private func timeoutPendingResponse(requestId: UInt64) {
        // Only timeout if:
        // 1. There's a pending response waiting
        // 2. The request ID matches (same request that set up this timeout)
        guard let continuation = pendingResponse,
              currentRequestId == requestId else {
            return
        }

        // Clear and resume with timeout error - all within actor isolation
        pendingResponse = nil
        continuation.resume(throwing: CLIProtocolError.timeout)
    }
}

// =============================================================================
// MARK: - fd_set Helpers (Duplicated for client module)
// =============================================================================

/// Clears an fd_set.
private func fdZero(_ set: inout fd_set) {
    #if canImport(Darwin)
    _ = withUnsafeMutablePointer(to: &set) { ptr in
        memset(ptr, 0, MemoryLayout<fd_set>.size)
    }
    #else
    __FD_ZERO(&set)
    #endif
}

/// Adds a file descriptor to an fd_set.
private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    #if canImport(Darwin)
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    withUnsafeMutablePointer(to: &set) { ptr in
        let rawPtr = UnsafeMutableRawPointer(ptr)
        let arrayPtr = rawPtr.assumingMemoryBound(to: Int32.self)
        arrayPtr[intOffset] |= Int32(1 << bitOffset)
    }
    #else
    __FD_SET(fd, &set)
    #endif
}
