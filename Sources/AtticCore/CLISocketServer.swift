// =============================================================================
// CLISocketServer.swift - Unix Socket Server for CLI Protocol
// =============================================================================
//
// This file implements a Unix domain socket server that handles CLI protocol
// connections from the attic CLI tool. The server:
//
// - Listens on /tmp/attic-<pid>.sock
// - Accepts multiple CLI connections
// - Parses text commands and executes them against the emulator
// - Sends responses and async events back to connected clients
//
// Architecture:
// -------------
// The server uses Swift's async/await and the Network framework for socket I/O.
// It's designed to be embedded in AtticServer alongside the AESP binary protocol.
//
// Why Unix Sockets?
// -----------------
// Unix domain sockets provide efficient IPC (inter-process communication) on
// the same machine. They're faster than TCP for local communication and
// support standard file system permissions for security.
//
// Socket Path: /tmp/attic-<pid>.sock
// ----------------------------------
// Using the PID in the socket path allows multiple AtticServer instances to
// run simultaneously (e.g., for testing). The CLI discovers sockets by
// scanning /tmp/attic-*.sock.
//
// =============================================================================

import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// =============================================================================
// MARK: - CLI Socket Server Delegate
// =============================================================================

/// Protocol for receiving callbacks from the CLI socket server.
///
/// Implement this protocol to handle CLI commands. The server parses commands
/// and calls delegate methods for execution. The delegate should return
/// appropriate responses.
public protocol CLISocketServerDelegate: AnyObject, Sendable {
    /// Called when a command is received from a CLI client.
    ///
    /// - Parameters:
    ///   - server: The server that received the command.
    ///   - command: The parsed command.
    ///   - clientId: Unique identifier for the client connection.
    /// - Returns: The response to send back to the client.
    func server(
        _ server: CLISocketServer,
        didReceiveCommand command: CLICommand,
        from clientId: UUID
    ) async -> CLIResponse

    /// Called when a client connects.
    ///
    /// - Parameters:
    ///   - server: The server.
    ///   - clientId: Unique identifier for the new client.
    func server(_ server: CLISocketServer, clientDidConnect clientId: UUID) async

    /// Called when a client disconnects.
    ///
    /// - Parameters:
    ///   - server: The server.
    ///   - clientId: Unique identifier for the disconnected client.
    func server(_ server: CLISocketServer, clientDidDisconnect clientId: UUID) async
}

// =============================================================================
// MARK: - CLI Socket Server
// =============================================================================

