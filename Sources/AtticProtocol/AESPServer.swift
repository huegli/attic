// =============================================================================
// AESPServer.swift - AESP Protocol Server
// =============================================================================
//
// This file implements the server-side of the Attic Emulator Server Protocol.
// The server listens on three separate ports for different data streams:
//
// - Control Port (47800): Commands, status, memory access
// - Video Port (47801): Frame broadcasts to subscribed clients
// - Audio Port (47802): Audio sample broadcasts to subscribed clients
//
// The server is implemented as a Swift actor for thread-safe state management.
// It uses NIO (via Foundation's async networking) for efficient I/O handling.
//
// ## Architecture
//
// The server maintains three listener sockets and tracks connected clients
// for each channel. Video and audio clients are "subscribers" that receive
// push notifications (frames/samples) from the emulation loop.
//
// ## Usage
//
// ```swift
// let server = AESPServer()
// try await server.start()
//
// // In emulation loop:
// await server.broadcastFrame(frameBuffer)
// await server.broadcastAudio(audioSamples)
//
// // Handle incoming control messages:
// for await message in await server.controlMessages {
//     // Process message...
// }
//
// // Shutdown:
// await server.stop()
// ```
//
// =============================================================================

import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - Server Configuration

/// Configuration for the AESP server.
public struct AESPServerConfiguration: Sendable {
    /// Port for control channel.
    public var controlPort: Int

    /// Port for video channel.
    public var videoPort: Int

    /// Port for audio channel.
    public var audioPort: Int

    /// Whether to use TCP (true) or Unix domain sockets (false).
    public var useTCP: Bool

    /// Base path for Unix domain sockets (only used if useTCP is false).
    /// Sockets will be created as: {basePath}-control.sock, {basePath}-video.sock, etc.
    public var socketBasePath: String

    /// Creates a default configuration.
    public init(
        controlPort: Int = AESPConstants.defaultControlPort,
        videoPort: Int = AESPConstants.defaultVideoPort,
        audioPort: Int = AESPConstants.defaultAudioPort,
        useTCP: Bool = true,
        socketBasePath: String = "/tmp/attic-\(ProcessInfo.processInfo.processIdentifier)"
    ) {
        self.controlPort = controlPort
        self.videoPort = videoPort
        self.audioPort = audioPort
        self.useTCP = useTCP
        self.socketBasePath = socketBasePath
    }
}

// MARK: - Client Connection

/// Represents a connected client on one of the server's channels.
final class AESPClientConnection: @unchecked Sendable {
    /// Unique identifier for this connection.
    let id: UUID

    /// The channel this client is connected to.
    let channel: AESPChannel

    /// The underlying network connection (NWConnection).
    #if canImport(Network)
    let connection: NWConnection
    #endif

    /// Whether the client wants delta-encoded video frames.
    var wantsDeltaFrames: Bool = false

    /// Buffer for incomplete incoming data.
    var receiveBuffer: Data = Data()

    /// Creates a new client connection.
    #if canImport(Network)
    init(id: UUID = UUID(), channel: AESPChannel, connection: NWConnection) {
        self.id = id
        self.channel = channel
        self.connection = connection
    }
    #endif
}

/// The channel type for a connection.
public enum AESPChannel: String, Sendable {
    case control
    case video
    case audio
}

// MARK: - Server Delegate Protocol

/// Delegate protocol for receiving server events.
///
/// Implement this protocol to handle incoming messages and connection events.
public protocol AESPServerDelegate: AnyObject, Sendable {
    /// Called when a control message is received from a client.
    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async

    /// Called when a client connects.
    func server(_ server: AESPServer, clientDidConnect clientId: UUID, channel: AESPChannel) async

    /// Called when a client disconnects.
    func server(_ server: AESPServer, clientDidDisconnect clientId: UUID, channel: AESPChannel) async
}

// MARK: - AESP Server Actor

