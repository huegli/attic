// =============================================================================
// AESPEndToEndTests.swift - End-to-End Tests for AESP Protocol
// =============================================================================
//
// This file contains end-to-end tests that verify actual message exchange
// through real TCP connections between AESPServer and AESPClient. Unlike the
// unit tests (encoding/decoding) and basic integration tests (lifecycle),
// these tests prove that messages traverse the network correctly.
//
// Test Coverage:
// - Control channel: PING/PONG, PAUSE→ACK, RESUME→ACK, STATUS
// - Video channel: Frame delivery, full-size frames, multiple frames, no-video
// - Audio channel: Audio delivery, sample sizes, multiple buffers, no-audio,
//   PCM integrity
// - Error handling: Invalid magic, invalid version, unknown message type,
//   oversized payload, server ERROR message
// - Message types: INFO, BOOT_FILE, RESET, PADDLE, FRAME_CONFIG, AUDIO_CONFIG
//
// Port Allocation (49000-49499, avoids conflicts with existing tests):
// - Control tests: 49000-49099
// - Video tests: 49100-49199
// - Audio tests: 49200-49299
// - Error tests: 49300-49399
// - Message type tests: 49400-49499
//
// =============================================================================

import XCTest
@testable import AtticProtocol
#if canImport(Network)
import Network
#endif

// =============================================================================
// MARK: - Responding Mock Server Delegate
// =============================================================================

/// Actor-based storage for the responding mock delegate.
///
/// This actor provides thread-safe storage for messages received by the
/// server delegate, and tracks which responses were sent. Unlike the basic
/// MockServerDelegate in the integration tests, this delegate automatically
/// responds to messages like a real server would.
private actor RespondingDelegateStorage {
    /// All messages received from clients.
    var receivedMessages: [AESPMessage] = []

    /// Client connection events: (clientId, channel).
    var connectedClients: [(UUID, AESPChannel)] = []

    /// Client disconnection events: (clientId, channel).
    var disconnectedClients: [(UUID, AESPChannel)] = []

    func addMessage(_ message: AESPMessage) {
        receivedMessages.append(message)
    }

    func addConnectedClient(_ clientId: UUID, channel: AESPChannel) {
        connectedClients.append((clientId, channel))
    }

    func addDisconnectedClient(_ clientId: UUID, channel: AESPChannel) {
        disconnectedClients.append((clientId, channel))
    }
}

/// A server delegate that automatically responds to client messages.
///
/// This mimics the behavior of the real AtticServer's ServerDelegate:
/// - PAUSE → ACK(PAUSE)
/// - RESUME → ACK(RESUME)
/// - STATUS → StatusResponse with disk info
/// - INFO → InfoResponse with JSON capabilities
/// - BOOT_FILE → BootFileResponse (success for .atr files, failure otherwise)
/// - RESET → StatusResponse (running, no drives)
///
/// PING/PONG is handled automatically by AESPServer (not the delegate),
/// so it doesn't appear here.
private final class RespondingMockDelegate: AESPServerDelegate, @unchecked Sendable {
    let storage = RespondingDelegateStorage()

    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        await storage.addMessage(message)

        switch message.type {
        case .pause:
            // Respond with ACK for PAUSE
            await server.sendMessage(.ack(for: .pause), to: clientId, channel: .control)

        case .resume:
            // Respond with ACK for RESUME
            await server.sendMessage(.ack(for: .resume), to: clientId, channel: .control)

        case .status:
            // Respond with status including mounted drives
            let response = AESPMessage.statusResponse(
                isRunning: true,
                mountedDrives: [(drive: 1, filename: "GAME.ATR")]
            )
            await server.sendMessage(response, to: clientId, channel: .control)

        case .info:
            // Respond with emulator capabilities as JSON
            let json = """
            {"version":"1.0","name":"Attic","platform":"macOS"}
            """
            await server.sendMessage(.infoResponse(json: json), to: clientId, channel: .control)

        case .bootFile:
            // Simulate boot: succeed for .atr files, fail otherwise
            let filePath = message.parseBootFileRequest() ?? ""
            if filePath.hasSuffix(".atr") {
                await server.sendMessage(
                    .bootFileResponse(success: true, message: "Disk image loaded"),
                    to: clientId, channel: .control
                )
            } else {
                await server.sendMessage(
                    .bootFileResponse(success: false, message: "Unsupported file type"),
                    to: clientId, channel: .control
                )
            }

        case .reset:
            // Respond with status after reset (running, no mounted drives)
            let response = AESPMessage.statusResponse(
                isRunning: true,
                mountedDrives: []
            )
            await server.sendMessage(response, to: clientId, channel: .control)

        default:
            break
        }
    }

    func server(_ server: AESPServer, clientDidConnect clientId: UUID, channel: AESPChannel) async {
        await storage.addConnectedClient(clientId, channel: channel)
    }

    func server(_ server: AESPServer, clientDidDisconnect clientId: UUID, channel: AESPChannel) async {
        await storage.addDisconnectedClient(clientId, channel: channel)
    }
}

// =============================================================================
// MARK: - Mock Client Delegate
// =============================================================================

/// Actor-based storage for the mock client delegate.
///
/// Captures all messages, state changes, and errors received by the client.
private actor ClientDelegateStorage {
    /// Messages received from the server (via delegate callback).
    var receivedMessages: [AESPMessage] = []

    /// Connection state changes (true = connected, false = disconnected).
    var stateChanges: [Bool] = []

    /// Errors encountered by the client.
    var errors: [Error] = []

    func addMessage(_ message: AESPMessage) {
        receivedMessages.append(message)
    }

    func addStateChange(_ isConnected: Bool) {
        stateChanges.append(isConnected)
    }

    func addError(_ error: Error) {
        errors.append(error)
    }
}

