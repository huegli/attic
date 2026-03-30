// =============================================================================
// AESPWebSocketBridge.swift - WebSocket Bridge for AESP Protocol
// =============================================================================
//
// This file implements a WebSocket server that bridges web browser clients to
// the AESP protocol. It allows JavaScript clients to connect via a single
// WebSocket port and receive all AESP channels (control, video, audio)
// multiplexed over one connection.
//
// ## Architecture
//
// The bridge runs in-process within AtticServer. It receives frame and audio
// data directly from the emulation loop (avoiding double-serialization) and
// forwards it to connected WebSocket clients as binary frames. Each binary
// frame contains a standard AESP message (8-byte header + payload).
//
// The bridge uses Apple's Network framework with NWProtocolWebSocket for
// native WebSocket server support. This handles the HTTP upgrade handshake,
// frame encoding/decoding, and ping/pong keepalives automatically.
//
// ## Port
//
// The bridge listens on a single port (default 47803) that multiplexes all
// AESP channels. Web clients parse the message type byte from the AESP header
// to determine which channel a message belongs to.
//
// ## Web Client Usage
//
// ```javascript
// const ws = new WebSocket('ws://localhost:47803');
// ws.binaryType = 'arraybuffer';
//
// ws.onmessage = (event) => {
//     const view = new DataView(event.data);
//     const magic = view.getUint16(0);      // 0xAE50
//     const type = view.getUint8(3);         // Message type
//     const length = view.getUint32(4);      // Payload length
//     const payload = new Uint8Array(event.data, 8, length);
//     // Handle by type...
// };
// ```
//
// =============================================================================

import Foundation
#if canImport(Network)
import Network
#endif

// MARK: - WebSocket Bridge Delegate

/// Delegate protocol for receiving messages from WebSocket clients.
///
/// This mirrors AESPServerDelegate but is specific to WebSocket connections.
/// The delegate receives control and input messages from web clients, which
/// should be forwarded to the emulator for processing.
public protocol AESPWebSocketBridgeDelegate: AnyObject, Sendable {
    /// Called when a control or input message is received from a WebSocket client.
    ///
    /// - Parameters:
    ///   - bridge: The bridge that received the message.
    ///   - message: The decoded AESP message.
    ///   - clientId: The unique identifier of the sending client.
    func bridge(_ bridge: AESPWebSocketBridge, didReceiveMessage message: AESPMessage, from clientId: UUID) async

    /// Called when a WebSocket client connects.
    ///
    /// - Parameters:
    ///   - bridge: The bridge that accepted the connection.
    ///   - clientId: The unique identifier of the new client.
    func bridge(_ bridge: AESPWebSocketBridge, clientDidConnect clientId: UUID) async

    /// Called when a WebSocket client disconnects.
    ///
    /// - Parameters:
    ///   - bridge: The bridge the client disconnected from.
    ///   - clientId: The unique identifier of the disconnected client.
    func bridge(_ bridge: AESPWebSocketBridge, clientDidDisconnect clientId: UUID) async
}

// MARK: - WebSocket Client Connection

/// Represents a connected WebSocket client.
///
/// Each client gets its own connection object. Unlike the TCP-based AESPServer
/// which uses separate ports for control/video/audio, WebSocket clients receive
/// all channels on a single connection.
final class WebSocketClientConnection: @unchecked Sendable {
    /// Unique identifier for this client.
    let id: UUID

    /// The underlying NWConnection with WebSocket protocol.
    #if canImport(Network)
    let connection: NWConnection
    #endif

    /// Creates a new WebSocket client connection.
    #if canImport(Network)
    init(id: UUID = UUID(), connection: NWConnection) {
        self.id = id
        self.connection = connection
    }
    #endif
}

// MARK: - WebSocket Bridge Actor