/// A Unix domain socket server for the CLI text protocol.
///
/// This server listens for connections from the attic CLI tool and handles
/// text-based commands. It can be used alongside the AESP server in AtticServer.
///
/// Usage:
///
///     let server = CLISocketServer()
///     server.delegate = myDelegate
///     try await server.start()
///
///     // Later...
///     await server.stop()
///
public actor CLISocketServer {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The delegate for handling commands.
    public weak var delegate: CLISocketServerDelegate?

    /// Sets the delegate for handling commands.
    /// This method is required because actor-isolated properties cannot be
    /// directly set from outside the actor context.
    public func setDelegate(_ delegate: CLISocketServerDelegate?) {
        self.delegate = delegate
    }

    /// The socket file descriptor.
    private var serverSocket: Int32 = -1

    /// Path to the Unix socket file.
    private let socketPath: String

    /// Whether the server is running.
    private var isRunning: Bool = false

    /// Connected clients (clientId -> socket fd).
    private var clients: [UUID: Int32] = [:]

    /// Task for accepting connections.
    private var acceptTask: Task<Void, Never>?

    /// Tasks for reading from clients.
    private var clientTasks: [UUID: Task<Void, Never>] = [:]

    /// Command parser.
    private let parser = CLICommandParser()

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new CLI socket server.
    ///
    /// - Parameter socketPath: Path for the Unix socket. Defaults to /tmp/attic-<pid>.sock.
    public init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? CLIProtocolConstants.currentSocketPath
    }

    deinit {
        // Clean up socket file if it exists
        if serverSocket >= 0 {
            close(serverSocket)
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // =========================================================================
    // MARK: - Server Lifecycle
    // =========================================================================

    /// Starts the server.
    ///
    /// This creates the Unix socket and begins accepting connections.
    ///
    /// - Throws: CLIProtocolError if the server cannot start.
    public func start() async throws {
        guard !isRunning else { return }

        // Remove existing socket file if present
        try? FileManager.default.removeItem(atPath: socketPath)

        // Create Unix domain socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw CLIProtocolError.connectionFailed("Failed to create socket: \(errno)")
        }

        // Set socket options
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Bind to socket path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Copy path to sun_path
        let pathBytes = socketPath.utf8CString
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

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            serverSocket = -1
            throw CLIProtocolError.connectionFailed("Failed to bind socket: \(errno)")
        }

        // Set socket permissions (user read/write only)
        chmod(socketPath, 0o600)

        // Start listening
        guard listen(serverSocket, 5) == 0 else {
            close(serverSocket)
            serverSocket = -1
            try? FileManager.default.removeItem(atPath: socketPath)
            throw CLIProtocolError.connectionFailed("Failed to listen: \(errno)")
        }

        isRunning = true

        // Start accept loop in background task
        acceptTask = Task { [weak self] in
            await self?.acceptLoop()
        }

        print("[CLISocket] Server listening on \(socketPath)")
    }

    /// Stops the server.
    ///
    /// This closes all client connections and removes the socket file.
    public func stop() async {
        guard isRunning else { return }
        isRunning = false

        // Cancel accept task
        acceptTask?.cancel()
        acceptTask = nil

        // Cancel all client tasks
        for (_, task) in clientTasks {
            task.cancel()
        }
        clientTasks.removeAll()

        // Close all client sockets
        for (_, socket) in clients {
            close(socket)
        }
        clients.removeAll()

        // Close server socket
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }

        // Remove socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        print("[CLISocket] Server stopped")
    }

    /// Returns the socket path.
    public var path: String {
        socketPath
    }

    // =========================================================================
    // MARK: - Client Communication
    // =========================================================================

    /// Sends an event to all connected clients.
    ///
    /// - Parameter event: The event to broadcast.
    public func broadcastEvent(_ event: CLIEvent) async {
        let message = event.formatted + "\n"
        guard let data = message.data(using: .utf8) else { return }

        for (_, clientSocket) in clients {
            _ = data.withUnsafeBytes { ptr in
                write(clientSocket, ptr.baseAddress, data.count)
            }
        }
    }

    /// Sends an event to a specific client.
    ///
    /// - Parameters:
    ///   - event: The event to send.
    ///   - clientId: The target client.
    public func sendEvent(_ event: CLIEvent, to clientId: UUID) async {
        guard let clientSocket = clients[clientId] else { return }

        let message = event.formatted + "\n"
        guard let data = message.data(using: .utf8) else { return }

        _ = data.withUnsafeBytes { ptr in
            write(clientSocket, ptr.baseAddress, data.count)
        }
    }

    // =========================================================================
    // MARK: - Private Implementation
    // =========================================================================

    /// Accept loop - runs in background and accepts incoming connections.
    private func acceptLoop() async {
        while isRunning && !Task.isCancelled {
            // Use select() with timeout to allow for cancellation checks
            // IMPORTANT: Use a short timeout to allow other actor tasks to run
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(serverSocket, &readSet)

            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)  // 100ms timeout
            let selectResult = select(serverSocket + 1, &readSet, nil, nil, &timeout)

            if selectResult <= 0 {
                // Timeout or error - yield to allow other tasks to run
                await Task.yield()
                continue
            }

            // Accept new connection
            var clientAddr = sockaddr_un()
            var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverSocket, sockaddrPtr, &addrLen)
                }
            }

            guard clientSocket >= 0 else {
                continue
            }

            // Create client ID and add to list
            let clientId = UUID()
            addClient(clientId, socket: clientSocket)

            // Notify delegate
            await delegate?.server(self, clientDidConnect: clientId)

            // Start reading from client in a detached task so it's not blocked by this actor
            // The task captures clientId and clientSocket by value
            let task = Task.detached { [weak self] in
                guard let self = self else { return }
                await self.clientReadLoop(clientId: clientId, socket: clientSocket)
            }
            setClientTask(clientId, task: task)

            print("[CLISocket] Client connected: \(clientId)")

            // Yield to allow the new client task to start
            await Task.yield()
        }
    }

    /// Read loop for a single client.
    /// Note: This runs in a detached task to avoid blocking the actor's accept loop.
    private func clientReadLoop(clientId: UUID, socket clientSocket: Int32) async {
        var buffer = Data()
        let readBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { readBuffer.deallocate() }

        while !Task.isCancelled {
            // Check if socket is readable with short timeout
            // Using 100ms allows other actor tasks to run between checks
            var readSet = fd_set()
            fdZero(&readSet)
            fdSet(clientSocket, &readSet)

            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)  // 100ms timeout
            let selectResult = select(clientSocket + 1, &readSet, nil, nil, &timeout)

            if selectResult < 0 {
                break  // Error
            } else if selectResult == 0 {
                // Timeout - yield to allow other tasks to run
                await Task.yield()
                continue
            }

            // Read from socket
            let bytesRead = read(clientSocket, readBuffer, 4096)
            if bytesRead <= 0 {
                break  // EOF or error
            }

            // Append to buffer
            buffer.append(readBuffer, count: bytesRead)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {  // \n
                let lineData = buffer[..<newlineIndex]
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                if let line = String(data: lineData, encoding: .utf8) {
                    await processLine(line, clientId: clientId, socket: clientSocket)
                }
            }

            // Yield after processing to allow other tasks to run
            await Task.yield()
        }

        // Client disconnected
        removeClient(clientId)
        close(clientSocket)
        await delegate?.server(self, clientDidDisconnect: clientId)
        print("[CLISocket] Client disconnected: \(clientId)")
    }

    /// Processes a single command line from a client.
    private func processLine(_ line: String, clientId: UUID, socket clientSocket: Int32) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Parse the command
        let response: CLIResponse
        do {
            let command = try parser.parse(trimmed)
            if let delegate = delegate {
                response = await delegate.server(self, didReceiveCommand: command, from: clientId)
            } else {
                response = .error("Server not configured")
            }
        } catch let error as CLIProtocolError {
            response = error.cliResponse
        } catch {
            response = .error(error.localizedDescription)
        }

        // Send response
        let message = response.formatted + "\n"
        if let data = message.data(using: .utf8) {
            _ = data.withUnsafeBytes { ptr in
                write(clientSocket, ptr.baseAddress, data.count)
            }
        }
    }

    // =========================================================================
    // MARK: - Client Management (isolated state mutations)
    // =========================================================================

    private func addClient(_ clientId: UUID, socket: Int32) {
        clients[clientId] = socket
    }

    private func removeClient(_ clientId: UUID) {
        clients.removeValue(forKey: clientId)
        clientTasks.removeValue(forKey: clientId)
    }

    private func setClientTask(_ clientId: UUID, task: Task<Void, Never>) {
        clientTasks[clientId] = task
    }
}