/// A client delegate that captures received events for test assertions.
///
/// Unlike the server delegate, this delegate doesn't respond to anything —
/// it simply records what the client received so tests can verify it.
private final class MockClientDelegate: AESPClientDelegate, @unchecked Sendable {
    let storage = ClientDelegateStorage()

    func client(_ client: AESPClient, didReceiveMessage message: AESPMessage) async {
        await storage.addMessage(message)
    }

    func client(_ client: AESPClient, didChangeState isConnected: Bool) async {
        await storage.addStateChange(isConnected)
    }

    func client(_ client: AESPClient, didEncounterError error: Error) async {
        await storage.addError(error)
    }
}

// =============================================================================
// MARK: - Test Helpers
// =============================================================================

/// Standard delay for server startup (100ms).
private let serverStartDelay: UInt64 = 100_000_000

/// Standard delay for message propagation (200ms).
private let messagePropagationDelay: UInt64 = 200_000_000

/// Creates a server and client pair with the given port configuration.
///
/// This is a DRY helper that handles the boilerplate of creating matching
/// server/client configurations, starting the server, and connecting the client.
///
/// - Parameters:
///   - controlPort: Base port for control channel.
///   - connectVideo: Whether the client should connect to video channel.
///   - connectAudio: Whether the client should connect to audio channel.
///   - delegate: The server delegate to use.
///   - clientDelegate: The client delegate to use.
/// - Returns: Tuple of (server, client) ready for testing.
private func createServerAndClient(
    controlPort: Int,
    connectVideo: Bool = false,
    connectAudio: Bool = false,
    delegate: RespondingMockDelegate? = nil,
    clientDelegate: MockClientDelegate? = nil
) async throws -> (AESPServer, AESPClient) {
    let serverConfig = AESPServerConfiguration(
        controlPort: controlPort,
        videoPort: controlPort + 1,
        audioPort: controlPort + 2
    )
    let server = AESPServer(configuration: serverConfig)

    if let delegate = delegate {
        await server.setDelegate(delegate)
    }

    try await server.start()
    try await Task.sleep(nanoseconds: serverStartDelay)

    let clientConfig = AESPClientConfiguration(
        host: "localhost",
        controlPort: controlPort,
        videoPort: controlPort + 1,
        audioPort: controlPort + 2
    )
    let client = AESPClient(configuration: clientConfig)

    if let clientDelegate = clientDelegate {
        await client.setDelegate(clientDelegate)
    }

    try await client.connect(connectVideo: connectVideo, connectAudio: connectAudio)
    try await Task.sleep(nanoseconds: serverStartDelay)

    return (server, client)
}

/// Extension to set delegate on AESPServer (convenience for tests).
///
/// The server's `delegate` property is directly assignable since AESPServer
/// is an actor — we just need `await` to cross the actor boundary.
private extension AESPServer {
    func setDelegate(_ delegate: AESPServerDelegate) {
        self.delegate = delegate
    }
}

/// Extension to set delegate on AESPClient (convenience for tests).
private extension AESPClient {
    func setDelegate(_ delegate: AESPClientDelegate) {
        self.delegate = delegate
    }
}

// =============================================================================
// MARK: - Control Channel End-to-End Tests (Sub-task 5.1)
// =============================================================================