/// The AESP protocol server.
///
/// This actor manages network connections for the emulator server protocol.
/// It listens on separate ports for control, video, and audio channels,
/// allowing clients to subscribe to the streams they need.
///
/// ## Thread Safety
///
/// As a Swift actor, all access to the server's state is serialized.
/// The broadcast methods (`broadcastFrame`, `broadcastAudio`) can be
/// called safely from the emulation loop.
///
/// ## Starting the Server
///
/// ```swift
/// let server = AESPServer()
/// try await server.start()
/// print("Server listening on ports \(server.configuration.controlPort), etc.")
/// ```
///
/// ## Broadcasting Frames
///
/// Call from your emulation loop:
/// ```swift
/// let frameBuffer: [UInt8] = await emulator.getFrameBuffer()
/// await server.broadcastFrame(frameBuffer)
/// ```
public actor AESPServer {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Server configuration.
    public let configuration: AESPServerConfiguration

    /// Delegate for receiving events.
    public weak var delegate: AESPServerDelegate?

    /// Whether the server is currently running.
    public private(set) var isRunning: Bool = false

    #if canImport(Network)
    /// Control channel listener.
    private var controlListener: NWListener?

    /// Video channel listener.
    private var videoListener: NWListener?

    /// Audio channel listener.
    private var audioListener: NWListener?

    /// Connected control clients.
    private var controlClients: [UUID: AESPClientConnection] = [:]

    /// Connected video clients (subscribers).
    private var videoClients: [UUID: AESPClientConnection] = [:]

    /// Connected audio clients (subscribers).
    private var audioClients: [UUID: AESPClientConnection] = [:]
    #endif

    /// Frame counter for synchronization.
    private var frameCounter: UInt64 = 0

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new AESP server with the given configuration.
    ///
    /// - Parameter configuration: Server configuration (ports, transport type).
    public init(configuration: AESPServerConfiguration = AESPServerConfiguration()) {
        self.configuration = configuration
    }

    // =========================================================================
    // MARK: - Server Lifecycle
    // =========================================================================

    /// Starts the server and begins listening for connections.
    ///
    /// This method sets up listeners on the control, video, and audio ports.
    /// Once started, clients can connect and subscribe to streams.
    ///
    /// - Throws: `AESPError.connectionError` if listeners cannot be started.
    public func start() async throws {
        guard !isRunning else { return }

        #if canImport(Network)
        // Create listeners for each channel
        do {
            controlListener = try createListener(port: configuration.controlPort, channel: .control)
            videoListener = try createListener(port: configuration.videoPort, channel: .video)
            audioListener = try createListener(port: configuration.audioPort, channel: .audio)

            // Start all listeners
            controlListener?.start(queue: .global(qos: .userInteractive))
            videoListener?.start(queue: .global(qos: .userInteractive))
            audioListener?.start(queue: .global(qos: .userInteractive))

            isRunning = true

            print("[AESPServer] Started on ports: control=\(configuration.controlPort), video=\(configuration.videoPort), audio=\(configuration.audioPort)")
        } catch {
            throw AESPError.connectionError("Failed to start listeners: \(error)")
        }
        #else
        throw AESPError.connectionError("Network framework not available")
        #endif
    }

    /// Stops the server and closes all connections.
    ///
    /// All connected clients will be disconnected and listeners will be closed.
    public func stop() async {
        guard isRunning else { return }

        #if canImport(Network)
        // Close all client connections
        for client in controlClients.values {
            client.connection.cancel()
        }
        for client in videoClients.values {
            client.connection.cancel()
        }
        for client in audioClients.values {
            client.connection.cancel()
        }

        controlClients.removeAll()
        videoClients.removeAll()
        audioClients.removeAll()

        // Stop listeners
        controlListener?.cancel()
        videoListener?.cancel()
        audioListener?.cancel()

        controlListener = nil
        videoListener = nil
        audioListener = nil
        #endif

        isRunning = false
        print("[AESPServer] Stopped")
    }

    // =========================================================================
    // MARK: - Listener Setup
    // =========================================================================

    #if canImport(Network)
    /// Creates a network listener for the specified port and channel.
    private func createListener(port: Int, channel: AESPChannel) throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))

        // Set up state change handler
        listener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerStateChange(state, channel: channel)
            }
        }

        // Set up new connection handler
        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection, channel: channel)
            }
        }

        return listener
    }

    /// Handles listener state changes.
    private func handleListenerStateChange(_ state: NWListener.State, channel: AESPChannel) {
        switch state {
        case .ready:
            print("[AESPServer] \(channel.rawValue) listener ready")
        case .failed(let error):
            print("[AESPServer] \(channel.rawValue) listener failed: \(error)")
        case .cancelled:
            print("[AESPServer] \(channel.rawValue) listener cancelled")
        default:
            break
        }
    }

    /// Handles a new client connection.
    private func handleNewConnection(_ connection: NWConnection, channel: AESPChannel) {
        let clientId = UUID()
        let client = AESPClientConnection(id: clientId, channel: channel, connection: connection)

        // Store client in appropriate dictionary
        switch channel {
        case .control:
            controlClients[clientId] = client
        case .video:
            videoClients[clientId] = client
        case .audio:
            audioClients[clientId] = client
        }

        // Set up connection state handler
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionStateChange(state, clientId: clientId, channel: channel)
            }
        }

        // Start the connection
        connection.start(queue: .global(qos: .userInteractive))

        print("[AESPServer] Client \(clientId) connected on \(channel.rawValue) channel")

        // Notify delegate
        Task {
            await delegate?.server(self, clientDidConnect: clientId, channel: channel)
        }
    }

    /// Handles connection state changes.
    private func handleConnectionStateChange(_ state: NWConnection.State, clientId: UUID, channel: AESPChannel) {
        switch state {
        case .ready:
            // Start receiving data
            Task {
                startReceiving(clientId: clientId, channel: channel)
            }
        case .failed(let error):
            print("[AESPServer] Client \(clientId) connection failed: \(error)")
            Task {
                await removeClient(clientId: clientId, channel: channel)
            }
        case .cancelled:
            Task {
                await removeClient(clientId: clientId, channel: channel)
            }
        default:
            break
        }
    }

    /// Starts receiving data from a client.
    private func startReceiving(clientId: UUID, channel: AESPChannel) {
        guard let client = getClient(clientId: clientId, channel: channel) else { return }

        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                if let data = data, !data.isEmpty {
                    await self?.handleReceivedData(data, clientId: clientId, channel: channel)
                }

                if isComplete || error != nil {
                    await self?.removeClient(clientId: clientId, channel: channel)
                } else {
                    // Continue receiving
                    await self?.startReceiving(clientId: clientId, channel: channel)
                }
            }
        }
    }

    /// Gets a client by ID and channel.
    private func getClient(clientId: UUID, channel: AESPChannel) -> AESPClientConnection? {
        switch channel {
        case .control:
            return controlClients[clientId]
        case .video:
            return videoClients[clientId]
        case .audio:
            return audioClients[clientId]
        }
    }

    /// Handles received data from a client.
    private func handleReceivedData(_ data: Data, clientId: UUID, channel: AESPChannel) async {
        guard let client = getClient(clientId: clientId, channel: channel) else { return }

        // Append to receive buffer
        client.receiveBuffer.append(data)

        // Process complete messages
        while let messageSize = AESPMessage.messageSize(in: client.receiveBuffer) {
            do {
                let (message, _) = try AESPMessage.decode(from: client.receiveBuffer)
                client.receiveBuffer.removeFirst(messageSize)

                // Handle the message
                await handleMessage(message, from: clientId, channel: channel)
            } catch {
                print("[AESPServer] Error decoding message from \(clientId): \(error)")
                client.receiveBuffer.removeAll()
                break
            }
        }
    }

    /// Handles a decoded message from a client.
    private func handleMessage(_ message: AESPMessage, from clientId: UUID, channel: AESPChannel) async {
        switch message.type {
        // Handle subscription messages
        case .videoSubscribe:
            if channel == .control, let controlClient = controlClients[clientId] {
                // Move client to video subscribers (or create new connection)
                controlClient.wantsDeltaFrames = message.payload.first == 0x01
            }

        case .audioSubscribe:
            // Client wants audio
            break

        case .videoUnsubscribe:
            // Remove from video subscribers
            break

        case .audioUnsubscribe:
            // Remove from audio subscribers
            break

        case .ping:
            // Respond with pong
            await sendMessage(.pong(), to: clientId, channel: channel)

        default:
            // Forward to delegate for handling
            await delegate?.server(self, didReceiveMessage: message, from: clientId)
        }
    }

    /// Removes a client from tracking.
    private func removeClient(clientId: UUID, channel: AESPChannel) async {
        switch channel {
        case .control:
            if let client = controlClients.removeValue(forKey: clientId) {
                client.connection.cancel()
            }
        case .video:
            if let client = videoClients.removeValue(forKey: clientId) {
                client.connection.cancel()
            }
        case .audio:
            if let client = audioClients.removeValue(forKey: clientId) {
                client.connection.cancel()
            }
        }

        print("[AESPServer] Client \(clientId) disconnected from \(channel.rawValue) channel")

        // Notify delegate
        await delegate?.server(self, clientDidDisconnect: clientId, channel: channel)
    }
    #endif

    // =========================================================================
    // MARK: - Sending Messages
    // =========================================================================

    /// Sends a message to a specific client.
    ///
    /// - Parameters:
    ///   - message: The message to send.
    ///   - clientId: The client's unique identifier.
    ///   - channel: The channel to send on.
    public func sendMessage(_ message: AESPMessage, to clientId: UUID, channel: AESPChannel) async {
        #if canImport(Network)
        guard let client = getClient(clientId: clientId, channel: channel) else { return }

        let data = message.encode()
        client.connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[AESPServer] Error sending to \(clientId): \(error)")
            }
        })
        #endif
    }

    /// Sends a message to all clients on a channel.
    ///
    /// - Parameters:
    ///   - message: The message to send.
    ///   - channel: The channel to broadcast on.
    public func broadcast(_ message: AESPMessage, on channel: AESPChannel) async {
        #if canImport(Network)
        let clients: [AESPClientConnection]
        switch channel {
        case .control:
            clients = Array(controlClients.values)
        case .video:
            clients = Array(videoClients.values)
        case .audio:
            clients = Array(audioClients.values)
        }

        let data = message.encode()
        for client in clients {
            client.connection.send(content: data, completion: .contentProcessed { _ in })
        }
        #endif
    }

    // =========================================================================
    // MARK: - Broadcasting Frames and Audio
    // =========================================================================

    /// Broadcasts a video frame to all subscribed video clients.
    ///
    /// This method should be called from the emulation loop after each frame.
    /// The frame data is sent as a raw BGRA buffer (384×240×4 bytes).
    ///
    /// - Parameter pixels: The frame buffer as a byte array.
    public func broadcastFrame(_ pixels: [UInt8]) async {
        #if canImport(Network)
        guard !videoClients.isEmpty else { return }

        let message = AESPMessage.frameRaw(pixels: pixels)
        let data = message.encode()

        for client in videoClients.values {
            client.connection.send(content: data, completion: .contentProcessed { _ in })
        }
        #endif

        frameCounter += 1
    }

    /// Broadcasts a video frame to all subscribed video clients.
    ///
    /// - Parameter pixels: The frame buffer as Data.
    public func broadcastFrame(_ pixels: Data) async {
        await broadcastFrame(Array(pixels))
    }

    /// Broadcasts audio samples to all subscribed audio clients.
    ///
    /// This method should be called from the emulation loop with each batch
    /// of audio samples. Samples are 16-bit signed PCM, mono.
    ///
    /// - Parameter samples: The audio samples as a byte array.
    public func broadcastAudio(_ samples: [UInt8]) async {
        #if canImport(Network)
        guard !audioClients.isEmpty else { return }

        let message = AESPMessage.audioPCM(samples: Data(samples))
        let data = message.encode()

        for client in audioClients.values {
            client.connection.send(content: data, completion: .contentProcessed { _ in })
        }
        #endif
    }

    /// Broadcasts audio samples to all subscribed audio clients.
    ///
    /// - Parameter samples: The audio samples as Data.
    public func broadcastAudio(_ samples: Data) async {
        await broadcastAudio(Array(samples))
    }

    /// Broadcasts an audio sync message with the current frame number.
    ///
    /// This helps clients synchronize audio with video.
    public func broadcastAudioSync() async {
        await broadcast(.audioSync(frameNumber: frameCounter), on: .audio)
    }

    // =========================================================================
    // MARK: - Client Information
    // =========================================================================

    /// Returns the number of connected clients on each channel.
    public var clientCounts: (control: Int, video: Int, audio: Int) {
        #if canImport(Network)
        return (controlClients.count, videoClients.count, audioClients.count)
        #else
        return (0, 0, 0)
        #endif
    }

    /// Returns the current frame counter.
    public var currentFrameNumber: UInt64 {
        return frameCounter
    }
}
