// =============================================================================
// AESPClient.swift - AESP Protocol Client
// =============================================================================
//
// This file implements the client-side of the Attic Emulator Server Protocol.
// A client connects to an emulator server and can:
//
// - Send control commands (pause, resume, reset)
// - Send input events (keyboard, joystick)
// - Subscribe to video frame streams
// - Subscribe to audio sample streams
//
// The client is implemented as a Swift actor for thread-safe state management.
//
// ## Usage
//
// ```swift
// let client = AESPClient()
// try await client.connect(host: "localhost")
//
// // Subscribe to video frames
// await client.subscribeToVideo()
// for await frame in await client.frameStream {
//     renderer.updateTexture(with: frame)
// }
//
// // Send input
// await client.sendKeyDown(keyChar: 65, keyCode: 0x3F, shift: false, control: false)
// await client.sendKeyUp()
//
// // Disconnect
// await client.disconnect()
// ```
//
// =============================================================================

import Foundation
#if canImport(Network)
import Network
#endif
@preconcurrency import Dispatch
import os.lock

// MARK: - Continuation Resume Guard

/// A thread-safe guard to prevent resuming a continuation more than once.
///
/// This class uses an atomic flag to ensure that only one call to `tryResume()`
/// succeeds, even when called from multiple threads concurrently.
private final class ContinuationResumeGuard: @unchecked Sendable {
    /// The underlying lock for atomic access.
    private let lock = OSAllocatedUnfairLock(initialState: false)

    /// Attempts to mark the continuation as resumed.
    ///
    /// - Returns: `true` if this is the first call (continuation should be resumed),
    ///   `false` if already resumed (continuation should NOT be resumed again).
    func tryResume() -> Bool {
        return lock.withLock { hasResumed in
            if hasResumed {
                return false
            }
            hasResumed = true
            return true
        }
    }
}

// MARK: - Client Configuration

/// Configuration for the AESP client.
public struct AESPClientConfiguration: Sendable {
    /// Server host address.
    public var host: String

    /// Port for control channel.
    public var controlPort: Int

    /// Port for video channel.
    public var videoPort: Int

    /// Port for audio channel.
    public var audioPort: Int

    /// Connection timeout in seconds.
    public var connectionTimeout: TimeInterval

    /// Creates a default configuration.
    public init(
        host: String = "localhost",
        controlPort: Int = AESPConstants.defaultControlPort,
        videoPort: Int = AESPConstants.defaultVideoPort,
        audioPort: Int = AESPConstants.defaultAudioPort,
        connectionTimeout: TimeInterval = 5.0
    ) {
        self.host = host
        self.controlPort = controlPort
        self.videoPort = videoPort
        self.audioPort = audioPort
        self.connectionTimeout = connectionTimeout
    }
}

// MARK: - Client Delegate Protocol

/// Delegate protocol for receiving client events.
public protocol AESPClientDelegate: AnyObject, Sendable {
    /// Called when a control message is received from the server.
    func client(_ client: AESPClient, didReceiveMessage message: AESPMessage) async

    /// Called when the connection state changes.
    func client(_ client: AESPClient, didChangeState isConnected: Bool) async

    /// Called when an error occurs.
    func client(_ client: AESPClient, didEncounterError error: Error) async
}

// MARK: - Connection State

/// The connection state of the client.
public enum AESPClientState: Sendable {
    /// Not connected to server.
    case disconnected

    /// Connecting to server.
    case connecting

    /// Connected to server.
    case connected

    /// Connection failed.
    case failed(Error)
}

// MARK: - AESP Client Actor