/// End-to-end tests for the AESP control channel.
///
/// These tests verify that control messages travel through real TCP connections
/// between server and client. Port range: 49000-49099.
///
/// Key insight: PING/PONG is tested with raw TCP because the AESPClient
/// silently swallows PONG responses (they're handled internally without
/// forwarding to the delegate). Raw TCP lets us verify the server's auto-PONG
/// at the wire level.
final class AESPControlChannelE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test PING/PONG using raw TCP connection.
    ///
    /// The server auto-responds to PING with PONG (handled in
    /// AESPServer.handleMessage, not the delegate). The client swallows
    /// PONG internally, so we use a raw NWConnection to verify the
    /// response arrives on the wire.
    func test_pingPong_rawTCP() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let port = 49000
        let serverConfig = AESPServerConfiguration(
            controlPort: port, videoPort: port + 1, audioPort: port + 2
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: serverStartDelay)

        // Create raw TCP connection to control port
        let endpoint = NWEndpoint.hostPort(
            host: "localhost",
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        let connection = NWConnection(to: endpoint, using: .tcp)

        // Wait for connection to be ready
        let connected = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume(returning: true)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        XCTAssertTrue(connected)

        // Send a PING message
        let pingData = AESPMessage.ping().encode()
        connection.send(content: pingData, completion: .contentProcessed { error in
            XCTAssertNil(error)
        })

        // Receive the PONG response
        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 8, maximumLength: 256) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: AESPError.connectionError("No data received"))
                }
            }
        }

        // Decode and verify it's a PONG
        let (response, _) = try AESPMessage.decode(from: responseData)
        XCTAssertEqual(response.type, .pong)

        connection.cancel()
        await server.stop()
    }

    /// Test PAUSE command → ACK response flow.
    ///
    /// Client sends PAUSE → server delegate receives it → delegate responds
    /// with ACK → client delegate receives ACK.
    func test_pauseAck() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49003,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send PAUSE
        await client.pause()

        // Wait for round-trip
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received PAUSE
        let serverMessages = await delegate.storage.receivedMessages
        XCTAssertTrue(serverMessages.contains { $0.type == .pause },
                      "Server should have received PAUSE")

        // Verify client received ACK for PAUSE
        let clientMessages = await clientDelegate.storage.receivedMessages
        let acks = clientMessages.filter { $0.type == .ack }
        XCTAssertFalse(acks.isEmpty, "Client should have received ACK")
        XCTAssertEqual(acks.first?.payload.first, AESPMessageType.pause.rawValue,
                       "ACK should reference PAUSE")

        await client.disconnect()
        await server.stop()
    }

    /// Test RESUME command → ACK response flow.
    ///
    /// Same pattern as PAUSE test but for RESUME.
    func test_resumeAck() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49006,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send RESUME
        await client.resume()

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received RESUME
        let serverMessages = await delegate.storage.receivedMessages
        XCTAssertTrue(serverMessages.contains { $0.type == .resume },
                      "Server should have received RESUME")

        // Verify client received ACK for RESUME
        let clientMessages = await clientDelegate.storage.receivedMessages
        let acks = clientMessages.filter { $0.type == .ack }
        XCTAssertFalse(acks.isEmpty, "Client should have received ACK")
        XCTAssertEqual(acks.first?.payload.first, AESPMessageType.resume.rawValue,
                       "ACK should reference RESUME")

        await client.disconnect()
        await server.stop()
    }

    /// Test STATUS request → StatusResponse with disk info.
    ///
    /// Uses the requestStatusWithDisks() method which sets up a pending
    /// continuation and waits for the response.
    func test_statusRequestResponse() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49009,
            delegate: delegate
        )

        // Request status (this awaits the response)
        let status = await client.requestStatusWithDisks()

        // Verify the response content
        XCTAssertTrue(status.isRunning, "Status should report running")
        XCTAssertEqual(status.mountedDrives.count, 1, "Should have 1 mounted drive")
        XCTAssertEqual(status.mountedDrives.first?.drive, 1)
        XCTAssertEqual(status.mountedDrives.first?.filename, "GAME.ATR")

        await client.disconnect()
        await server.stop()
    }

}

// =============================================================================
// MARK: - Video Channel End-to-End Tests (Sub-task 5.2)
// =============================================================================