/// A WebSocket server that bridges web browser clients to the AESP protocol.
///
/// The bridge listens on a single port (default 47803) and multiplexes all
/// AESP channels over each WebSocket connection. AESP binary messages are
/// sent as WebSocket binary frames with no transcoding — the standard 8-byte
/// header + payload format is preserved.
///
/// ## Starting the Bridge
///
/// ```swift
/// let bridge = AESPWebSocketBridge(port: 47803)
/// bridge.delegate = myDelegate
/// try await bridge.start()
/// ```
///
/// ## Broadcasting from the Emulation Loop
///
/// ```swift
/// await bridge.broadcastFrame(frameBuffer)
/// await bridge.broadcastAudio(audioSamples)
/// ```
///
/// ## Thread Safety
///
/// As a Swift actor, all state access is serialized. The broadcast methods
/// can be called safely from the emulation loop alongside AESPServer broadcasts.
public actor AESPWebSocketBridge {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The port to listen on.
    private let port: Int

    /// Delegate for receiving messages from WebSocket clients.
    public weak var delegate: AESPWebSocketBridgeDelegate?

    /// Whether the bridge is currently running.
    public private(set) var isRunning: Bool = false

    /// Maximum number of WebSocket clients to accept.
    /// Web clients are more resource-intensive due to per-client delta encoding
    /// buffers and the overhead of WebSocket framing.
    public let maxClients: Int

    #if canImport(Network)
    /// The WebSocket listener.
    private var listener: NWListener?

    /// Connected WebSocket clients.
    private var clients: [UUID: WebSocketClientConnection] = [:]

    /// Pending connections that haven't completed the WebSocket handshake yet.
    private var pendingClients: [UUID: WebSocketClientConnection] = [:]
    #endif

    /// Frame counter for audio synchronization.
    private var frameCounter: UInt64 = 0

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new WebSocket bridge.
    ///
    /// - Parameters:
    ///   - port: The port to listen on (default: 47803).
    ///   - maxClients: Maximum number of simultaneous WebSocket clients (default: 8).
    public init(port: Int = AESPConstants.defaultWebSocketPort, maxClients: Int = 8) {
        self.port = port
        self.maxClients = maxClients
    }

    // =========================================================================
    // MARK: - Lifecycle
    // =========================================================================

    /// Starts the WebSocket bridge and begins listening for connections.
    ///
    /// The bridge uses Apple's Network framework with NWProtocolWebSocket to
    /// handle the HTTP upgrade handshake and WebSocket framing automatically.
    /// This means standard browser WebSocket clients can connect without any
    /// additional HTTP server infrastructure.
    ///
    /// - Throws: `AESPError.connectionError` if the listener cannot be started.
    public func start() async throws {
        guard !isRunning else { return }

        #if canImport(Network)
        do {
            listener = try createWebSocketListener()
            listener?.start(queue: .global(qos: .userInteractive))
            isRunning = true
            print("[AESPWebSocketBridge] Started on port \(port)")
        } catch {
            throw AESPError.connectionError("Failed to start WebSocket listener: \(error)")
        }
        #else
        throw AESPError.connectionError("Network framework not available")
        #endif
    }

    /// Stops the WebSocket bridge and disconnects all clients.
    ///
    /// All active WebSocket connections are closed with a normal closure code.
    /// The listener is cancelled and released.
    public func stop() async {
        guard isRunning else { return }

        #if canImport(Network)
        // Close all client connections
        for client in clients.values {
            client.connection.cancel()
        }
        for client in pendingClients.values {
            client.connection.cancel()
        }
        clients.removeAll()
        pendingClients.removeAll()

        // Stop listener
        listener?.cancel()
        listener = nil
        #endif

        isRunning = false
        print("[AESPWebSocketBridge] Stopped")
    }

    // =========================================================================
    // MARK: - Listener Setup
    // =========================================================================

    #if canImport(Network)
    /// Creates a NWListener configured for WebSocket connections.
    ///
    /// This sets up a TCP listener with WebSocket protocol options inserted
    /// into the application protocol stack. The Network framework handles:
    /// - TCP connection establishment
    /// - HTTP upgrade handshake (101 Switching Protocols)
    /// - WebSocket frame encoding/decoding
    /// - Ping/pong keepalives
    ///
    /// The WebSocket is configured to auto-respond to pings and auto-reply
    /// to close frames, which are standard behaviors that browsers expect.
    private func createWebSocketListener() throws -> NWListener {
        // Configure WebSocket protocol options.
        // autoReplyPing ensures the server responds to browser WebSocket pings
        // automatically without requiring application-level handling.
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        // Build the protocol stack: TCP -> WebSocket.
        // The Network framework inserts WebSocket as an "application protocol"
        // on top of TCP, handling the HTTP upgrade transparently.
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))

        // Handle listener state changes (ready, failed, cancelled).
        listener.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleListenerStateChange(state)
            }
        }

        // Handle new incoming WebSocket connections.
        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        return listener
    }

    /// Handles listener state transitions.
    ///
    /// Logs state changes for diagnostics. The listener transitions through:
    /// setup -> ready -> (cancelled | failed)
    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[AESPWebSocketBridge] Listener ready on port \(port)")
        case .failed(let error):
            print("[AESPWebSocketBridge] Listener failed: \(error)")
        case .cancelled:
            print("[AESPWebSocketBridge] Listener cancelled")
        default:
            break
        }
    }

    // =========================================================================
    // MARK: - Connection Handling
    // =========================================================================

    /// Handles a new incoming WebSocket connection.
    ///
    /// New connections are placed in a pending state until the WebSocket
    /// handshake completes (connection reaches .ready). This prevents
    /// broadcasting frames to connections that aren't fully established.
    ///
    /// If the maximum client count is reached, the connection is rejected
    /// immediately to prevent resource exhaustion.
    private func handleNewConnection(_ connection: NWConnection) {
        // Enforce client limit to prevent resource exhaustion.
        // Each WebSocket client consumes memory for delta encoding buffers
        // and CPU for frame serialization.
        if clients.count >= maxClients {
            print("[AESPWebSocketBridge] Rejecting connection: max clients (\(maxClients)) reached")
            connection.cancel()
            return
        }

        let clientId = UUID()
        let client = WebSocketClientConnection(id: clientId, connection: connection)

        // Store in pending until WebSocket handshake completes
        pendingClients[clientId] = client

        // Monitor connection state transitions
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleConnectionStateChange(state, clientId: clientId)
            }
        }

        // Start the connection (initiates WebSocket handshake)
        connection.start(queue: .global(qos: .userInteractive))
    }

    /// Handles connection state transitions for a WebSocket client.
    ///
    /// When a connection reaches .ready, the WebSocket handshake is complete
    /// and the client is promoted from pending to active. On failure or
    /// cancellation, the client is cleaned up.
    private func handleConnectionStateChange(_ state: NWConnection.State, clientId: UUID) {
        switch state {
        case .ready:
            // Promote from pending to active — WebSocket handshake is complete
            if let client = pendingClients.removeValue(forKey: clientId) {
                clients[clientId] = client
                print("[AESPWebSocketBridge] Client \(clientId) connected (total: \(clients.count))")

                // Notify delegate of new connection
                Task {
                    await delegate?.bridge(self, clientDidConnect: clientId)
                }

                // Begin receiving WebSocket messages from this client
                startReceiving(clientId: clientId)
            }

        case .failed(let error):
            print("[AESPWebSocketBridge] Client \(clientId) failed: \(error)")
            removeClient(clientId: clientId)

        case .cancelled:
            removeClient(clientId: clientId)

        default:
            break
        }
    }

    /// Removes a client from both pending and active tracking.
    ///
    /// Cancels the underlying connection and notifies the delegate if
    /// the client was active (not just pending).
    private func removeClient(clientId: UUID) {
        // Check pending first
        if let client = pendingClients.removeValue(forKey: clientId) {
            client.connection.cancel()
            return
        }

        // Remove from active clients
        if let client = clients.removeValue(forKey: clientId) {
            client.connection.cancel()
            print("[AESPWebSocketBridge] Client \(clientId) disconnected (total: \(clients.count))")

            Task {
                await delegate?.bridge(self, clientDidDisconnect: clientId)
            }
        }
    }

    // =========================================================================
    // MARK: - Receiving Messages
    // =========================================================================

    /// Starts receiving WebSocket messages from a client.
    ///
    /// Unlike TCP-based AESP where data arrives as a byte stream and must be
    /// reassembled, WebSocket provides message framing. Each `receiveMessage()`
    /// callback delivers exactly one complete WebSocket message, which contains
    /// one complete AESP message.
    ///
    /// This is a key advantage of WebSocket for the bridge: no need for the
    /// receive buffer and partial-message reassembly logic that AESPServer uses.
    private func startReceiving(clientId: UUID) {
        guard let client = clients[clientId] else { return }

        // receiveMessage() delivers one complete WebSocket message at a time.
        // For binary messages, this is the full AESP-encoded bytes.
        client.connection.receiveMessage { [weak self] content, context, isComplete, error in
            Task { [weak self] in
                if let data = content, !data.isEmpty {
                    // Decode any binary data as AESP messages.
                    // Network framework handles WebSocket framing transparently
                    // when NWProtocolWebSocket is in the protocol stack.
                    await self?.handleReceivedMessage(data, clientId: clientId)
                }

                if let error = error {
                    // An actual error occurred — remove the client
                    print("[AESPWebSocketBridge] Receive error from \(clientId): \(error)")
                    await self?.removeClient(clientId: clientId)
                } else {
                    // For WebSocket, isComplete: true from receiveMessage means
                    // "this WebSocket message is complete", NOT "the connection
                    // is closing". Each WebSocket message is a discrete unit.
                    // Always continue receiving the next message.
                    await self?.startReceiving(clientId: clientId)
                }
            }
        }
    }

    /// Handles a received binary WebSocket message from a client.
    ///
    /// The message data is a complete AESP binary message (8-byte header +
    /// payload). It is decoded and either handled internally (ping/pong) or
    /// forwarded to the delegate (control/input messages).
    private func handleReceivedMessage(_ data: Data, clientId: UUID) async {
        do {
            let (message, _) = try AESPMessage.decode(from: data)

            switch message.type {
            case .ping:
                // Respond with pong directly
                await sendMessage(.pong(), to: clientId)

            case .videoSubscribe, .audioSubscribe:
                // WebSocket clients are always subscribed to all channels
                // (single multiplexed connection), so these are acknowledged
                // but don't change state.
                await sendMessage(.ack(for: message.type), to: clientId)

            case .videoUnsubscribe, .audioUnsubscribe:
                // Acknowledged but no-op for WebSocket clients
                await sendMessage(.ack(for: message.type), to: clientId)

            default:
                // Forward control and input messages to the delegate
                await delegate?.bridge(self, didReceiveMessage: message, from: clientId)
            }
        } catch {
            print("[AESPWebSocketBridge] Error decoding message from \(clientId): \(error)")
        }
    }

    // =========================================================================
    // MARK: - Sending Messages
    // =========================================================================

    /// Sends an AESP message to a specific WebSocket client.
    ///
    /// The message is encoded to its binary AESP format and sent as a single
    /// WebSocket binary frame. The WebSocket metadata must be set to `.binary`
    /// opcode — this is a common gotcha with Network framework WebSocket
    /// support; without it, the framework may default to text frames.
    ///
    /// - Parameters:
    ///   - message: The AESP message to send.
    ///   - clientId: The target client's unique identifier.
    public func sendMessage(_ message: AESPMessage, to clientId: UUID) async {
        guard let client = clients[clientId] else { return }

        let data = message.encode()
        sendBinaryData(data, to: client)
    }

    /// Sends raw binary data as a WebSocket binary frame.
    ///
    /// Sets up the NWProtocolWebSocket.Metadata with .binary opcode and
    /// attaches it to the content context. This ensures the data is sent
    /// as a binary WebSocket frame, not a text frame.
    private func sendBinaryData(_ data: Data, to client: WebSocketClientConnection) {
        // Create WebSocket metadata specifying this is a binary message.
        // Without this, Network framework doesn't know the opcode and the
        // message may be malformed or rejected by the browser.
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "aesp-binary",
            metadata: [metadata]
        )

        // isComplete must be true for WebSocket — it signals that this WebSocket
        // message is complete. Unlike raw TCP, isComplete: true on a WebSocket
        // connection does NOT close the connection; it just marks the current
        // message as finished so receiveMessage() delivers it on the other side.
        // With isComplete: false, the framework buffers data indefinitely
        // waiting for more fragments, and receiveMessage() never fires.
        client.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error = error {
                    print("[AESPWebSocketBridge] Send error to \(client.id): \(error)")
                }
            }
        )
    }

    // =========================================================================
    // MARK: - Broadcasting
    // =========================================================================

    /// Broadcasts a video frame to all connected WebSocket clients.
    ///
    /// Called from the emulation loop after each frame. The frame is encoded
    /// as a FRAME_RAW AESP message and sent as a WebSocket binary frame to
    /// every connected client.
    ///
    /// - Parameter pixels: BGRA pixel data (336×240×4 = 322,560 bytes).
    public func broadcastFrame(_ pixels: [UInt8]) async {
        frameCounter += 1
        guard !clients.isEmpty else { return }

        let message = AESPMessage.frameRaw(pixels: pixels)
        let data = message.encode()

        for client in clients.values {
            sendBinaryData(data, to: client)
        }
    }

    /// Broadcasts a video frame to all connected WebSocket clients.
    ///
    /// Convenience overload accepting Data instead of [UInt8].
    ///
    /// - Parameter pixels: BGRA pixel data as Data.
    public func broadcastFrame(_ pixels: Data) async {
        await broadcastFrame(Array(pixels))
    }

    /// Broadcasts audio samples to all connected WebSocket clients.
    ///
    /// Called from the emulation loop with each batch of audio samples.
    /// Samples are 16-bit signed PCM, mono, sent as an AUDIO_PCM AESP message.
    ///
    /// - Parameter samples: Raw PCM audio samples as bytes.
    public func broadcastAudio(_ samples: [UInt8]) async {
        guard !clients.isEmpty else { return }

        let message = AESPMessage.audioPCM(samples: Data(samples))
        let data = message.encode()

        for client in clients.values {
            sendBinaryData(data, to: client)
        }
    }

    /// Broadcasts audio samples to all connected WebSocket clients.
    ///
    /// Convenience overload accepting Data instead of [UInt8].
    ///
    /// - Parameter samples: Raw PCM audio samples as Data.
    public func broadcastAudio(_ samples: Data) async {
        await broadcastAudio(Array(samples))
    }

    /// Broadcasts an audio sync message with the current frame number.
    ///
    /// Allows web clients to correlate audio buffers with video frames
    /// for A/V synchronization. Should be called periodically from the
    /// emulation loop (e.g., every frame or every few frames).
    ///
    /// - Parameter frameNumber: The current frame counter value.
    public func broadcastAudioSync(frameNumber: UInt64) async {
        guard !clients.isEmpty else { return }

        let message = AESPMessage.audioSync(frameNumber: frameNumber)
        let data = message.encode()

        for client in clients.values {
            sendBinaryData(data, to: client)
        }
    }

    // =========================================================================
    // MARK: - Client Information
    // =========================================================================

    /// Returns the number of connected WebSocket clients.
    public var clientCount: Int {
        #if canImport(Network)
        return clients.count
        #else
        return 0
        #endif
    }

    /// Returns the current frame counter value.
    public var currentFrameNumber: UInt64 {
        return frameCounter
    }
    #endif
}

// MARK: - Delegate Setter Extension

extension AESPWebSocketBridge {
    /// Sets the bridge delegate.
    ///
    /// Convenience method matching the pattern used by AESPServer.setDelegate().
    public func setDelegate(_ delegate: AESPWebSocketBridgeDelegate) {
        self.delegate = delegate
    }
}