/// The AESP protocol client.
///
/// This actor manages network connections to an emulator server.
/// It provides methods for sending input and commands, and
/// AsyncStreams for receiving video frames and audio samples.
///
/// ## Connecting to a Server
///
/// ```swift
/// let client = AESPClient()
/// try await client.connect(host: "localhost")
/// ```
///
/// ## Receiving Video Frames
///
/// Subscribe to video and iterate over the frame stream:
/// ```swift
/// await client.subscribeToVideo()
/// for await frame in await client.frameStream {
///     renderer.updateTexture(with: frame)
/// }
/// ```
///
/// ## Sending Input
///
/// ```swift
/// await client.sendKeyDown(keyChar: 65, keyCode: 0x3F, shift: false, control: false)
/// await client.sendKeyUp()
/// await client.sendConsoleKeys(start: true, select: false, option: false)
/// ```
public actor AESPClient {

    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// Client configuration.
    public let configuration: AESPClientConfiguration

    /// Delegate for receiving events.
    public weak var delegate: AESPClientDelegate?

    /// Current connection state.
    public private(set) var state: AESPClientState = .disconnected

    /// Timestamp of the most recent PONG received from the server.
    /// Used by heartbeat monitors to detect server loss — if this remains
    /// nil or stale for too long, the server is presumed dead.
    public private(set) var lastPongReceived: Date?

    /// Whether the client is connected.
    public var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    #if canImport(Network)
    /// Control channel connection.
    private var controlConnection: NWConnection?

    /// Video channel connection.
    private var videoConnection: NWConnection?

    /// Audio channel connection.
    private var audioConnection: NWConnection?
    #endif

    /// Buffer for incomplete control data.
    private var controlReceiveBuffer: Data = Data()

    /// Buffer for incomplete video data.
    private var videoReceiveBuffer: Data = Data()

    /// Index of next byte to consume in video buffer (for efficient buffer management).
    /// Using index tracking avoids O(n) removeFirst() operations on large buffers.
    private var videoBufferConsumed: Int = 0

    /// Buffer for incomplete audio data.
    private var audioReceiveBuffer: Data = Data()

    /// Index of next byte to consume in audio buffer.
    private var audioBufferConsumed: Int = 0

    /// Continuation for the frame stream.
    /// Uses Data instead of [UInt8] to avoid expensive Array copy on each frame.
    private var frameContinuation: AsyncStream<Data>.Continuation?

    /// Continuation for the audio stream.
    /// Uses Data instead of [UInt8] to avoid expensive Array copy.
    private var audioContinuation: AsyncStream<Data>.Continuation?

    /// The video frame stream.
    private var _frameStream: AsyncStream<Data>?

    /// The audio sample stream.
    private var _audioStream: AsyncStream<Data>?

    /// Pending continuation for a status request-response.
    /// Set by `requestStatusWithDisks()` and resumed by `handleControlMessage()`
    /// when a `.status` response arrives.
    private var pendingStatusContinuation: CheckedContinuation<AESPMessage.StatusPayload, Never>?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new AESP client with the given configuration.
    ///
    /// - Parameter configuration: Client configuration (host, ports).
    public init(configuration: AESPClientConfiguration = AESPClientConfiguration()) {
        self.configuration = configuration
    }

    /// Creates a new AESP client with a custom host.
    ///
    /// - Parameter host: The server host address.
    public init(host: String) {
        self.configuration = AESPClientConfiguration(host: host)
    }

    // =========================================================================
    // MARK: - Connection Management
    // =========================================================================

    /// Connects to the emulator server.
    ///
    /// This establishes connections to the control, video, and audio ports.
    /// You can optionally connect to only specific channels.
    ///
    /// - Parameters:
    ///   - host: Optional host override.
    ///   - connectVideo: Whether to connect to the video channel.
    ///   - connectAudio: Whether to connect to the audio channel.
    /// - Throws: `AESPError.connectionError` if connection fails.
    public func connect(
        host: String? = nil,
        connectVideo: Bool = true,
        connectAudio: Bool = true
    ) async throws {
        guard !isConnected else { return }

        state = .connecting
        let targetHost = host ?? configuration.host

        #if canImport(Network)
        do {
            // Connect to control channel (always)
            controlConnection = try await createConnection(
                host: targetHost,
                port: configuration.controlPort,
                channel: .control
            )

            // Connect to video channel if requested
            if connectVideo {
                videoConnection = try await createConnection(
                    host: targetHost,
                    port: configuration.videoPort,
                    channel: .video
                )
                setupVideoStream()
            }

            // Connect to audio channel if requested
            if connectAudio {
                audioConnection = try await createConnection(
                    host: targetHost,
                    port: configuration.audioPort,
                    channel: .audio
                )
                setupAudioStream()
            }

            state = .connected
            print("[AESPClient] Connected to \(targetHost)")

            // Notify delegate
            await delegate?.client(self, didChangeState: true)

            // Start receiving on all channels
            startReceiving()

        } catch {
            state = .failed(error)
            throw AESPError.connectionError("Failed to connect: \(error)")
        }
        #else
        throw AESPError.connectionError("Network framework not available")
        #endif
    }

    /// Disconnects from the emulator server.
    ///
    /// All connections are closed and streams are terminated.
    public func disconnect() async {
        #if canImport(Network)
        controlConnection?.cancel()
        videoConnection?.cancel()
        audioConnection?.cancel()

        controlConnection = nil
        videoConnection = nil
        audioConnection = nil
        #endif

        // Finish streams
        frameContinuation?.finish()
        audioContinuation?.finish()
        frameContinuation = nil
        audioContinuation = nil
        _frameStream = nil
        _audioStream = nil

        // Clear buffers and reset consumed indices
        controlReceiveBuffer.removeAll()
        videoReceiveBuffer.removeAll()
        videoBufferConsumed = 0
        audioReceiveBuffer.removeAll()
        audioBufferConsumed = 0

        state = .disconnected
        print("[AESPClient] Disconnected")

        // Notify delegate
        await delegate?.client(self, didChangeState: false)
    }

    #if canImport(Network)
    /// Creates a connection to the specified host and port with timeout.
    ///
    /// - Parameters:
    ///   - host: The host to connect to.
    ///   - port: The port to connect to.
    ///   - channel: The channel type (for logging and state management).
    /// - Returns: The established NWConnection.
    /// - Throws: `AESPError.connectionError` if connection fails or times out.
    private func createConnection(host: String, port: Int, channel: AESPChannel) async throws -> NWConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        let timeout = configuration.connectionTimeout

        return try await withCheckedThrowingContinuation { continuation in
            // Use a thread-safe flag to track whether continuation has been resumed
            let resumeGuard = ContinuationResumeGuard()

            // Set up timeout - if connection doesn't establish in time, cancel it
            let timeoutWorkItem = DispatchWorkItem {
                if resumeGuard.tryResume() {
                    connection.cancel()
                    continuation.resume(throwing: AESPError.connectionError("Connection timed out after \(timeout)s"))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            connection.stateUpdateHandler = { [resumeGuard, weak self] state in
                switch state {
                case .ready:
                    // Only resume continuation once
                    if resumeGuard.tryResume() {
                        // Cancel the timeout since we connected successfully
                        timeoutWorkItem.cancel()
                        // Keep monitoring state for disconnection events
                        continuation.resume(returning: connection)
                    }
                case .failed(let error):
                    if resumeGuard.tryResume() {
                        timeoutWorkItem.cancel()
                        continuation.resume(throwing: error)
                    } else {
                        // Connection failed after initial establishment
                        Task { [weak self] in
                            await self?.handleDisconnection(channel: channel)
                        }
                    }
                case .cancelled:
                    if resumeGuard.tryResume() {
                        timeoutWorkItem.cancel()
                        continuation.resume(throwing: AESPError.connectionError("Connection cancelled"))
                    } else {
                        // Connection cancelled after initial establishment
                        Task { [weak self] in
                            await self?.handleDisconnection(channel: channel)
                        }
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInteractive))
        }
    }

    /// Starts receiving on all connected channels.
    private func startReceiving() {
        if let connection = controlConnection {
            receiveLoop(connection: connection, channel: .control)
        }
        if let connection = videoConnection {
            receiveLoop(connection: connection, channel: .video)
        }
        if let connection = audioConnection {
            receiveLoop(connection: connection, channel: .audio)
        }
    }

    /// Receive loop for a channel.
    private func receiveLoop(connection: NWConnection, channel: AESPChannel) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                guard let self = self else { return }

                if let data = data, !data.isEmpty {
                    await self.handleReceivedData(data, channel: channel)
                }

                if isComplete || error != nil {
                    await self.handleDisconnection(channel: channel)
                } else {
                    // Continue receiving
                    await self.receiveLoop(connection: connection, channel: channel)
                }
            }
        }
    }
    #endif

    /// Handles received data from a channel.
    private func handleReceivedData(_ data: Data, channel: AESPChannel) async {
        // Append to appropriate buffer and process
        switch channel {
        case .control:
            controlReceiveBuffer.append(data)
            await processControlBuffer()
        case .video:
            // Compact buffer if consumed portion is too large (>1MB)
            // This prevents unbounded buffer growth while avoiding frequent O(n) shifts
            if videoBufferConsumed > 1_000_000 {
                videoReceiveBuffer.removeFirst(videoBufferConsumed)
                videoBufferConsumed = 0
            }
            videoReceiveBuffer.append(data)
            await processVideoBuffer()
        case .audio:
            // Compact audio buffer if consumed portion is too large
            if audioBufferConsumed > 100_000 {
                audioReceiveBuffer.removeFirst(audioBufferConsumed)
                audioBufferConsumed = 0
            }
            audioReceiveBuffer.append(data)
            await processAudioBuffer()
        }
    }

    /// Processes the control receive buffer.
    private func processControlBuffer() async {
        while let messageSize = AESPMessage.messageSize(in: controlReceiveBuffer) {
            do {
                let (message, _) = try AESPMessage.decode(from: controlReceiveBuffer)
                controlReceiveBuffer.removeFirst(messageSize)
                await handleControlMessage(message)
            } catch {
                print("[AESPClient] Error decoding control message: \(error)")
                controlReceiveBuffer.removeAll()
                break
            }
        }
    }

    /// Processes the video receive buffer.
    ///
    /// Uses index-based tracking to avoid O(n) removeFirst() on every frame.
    /// The buffer is only compacted when the consumed portion exceeds a threshold.
    private func processVideoBuffer() async {
        // Process all complete messages in the buffer
        while true {
            // Get unconsumed portion using dropFirst (safe: returns empty if index >= count)
            let unconsumedData = Data(videoReceiveBuffer.dropFirst(videoBufferConsumed))

            // Check if we have a complete message
            guard let messageSize = AESPMessage.messageSize(in: unconsumedData) else {
                // Incomplete message or empty buffer, wait for more data
                break
            }

            do {
                let (message, _) = try AESPMessage.decode(from: unconsumedData)

                // Advance the consumed index instead of removing bytes (O(1) vs O(n))
                videoBufferConsumed += messageSize

                if message.type == .frameRaw {
                    // Emit frame payload directly as Data (no Array copy needed)
                    frameContinuation?.yield(message.payload)
                }
            } catch {
                print("[AESPClient] Error decoding video message: \(error)")
                videoReceiveBuffer.removeAll()
                videoBufferConsumed = 0
                break
            }
        }
    }

    /// Processes the audio receive buffer.
    ///
    /// Uses index-based tracking to avoid O(n) removeFirst() operations.
    private func processAudioBuffer() async {
        // Process all complete messages in the buffer
        while true {
            // Get unconsumed portion using dropFirst (safe: returns empty if index >= count)
            let unconsumedData = Data(audioReceiveBuffer.dropFirst(audioBufferConsumed))

            // Check if we have a complete message
            guard let messageSize = AESPMessage.messageSize(in: unconsumedData) else {
                // Incomplete message or empty buffer, wait for more data
                break
            }

            do {
                let (message, _) = try AESPMessage.decode(from: unconsumedData)

                // Advance the consumed index (O(1) operation)
                audioBufferConsumed += messageSize

                if message.type == .audioPCM {
                    // Emit samples directly as Data (no Array copy needed)
                    audioContinuation?.yield(message.payload)
                }
            } catch {
                print("[AESPClient] Error decoding audio message: \(error)")
                audioReceiveBuffer.removeAll()
                audioBufferConsumed = 0
                break
            }
        }
    }

    /// Handles a control message from the server.
    private func handleControlMessage(_ message: AESPMessage) async {
        switch message.type {
        case .pong:
            // Ping response received — record the timestamp for heartbeat monitoring
            lastPongReceived = Date()

        case .status:
            // If a requestStatusWithDisks() call is waiting, fulfil its continuation
            if let continuation = pendingStatusContinuation {
                pendingStatusContinuation = nil
                let payload = message.parseStatusWithDisks()
                    ?? AESPMessage.StatusPayload(isRunning: false, mountedDrives: [])
                continuation.resume(returning: payload)
            } else {
                // No pending request — forward to delegate
                await delegate?.client(self, didReceiveMessage: message)
            }

        case .error:
            if let (code, errorMessage) = message.parseErrorPayload() {
                let error = AESPError.serverError(code: code, message: errorMessage)
                await delegate?.client(self, didEncounterError: error)
            }

        default:
            // Forward to delegate
            await delegate?.client(self, didReceiveMessage: message)
        }
    }

    /// Handles disconnection on a channel.
    private func handleDisconnection(channel: AESPChannel) async {
        print("[AESPClient] Disconnected from \(channel.rawValue) channel")

        // If control disconnects, consider fully disconnected
        if channel == .control {
            await disconnect()
        }
    }

    // =========================================================================
    // MARK: - Stream Setup
    // =========================================================================

    /// Sets up the video frame stream.
    private func setupVideoStream() {
        _frameStream = AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }

    /// Sets up the audio sample stream.
    private func setupAudioStream() {
        _audioStream = AsyncStream { continuation in
            self.audioContinuation = continuation
        }
    }

    /// The video frame stream.
    ///
    /// Iterate over this stream to receive video frames as Data:
    /// ```swift
    /// for await frameData in await client.frameStream {
    ///     renderer.updateTexture(with: frameData)
    /// }
    /// ```
    ///
    /// Note: Uses Data instead of [UInt8] for zero-copy frame delivery.
    public var frameStream: AsyncStream<Data> {
        return _frameStream ?? AsyncStream { $0.finish() }
    }

    /// The audio sample stream.
    ///
    /// Iterate over this stream to receive audio samples as Data:
    /// ```swift
    /// for await samples in await client.audioStream {
    ///     audioEngine.enqueueSamples(data: samples)
    /// }
    /// ```
    ///
    /// Note: Uses Data instead of [UInt8] for zero-copy delivery.
    public var audioStream: AsyncStream<Data> {
        return _audioStream ?? AsyncStream { $0.finish() }
    }

    // =========================================================================
    // MARK: - Subscriptions
    // =========================================================================

    /// Subscribes to video frames.
    ///
    /// - Parameter deltaEncoding: If true, request delta-encoded frames (for web clients).
    public func subscribeToVideo(deltaEncoding: Bool = false) async {
        await sendMessage(.videoSubscribe(deltaEncoding: deltaEncoding))
    }

    /// Unsubscribes from video frames.
    public func unsubscribeFromVideo() async {
        await sendMessage(.videoUnsubscribe())
    }

    /// Subscribes to audio samples.
    public func subscribeToAudio() async {
        await sendMessage(.audioSubscribe())
    }

    /// Unsubscribes from audio samples.
    public func unsubscribeFromAudio() async {
        await sendMessage(.audioUnsubscribe())
    }

    // =========================================================================
    // MARK: - Sending Messages
    // =========================================================================

    /// Sends a message to the server.
    ///
    /// - Parameter message: The message to send.
    public func sendMessage(_ message: AESPMessage) async {
        #if canImport(Network)
        guard let connection = controlConnection else { return }

        let data = message.encode()
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[AESPClient] Error sending message: \(error)")
            }
        })
        #endif
    }

    // =========================================================================
    // MARK: - Control Commands
    // =========================================================================

    /// Sends a ping to the server.
    public func ping() async {
        await sendMessage(.ping())
    }

    /// Pauses emulation.
    public func pause() async {
        await sendMessage(.pause())
    }

    /// Resumes emulation.
    public func resume() async {
        await sendMessage(.resume())
    }

    /// Resets the emulator.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    public func reset(cold: Bool = false) async {
        await sendMessage(.reset(cold: cold))
    }

    /// Requests emulator status (fire-and-forget).
    public func requestStatus() async {
        await sendMessage(.status())
    }

    /// Requests emulator status and waits for the response with disk information.
    ///
    /// Sends a STATUS request and awaits the server's response, which includes
    /// the running state and any mounted drive filenames. This is a request-response
    /// pattern: the next `.status` message received on the control channel will
    /// fulfil this call.
    ///
    /// - Returns: A `StatusPayload` containing running state and mounted drives.
    public func requestStatusWithDisks() async -> AESPMessage.StatusPayload {
        return await withCheckedContinuation { continuation in
            pendingStatusContinuation = continuation
            Task {
                await sendMessage(.status())
            }
        }
    }

    /// Boots the emulator with a file (disk image, executable, BASIC program, etc.).
    ///
    /// Sends a BOOT_FILE request to the server, which validates the file,
    /// calls `libatari800_reboot_with_file`, and returns a response.
    ///
    /// - Parameter filePath: Absolute path to the file to boot.
    public func bootFile(filePath: String) async {
        await sendMessage(.bootFile(filePath: filePath))
    }

    // =========================================================================
    // MARK: - Input
    // =========================================================================

    /// Sends a key down event.
    ///
    /// - Parameters:
    ///   - keyChar: The ATASCII character code (0 for special keys).
    ///   - keyCode: The Atari key code (AKEY_* constant).
    ///   - shift: Whether Shift is held.
    ///   - control: Whether Control is held.
    public func sendKeyDown(
        keyChar: UInt8,
        keyCode: UInt8,
        shift: Bool = false,
        control: Bool = false
    ) async {
        await sendMessage(.keyDown(keyChar: keyChar, keyCode: keyCode, shift: shift, control: control))
    }

    /// Sends a key up event.
    public func sendKeyUp() async {
        await sendMessage(.keyUp())
    }

    /// Sends a joystick state update.
    ///
    /// - Parameters:
    ///   - port: Joystick port (0 or 1).
    ///   - up: Up direction pressed.
    ///   - down: Down direction pressed.
    ///   - left: Left direction pressed.
    ///   - right: Right direction pressed.
    ///   - trigger: Trigger/button pressed.
    public func sendJoystick(
        port: UInt8 = 0,
        up: Bool = false,
        down: Bool = false,
        left: Bool = false,
        right: Bool = false,
        trigger: Bool = false
    ) async {
        var directions: UInt8 = 0
        if up { directions |= 0x01 }
        if down { directions |= 0x02 }
        if left { directions |= 0x04 }
        if right { directions |= 0x08 }
        await sendMessage(.joystick(port: port, directions: directions, trigger: trigger))
    }

    /// Sends console key states (START, SELECT, OPTION).
    ///
    /// - Parameters:
    ///   - start: Whether START is pressed.
    ///   - select: Whether SELECT is pressed.
    ///   - option: Whether OPTION is pressed.
    public func sendConsoleKeys(
        start: Bool = false,
        select: Bool = false,
        option: Bool = false
    ) async {
        await sendMessage(.consoleKeys(start: start, select: select, option: option))
    }
}