/// End-to-end tests for the AESP video channel.
///
/// These tests verify that video frames broadcast by the server arrive at
/// the client via the frameStream AsyncStream. Port range: 49100-49199.
///
/// Key insight: The client must connect with `connectVideo: true` to receive
/// frames. The frameStream yields Data payloads for each .frameRaw message.
final class AESPVideoChannelE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test that a single frame broadcast by the server is received by the client.
    func test_frameDelivery() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49100,
            connectVideo: true
        )

        // Get the frame stream before broadcasting
        let frameStream = await client.frameStream

        // Broadcast a small test frame
        let testPixels: [UInt8] = Array(repeating: 0xAB, count: 100)
        await server.broadcastFrame(testPixels)

        // Read one frame with timeout
        let frame = await firstElement(from: frameStream, timeout: 2.0)
        XCTAssertNotNil(frame, "Should have received a frame")
        XCTAssertEqual(frame?.count, 100, "Frame should be 100 bytes")
        XCTAssertEqual(Array(frame!), testPixels, "Frame data should match")

        await client.disconnect()
        await server.stop()
    }

    /// Test that a full-size frame (384x240x4 = 368,640 bytes) arrives intact.
    ///
    /// This is the actual frame size used by the Atari 800 XL emulator.
    func test_fullFrameSize() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49103,
            connectVideo: true
        )

        let frameStream = await client.frameStream

        // Create a full-size frame with a recognizable pattern
        let fullSize = AESPConstants.frameSize // 368,640 bytes
        let testPixels: [UInt8] = (0..<fullSize).map { UInt8($0 & 0xFF) }
        await server.broadcastFrame(testPixels)

        let frame = await firstElement(from: frameStream, timeout: 3.0)
        XCTAssertNotNil(frame, "Should have received a full-size frame")
        XCTAssertEqual(frame?.count, fullSize,
                       "Frame should be \(fullSize) bytes (384x240x4)")

        // Verify first and last bytes match
        if let frame = frame {
            XCTAssertEqual(frame[0], 0x00, "First byte should match pattern")
            XCTAssertEqual(frame[255], 0xFF, "Byte 255 should match pattern")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test that multiple sequential frames are all received correctly.
    func test_multipleFrames() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49106,
            connectVideo: true
        )

        let frameStream = await client.frameStream

        // Broadcast 5 frames with distinct patterns
        let frameCount = 5
        for i in 0..<frameCount {
            let pixels: [UInt8] = Array(repeating: UInt8(i * 50), count: 256)
            await server.broadcastFrame(pixels)
        }

        // Collect frames with timeout
        var receivedFrames: [Data] = []
        let deadline = Date().addingTimeInterval(3.0)
        for await frame in frameStream {
            receivedFrames.append(frame)
            if receivedFrames.count >= frameCount || Date() > deadline {
                break
            }
        }

        XCTAssertEqual(receivedFrames.count, frameCount,
                       "Should have received \(frameCount) frames")

        // Verify each frame has the correct fill byte
        for (i, frame) in receivedFrames.enumerated() {
            XCTAssertEqual(frame.count, 256)
            XCTAssertEqual(frame[0], UInt8(i * 50),
                           "Frame \(i) should have fill byte \(i * 50)")
        }

        // Verify frame counter on server
        let frameNumber = await server.currentFrameNumber
        XCTAssertEqual(frameNumber, UInt64(frameCount),
                       "Server frame counter should be \(frameCount)")

        await client.disconnect()
        await server.stop()
    }

    /// Test that a client without video connection receives no frames.
    ///
    /// When connectVideo is false, the client doesn't connect to the video
    /// port, so broadcastFrame has no subscribers and the frameStream is
    /// an empty (immediately-finishing) stream.
    func test_noVideoWithoutConnection() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        // Connect without video
        let (server, client) = try await createServerAndClient(
            controlPort: 49109,
            connectVideo: false
        )

        let frameStream = await client.frameStream

        // Broadcast a frame — no video client should receive it
        await server.broadcastFrame(Array(repeating: 0xFF, count: 100))

        // The stream should yield nothing (it finishes immediately when no
        // video connection was made)
        let frame = await firstElement(from: frameStream, timeout: 0.5)
        XCTAssertNil(frame, "Should not receive frames without video connection")

        await client.disconnect()
        await server.stop()
    }

    /// Helper: reads the first element from an AsyncStream with a timeout.
    ///
    /// Returns nil if no element is received before the timeout expires.
    private func firstElement(from stream: AsyncStream<Data>, timeout: TimeInterval) async -> Data? {
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                for await element in stream {
                    return element
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            // Return whichever finishes first
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

// =============================================================================
// MARK: - Audio Channel End-to-End Tests (Sub-task 5.3)
// =============================================================================

/// End-to-end tests for the AESP audio channel.
///
/// These tests verify that audio samples broadcast by the server arrive at
/// the client via the audioStream AsyncStream. Port range: 49200-49299.
///
/// Key insight: Audio samples are 16-bit signed PCM, mono at 44100 Hz.
/// A typical buffer is 735 samples × 2 bytes = 1470 bytes per frame.
final class AESPAudioChannelE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test that audio samples broadcast by the server are received by the client.
    func test_audioDelivery() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49200,
            connectAudio: true
        )

        let audioStream = await client.audioStream

        // Broadcast audio samples
        let testSamples: [UInt8] = Array(repeating: 0x80, count: 100)
        await server.broadcastAudio(testSamples)

        let audio = await firstElement(from: audioStream, timeout: 2.0)
        XCTAssertNotNil(audio, "Should have received audio samples")
        XCTAssertEqual(audio?.count, 100, "Audio should be 100 bytes")

        await client.disconnect()
        await server.stop()
    }

    /// Test that a typical audio buffer size (1470 bytes = 735 samples × 2) arrives intact.
    func test_audioSampleSize() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49203,
            connectAudio: true
        )

        let audioStream = await client.audioStream

        // Typical audio buffer: 735 samples × 2 bytes = 1470 bytes
        let sampleCount = 735
        let byteCount = sampleCount * 2
        let testSamples: [UInt8] = (0..<byteCount).map { UInt8($0 & 0xFF) }
        await server.broadcastAudio(testSamples)

        let audio = await firstElement(from: audioStream, timeout: 2.0)
        XCTAssertNotNil(audio, "Should have received audio buffer")
        XCTAssertEqual(audio?.count, byteCount,
                       "Audio buffer should be \(byteCount) bytes (\(sampleCount) samples × 2)")

        await client.disconnect()
        await server.stop()
    }

    /// Test that multiple sequential audio buffers are all received.
    func test_multipleAudioBuffers() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49206,
            connectAudio: true
        )

        let audioStream = await client.audioStream

        // Broadcast 5 audio buffers with distinct patterns
        let bufferCount = 5
        for i in 0..<bufferCount {
            let samples: [UInt8] = Array(repeating: UInt8(i * 40), count: 200)
            await server.broadcastAudio(samples)
        }

        // Collect audio buffers with timeout
        var receivedBuffers: [Data] = []
        let deadline = Date().addingTimeInterval(3.0)
        for await buffer in audioStream {
            receivedBuffers.append(buffer)
            if receivedBuffers.count >= bufferCount || Date() > deadline {
                break
            }
        }

        XCTAssertEqual(receivedBuffers.count, bufferCount,
                       "Should have received \(bufferCount) audio buffers")

        // Verify each buffer has the correct fill byte
        for (i, buffer) in receivedBuffers.enumerated() {
            XCTAssertEqual(buffer.count, 200)
            XCTAssertEqual(buffer[0], UInt8(i * 40),
                           "Buffer \(i) should have fill byte \(i * 40)")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test that a client without audio connection receives no audio.
    func test_noAudioWithoutConnection() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        // Connect without audio
        let (server, client) = try await createServerAndClient(
            controlPort: 49209,
            connectAudio: false
        )

        let audioStream = await client.audioStream

        // Broadcast audio — no audio client should receive it
        await server.broadcastAudio(Array(repeating: 0x80, count: 100))

        // The stream should yield nothing
        let audio = await firstElement(from: audioStream, timeout: 0.5)
        XCTAssertNil(audio, "Should not receive audio without audio connection")

        await client.disconnect()
        await server.stop()
    }

    /// Test that 16-bit PCM data integrity is preserved through the protocol.
    ///
    /// Creates a known PCM pattern (a sawtooth wave) and verifies it arrives
    /// byte-for-byte identical on the client side.
    func test_sixteenBitPCMIntegrity() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, client) = try await createServerAndClient(
            controlPort: 49212,
            connectAudio: true
        )

        let audioStream = await client.audioStream

        // Create a sawtooth pattern of 16-bit samples (little-endian, as PCM):
        // 0x0000, 0x1000, 0x2000, ..., 0xF000
        var pcmData = Data(capacity: 32)
        for i: UInt16 in stride(from: 0, to: 0xFFFF, by: 0x1000) {
            pcmData.append(UInt8(i & 0xFF))        // Low byte
            pcmData.append(UInt8((i >> 8) & 0xFF)) // High byte
        }

        await server.broadcastAudio(Array(pcmData))

        let received = await firstElement(from: audioStream, timeout: 2.0)
        XCTAssertNotNil(received, "Should have received PCM data")
        XCTAssertEqual(received, pcmData, "PCM data should match byte-for-byte")

        await client.disconnect()
        await server.stop()
    }

    /// Helper: reads the first element from an AsyncStream with a timeout.
    private func firstElement(from stream: AsyncStream<Data>, timeout: TimeInterval) async -> Data? {
        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                for await element in stream {
                    return element
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

// =============================================================================
// MARK: - Error Handling End-to-End Tests (Sub-task 5.4)
// =============================================================================

/// End-to-end tests for error handling in the AESP protocol.
///
/// These tests send malformed data via raw TCP connections and verify
/// the server recovers gracefully. Port range: 49300-49399.
///
/// Key design decisions:
/// - Uses raw NWConnection (not AESPClient) because the client validates
///   messages locally before sending — malformed data can't be sent through it.
/// - Server doesn't send ERROR messages for malformed data — it logs the error,
///   clears the buffer, and continues. Tests verify recovery by sending valid
///   PING after bad data and checking for PONG.
final class AESPErrorHandlingE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test server stays operational after receiving invalid magic bytes.
    ///
    /// Sends bytes with wrong magic (0xBEEF instead of 0xAE50) on one
    /// connection. The server's messageSize() returns nil for invalid magic
    /// (it can't recover on that connection since it never enters decode()),
    /// but the server stays up and accepts new connections.
    func test_invalidMagic_serverStaysUp() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        try await verifyServerStaysUpAfterBadData(
            port: 49300,
            // Invalid magic: 0xBEEF instead of 0xAE50
            badData: Data([0xBE, 0xEF, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    /// Test server recovers from invalid version byte.
    ///
    /// Sends a message with version 0x02 (unsupported). Since the magic is
    /// valid and length is 0, messageSize() returns 8, decode() throws
    /// unsupportedVersion, and the server clears the buffer. A subsequent
    /// PING on the same connection gets a PONG response.
    func test_invalidVersion_recovers() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        try await verifySameConnectionRecovery(
            port: 49303,
            // Valid magic, invalid version 0x02
            badData: Data([0xAE, 0x50, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00])
        )
    }

    /// Test server recovers from unknown message type.
    ///
    /// Sends a message with type 0xFE (not defined). Since magic is valid
    /// and length is 0, messageSize() returns 8, decode() throws
    /// unknownMessageType, and the server clears the buffer.
    func test_unknownMessageType_recovers() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        try await verifySameConnectionRecovery(
            port: 49306,
            // Valid magic and version, unknown type 0xFE
            badData: Data([0xAE, 0x50, 0x01, 0xFE, 0x00, 0x00, 0x00, 0x00])
        )
    }

    /// Test server stays operational after receiving oversized payload header.
    ///
    /// Sends a header claiming a 32MB payload. The server's messageSize()
    /// returns nil (buffer < total claimed size) so it waits for more data
    /// on that connection forever. But the server itself remains healthy
    /// and accepts new connections.
    func test_oversizedPayload_serverStaysUp() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        try await verifyServerStaysUpAfterBadData(
            port: 49309,
            // Valid magic/version/type, but payload size > 16MB (0x02000000 = 32MB)
            badData: Data([0xAE, 0x50, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00])
        )
    }

    /// Test that the server can send an ERROR message and the client receives it.
    ///
    /// Unlike the malformed-data tests above, this tests the ERROR message type
    /// itself — the delegate sends an ERROR message to the client, and the
    /// client delegate receives it via didEncounterError.
    func test_serverSendsErrorMessage() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let port = 49312
        let serverConfig = AESPServerConfiguration(
            controlPort: port, videoPort: port + 1, audioPort: port + 2
        )
        let server = AESPServer(configuration: serverConfig)

        // Use a custom delegate that responds to any message with an ERROR
        let errorDelegate = ErrorSendingDelegate()
        await server.setDelegate(errorDelegate)

        try await server.start()
        try await Task.sleep(nanoseconds: serverStartDelay)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: port, videoPort: port + 1, audioPort: port + 2
        )
        let client = AESPClient(configuration: clientConfig)
        let clientDelegate = MockClientDelegate()
        await client.setDelegate(clientDelegate)

        try await client.connect(connectVideo: false, connectAudio: false)
        try await Task.sleep(nanoseconds: serverStartDelay)

        // Send a PAUSE to trigger the delegate's error response
        await client.pause()

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify client received the error
        let errors = await clientDelegate.storage.errors
        XCTAssertFalse(errors.isEmpty, "Client should have received an error")

        if let error = errors.first as? AESPError,
           case .serverError(let code, let message) = error {
            XCTAssertEqual(code, 0x42)
            XCTAssertEqual(message, "Test error from server")
        } else {
            XCTFail("Error should be AESPError.serverError")
        }

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - Error Test Helpers
    // =========================================================================

    /// Helper to create a raw TCP connection to a port and wait until ready.
    private func createRawConnection(port: Int) async throws -> NWConnection {
        let endpoint = NWEndpoint.hostPort(
            host: "localhost",
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        let connection = NWConnection(to: endpoint, using: .tcp)

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume(returning: true)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        return connection
    }

    /// Verifies same-connection recovery after malformed data.
    ///
    /// For errors where messageSize() returns non-nil (invalid version,
    /// unknown type), the server enters decode(), which throws, and the
    /// buffer is cleared. A subsequent PING on the same connection works.
    private func verifySameConnectionRecovery(port: Int, badData: Data) async throws {
        let serverConfig = AESPServerConfiguration(
            controlPort: port, videoPort: port + 1, audioPort: port + 2
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: serverStartDelay)

        let connection = try await createRawConnection(port: port)
        try await Task.sleep(nanoseconds: serverStartDelay)

        // Send malformed data
        connection.send(content: badData, completion: .contentProcessed { _ in })
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Send valid PING — buffer should have been cleared by decode() error
        let pingData = AESPMessage.ping().encode()
        connection.send(content: pingData, completion: .contentProcessed { error in
            XCTAssertNil(error, "Sending PING after bad data should succeed")
        })

        // Receive PONG
        let responseData: Data? = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 8, maximumLength: 256) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }

        if let data = responseData, !data.isEmpty {
            let (response, _) = try AESPMessage.decode(from: data)
            XCTAssertEqual(response.type, .pong,
                           "Server should respond with PONG after recovery")
        } else {
            XCTFail("Should have received PONG response after recovery")
        }

        connection.cancel()
        await server.stop()
    }

    /// Verifies the server stays operational after bad data on one connection.
    ///
    /// For errors where messageSize() returns nil (invalid magic, oversized
    /// payload), the server can't recover on that connection because the
    /// while loop never enters decode(). But the server itself stays up
    /// and accepts new connections fine.
    private func verifyServerStaysUpAfterBadData(port: Int, badData: Data) async throws {
        let serverConfig = AESPServerConfiguration(
            controlPort: port, videoPort: port + 1, audioPort: port + 2
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: serverStartDelay)

        // First connection: send bad data
        let badConnection = try await createRawConnection(port: port)
        try await Task.sleep(nanoseconds: serverStartDelay)

        badConnection.send(content: badData, completion: .contentProcessed { _ in })
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server is still running
        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should still be running after bad data")

        // Second connection: verify PING→PONG works on a fresh connection
        let goodConnection = try await createRawConnection(port: port)
        try await Task.sleep(nanoseconds: serverStartDelay)

        let pingData = AESPMessage.ping().encode()
        goodConnection.send(content: pingData, completion: .contentProcessed { error in
            XCTAssertNil(error, "PING on new connection should succeed")
        })

        let responseData: Data? = try await withCheckedThrowingContinuation { continuation in
            goodConnection.receive(minimumIncompleteLength: 8, maximumLength: 256) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }

        if let data = responseData, !data.isEmpty {
            let (response, _) = try AESPMessage.decode(from: data)
            XCTAssertEqual(response.type, .pong,
                           "Server should respond with PONG on new connection")
        } else {
            XCTFail("Should have received PONG on new connection")
        }

        badConnection.cancel()
        goodConnection.cancel()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Message Type End-to-End Tests (attic-33a)
// =============================================================================

/// End-to-end tests for AESP message types that previously only had
/// encode/decode unit tests: INFO, BOOT_FILE, RESET, PADDLE, FRAME_CONFIG,
/// AUDIO_CONFIG.
///
/// These tests verify that each message type travels correctly through real
/// TCP connections between AESPServer and AESPClient. Port range: 49400-49499.
///
/// Test strategies by message type:
/// - INFO, BOOT_FILE, RESET: Client sends request → delegate responds → client
///   receives response (same pattern as PAUSE/RESUME/STATUS tests).
/// - PADDLE: Client sends input → delegate records it → verify payload integrity.
/// - FRAME_CONFIG, AUDIO_CONFIG: Server sends config to client → client delegate
///   receives it → verify field values parsed correctly.
final class AESPMessageTypeE2ETests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    // =========================================================================
    // MARK: - INFO Tests
    // =========================================================================

    /// Test INFO request → response flow.
    ///
    /// Client sends an INFO request (empty payload). The server delegate
    /// responds with a JSON string containing emulator capabilities. The
    /// client delegate receives the INFO response and can parse the JSON.
    func test_infoRequestResponse() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49400,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send INFO request
        await client.sendMessage(.info())

        // Wait for round-trip
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received INFO
        let serverMessages = await delegate.storage.receivedMessages
        XCTAssertTrue(serverMessages.contains { $0.type == .info },
                      "Server should have received INFO request")

        // Verify client received INFO response with JSON payload
        let clientMessages = await clientDelegate.storage.receivedMessages
        let infoMessages = clientMessages.filter { $0.type == .info }
        XCTAssertFalse(infoMessages.isEmpty, "Client should have received INFO response")

        if let infoMsg = infoMessages.first {
            let json = infoMsg.parseInfoPayload()
            XCTAssertNotNil(json, "INFO response should contain JSON")
            XCTAssertTrue(json!.contains("\"version\""), "JSON should contain version field")
            XCTAssertTrue(json!.contains("\"Attic\""), "JSON should contain product name")
            XCTAssertTrue(json!.contains("\"macOS\""), "JSON should contain platform")
        }

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - BOOT_FILE Tests
    // =========================================================================

    /// Test BOOT_FILE with a supported file type (success path).
    ///
    /// Client sends a BOOT_FILE request with an .atr file path. The server
    /// delegate validates the extension and responds with success=true.
    func test_bootFileSuccess() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49403,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send BOOT_FILE request with a .atr path
        await client.bootFile(filePath: "/path/to/game.atr")

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received BOOT_FILE with correct path
        let serverMessages = await delegate.storage.receivedMessages
        let bootMessages = serverMessages.filter { $0.type == .bootFile }
        XCTAssertFalse(bootMessages.isEmpty, "Server should have received BOOT_FILE")

        if let bootMsg = bootMessages.first {
            let path = bootMsg.parseBootFileRequest()
            XCTAssertEqual(path, "/path/to/game.atr", "File path should match")
        }

        // Verify client received success response
        let clientMessages = await clientDelegate.storage.receivedMessages
        let responseMessages = clientMessages.filter { $0.type == .bootFile }
        XCTAssertFalse(responseMessages.isEmpty, "Client should have received BOOT_FILE response")

        if let response = responseMessages.first {
            let parsed = response.parseBootFileResponse()
            XCTAssertNotNil(parsed, "Response should be parseable")
            XCTAssertTrue(parsed!.success, "Boot should have succeeded for .atr file")
            XCTAssertEqual(parsed!.message, "Disk image loaded")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test BOOT_FILE with an unsupported file type (failure path).
    ///
    /// Client sends a BOOT_FILE request with an unsupported extension. The
    /// server delegate responds with success=false and an error message.
    func test_bootFileFailure() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49406,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send BOOT_FILE with unsupported extension
        await client.bootFile(filePath: "/path/to/file.xyz")

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify client received failure response
        let clientMessages = await clientDelegate.storage.receivedMessages
        let responseMessages = clientMessages.filter { $0.type == .bootFile }
        XCTAssertFalse(responseMessages.isEmpty, "Client should have received BOOT_FILE response")

        if let response = responseMessages.first {
            let parsed = response.parseBootFileResponse()
            XCTAssertNotNil(parsed, "Response should be parseable")
            XCTAssertFalse(parsed!.success, "Boot should have failed for unsupported file")
            XCTAssertEqual(parsed!.message, "Unsupported file type")
        }

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - RESET Tests
    // =========================================================================

    /// Test cold reset request → status response.
    ///
    /// Client sends RESET with cold=true. The server delegate responds
    /// with a STATUS message. Verifies both the request payload (cold flag)
    /// and the response are correct.
    func test_resetCold() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49409,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send cold reset
        await client.reset(cold: true)

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received RESET with cold flag
        let serverMessages = await delegate.storage.receivedMessages
        let resetMessages = serverMessages.filter { $0.type == .reset }
        XCTAssertFalse(resetMessages.isEmpty, "Server should have received RESET")

        if let resetMsg = resetMessages.first {
            XCTAssertEqual(resetMsg.payload.count, 1, "RESET payload should be 1 byte")
            XCTAssertEqual(resetMsg.payload[0], 0x01, "Cold reset flag should be 0x01")
        }

        // Verify client received STATUS response
        let clientMessages = await clientDelegate.storage.receivedMessages
        let statusMessages = clientMessages.filter { $0.type == .status }
        XCTAssertFalse(statusMessages.isEmpty, "Client should have received STATUS after reset")

        if let statusMsg = statusMessages.first {
            let status = statusMsg.parseStatusWithDisks()
            XCTAssertNotNil(status, "Status should be parseable")
            XCTAssertTrue(status!.isRunning, "Emulator should be running after reset")
            XCTAssertTrue(status!.mountedDrives.isEmpty,
                         "No drives should be mounted after cold reset")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test warm reset request → status response.
    ///
    /// Same as cold reset but with cold=false. Verifies the warm reset
    /// flag (0x00) is correctly transmitted.
    func test_resetWarm() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49412,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Send warm reset
        await client.reset(cold: false)

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received RESET with warm flag
        let serverMessages = await delegate.storage.receivedMessages
        let resetMessages = serverMessages.filter { $0.type == .reset }
        XCTAssertFalse(resetMessages.isEmpty, "Server should have received RESET")

        if let resetMsg = resetMessages.first {
            XCTAssertEqual(resetMsg.payload[0], 0x00, "Warm reset flag should be 0x00")
        }

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - PADDLE Tests
    // =========================================================================

    /// Test paddle input message delivery.
    ///
    /// Client sends a PADDLE message with a specific paddle number and
    /// position. Verifies the server receives the message with the correct
    /// payload fields intact after traversing the network.
    func test_paddleInput() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49415,
            delegate: delegate
        )

        // Send paddle 2 at position 114 (mid-range of 0-228)
        await client.sendMessage(.paddle(number: 2, position: 114))

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify server received PADDLE with correct values
        let serverMessages = await delegate.storage.receivedMessages
        let paddleMessages = serverMessages.filter { $0.type == .paddle }
        XCTAssertFalse(paddleMessages.isEmpty, "Server should have received PADDLE")

        if let paddleMsg = paddleMessages.first {
            let parsed = paddleMsg.parsePaddlePayload()
            XCTAssertNotNil(parsed, "PADDLE payload should be parseable")
            XCTAssertEqual(parsed!.number, 2, "Paddle number should be 2")
            XCTAssertEqual(parsed!.position, 114, "Paddle position should be 114")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test paddle input at boundary values.
    ///
    /// Verifies that the minimum (0) and maximum (228) paddle positions
    /// are transmitted correctly without clipping or overflow.
    func test_paddleBoundaryValues() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49418,
            delegate: delegate
        )

        // Send paddle at minimum position
        await client.sendMessage(.paddle(number: 0, position: 0))
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Send paddle at maximum position
        await client.sendMessage(.paddle(number: 3, position: 228))
        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify both messages received
        let serverMessages = await delegate.storage.receivedMessages
        let paddleMessages = serverMessages.filter { $0.type == .paddle }
        XCTAssertEqual(paddleMessages.count, 2, "Server should have received 2 PADDLE messages")

        // Verify min values
        let minPaddle = paddleMessages[0].parsePaddlePayload()
        XCTAssertEqual(minPaddle?.number, 0, "Min paddle number should be 0")
        XCTAssertEqual(minPaddle?.position, 0, "Min paddle position should be 0")

        // Verify max values
        let maxPaddle = paddleMessages[1].parsePaddlePayload()
        XCTAssertEqual(maxPaddle?.number, 3, "Max paddle number should be 3")
        XCTAssertEqual(maxPaddle?.position, 228, "Max paddle position should be 228")

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - FRAME_CONFIG Tests
    // =========================================================================

    /// Test FRAME_CONFIG delivery from server to client.
    ///
    /// The server sends a FRAME_CONFIG message with the standard Atari 800 XL
    /// video parameters. Verifies the client receives and can parse all fields
    /// (width, height, bytes per pixel, FPS) correctly.
    func test_frameConfigDelivery() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49421,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Get the connected client ID from the delegate's storage
        let connectedClients = await delegate.storage.connectedClients
        guard let (clientId, _) = connectedClients.first else {
            XCTFail("No client connected to server")
            return
        }

        // Server sends FRAME_CONFIG with Atari 800 XL video params
        let configMsg = AESPMessage.frameConfig(
            width: 384,
            height: 240,
            bytesPerPixel: 4,
            fps: 60
        )
        await server.sendMessage(configMsg, to: clientId, channel: .control)

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify client received FRAME_CONFIG
        let clientMessages = await clientDelegate.storage.receivedMessages
        let configMessages = clientMessages.filter { $0.type == .frameConfig }
        XCTAssertFalse(configMessages.isEmpty, "Client should have received FRAME_CONFIG")

        if let received = configMessages.first {
            let config = received.parseFrameConfigPayload()
            XCTAssertNotNil(config, "FRAME_CONFIG should be parseable")
            XCTAssertEqual(config!.width, 384, "Width should be 384")
            XCTAssertEqual(config!.height, 240, "Height should be 240")
            XCTAssertEqual(config!.bytesPerPixel, 4, "Bytes per pixel should be 4 (BGRA)")
            XCTAssertEqual(config!.fps, 60, "FPS should be 60")
        }

        await client.disconnect()
        await server.stop()
    }

    // =========================================================================
    // MARK: - AUDIO_CONFIG Tests
    // =========================================================================

    /// Test AUDIO_CONFIG delivery from server to client.
    ///
    /// The server sends an AUDIO_CONFIG message with the standard Atari 800 XL
    /// audio parameters (44100 Hz, 16-bit, mono). Verifies the client receives
    /// and can parse all fields correctly, including the 4-byte big-endian
    /// sample rate.
    func test_audioConfigDelivery() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = RespondingMockDelegate()
        let clientDelegate = MockClientDelegate()

        let (server, client) = try await createServerAndClient(
            controlPort: 49424,
            delegate: delegate,
            clientDelegate: clientDelegate
        )

        // Get the connected client ID
        let connectedClients = await delegate.storage.connectedClients
        guard let (clientId, _) = connectedClients.first else {
            XCTFail("No client connected to server")
            return
        }

        // Server sends AUDIO_CONFIG with standard Atari audio params
        let configMsg = AESPMessage.audioConfig(
            sampleRate: 44100,
            bitsPerSample: 16,
            channels: 1
        )
        await server.sendMessage(configMsg, to: clientId, channel: .control)

        try await Task.sleep(nanoseconds: messagePropagationDelay)

        // Verify client received AUDIO_CONFIG
        let clientMessages = await clientDelegate.storage.receivedMessages
        let configMessages = clientMessages.filter { $0.type == .audioConfig }
        XCTAssertFalse(configMessages.isEmpty, "Client should have received AUDIO_CONFIG")

        if let received = configMessages.first {
            let config = received.parseAudioConfigPayload()
            XCTAssertNotNil(config, "AUDIO_CONFIG should be parseable")
            XCTAssertEqual(config!.sampleRate, 44100, "Sample rate should be 44100 Hz")
            XCTAssertEqual(config!.bitsPerSample, 16, "Bits per sample should be 16")
            XCTAssertEqual(config!.channels, 1, "Channels should be 1 (mono)")
        }

        await client.disconnect()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Error-Sending Delegate
// =============================================================================

/// A server delegate that responds to any message with an ERROR.
///
/// Used by test_serverSendsErrorMessage to verify the client correctly
/// receives and parses ERROR messages from the server.
private final class ErrorSendingDelegate: AESPServerDelegate, @unchecked Sendable {

    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        // Respond with an ERROR message
        let errorMsg = AESPMessage.error(code: 0x42, message: "Test error from server")
        await server.sendMessage(errorMsg, to: clientId, channel: .control)
    }

    func server(_ server: AESPServer, clientDidConnect clientId: UUID, channel: AESPChannel) async {}
    func server(_ server: AESPServer, clientDidDisconnect clientId: UUID, channel: AESPChannel) async {}
}
