// =============================================================================
// AESPMultiClientTests.swift - Multi-Client Integration Tests for AESP Protocol
// =============================================================================
//
// This file contains integration tests that verify multiple clients can
// simultaneously connect to a single AESP server and interact correctly.
//
// Test Coverage:
// - 14.1 Multiple GUI Clients: Two clients with video+audio both receive
//   frames and audio, input from either client works
// - 14.2 CLI and GUI Together: A control-only (CLI) client and a full
//   (GUI) client coexist, CLI commands affect server state visible to GUI,
//   both can pause/resume independently
//
// Port Allocation (50000-50199, avoids conflicts with existing tests):
// - Multiple GUI client tests: 50000-50099
// - CLI + GUI together tests: 50100-50199
//
// =============================================================================

import XCTest
@testable import AtticProtocol
#if canImport(Network)
import Network
#endif

// =============================================================================
// MARK: - Multi-Client Server Delegate
// =============================================================================

/// Actor-based storage for the multi-client server delegate.
///
/// Tracks all messages received from clients along with the client ID that
/// sent each message, so tests can verify which client's commands reached
/// the server.
private actor MultiClientDelegateStorage {
    /// All messages received, tagged with the sending client's UUID.
    var receivedMessages: [(clientId: UUID, message: AESPMessage)] = []

    /// Client connection events: (clientId, channel).
    var connectedClients: [(UUID, AESPChannel)] = []

    /// Client disconnection events: (clientId, channel).
    var disconnectedClients: [(UUID, AESPChannel)] = []

    func addMessage(_ message: AESPMessage, from clientId: UUID) {
        receivedMessages.append((clientId: clientId, message: message))
    }

    func addConnectedClient(_ clientId: UUID, channel: AESPChannel) {
        connectedClients.append((clientId, channel))
    }

    func addDisconnectedClient(_ clientId: UUID, channel: AESPChannel) {
        disconnectedClients.append((clientId, channel))
    }

    /// Returns all messages of a specific type.
    func messages(ofType type: AESPMessageType) -> [(clientId: UUID, message: AESPMessage)] {
        receivedMessages.filter { $0.message.type == type }
    }
}

/// A server delegate that responds to client messages and tracks which client
/// sent each one.
///
/// Responds identically to the RespondingMockDelegate in AESPEndToEndTests:
/// - PAUSE → ACK(PAUSE)
/// - RESUME → ACK(RESUME)
/// - STATUS → StatusResponse
/// - Other input messages are recorded but not responded to
///
/// The key difference: this delegate stores the client UUID alongside each
/// message, enabling tests to verify multi-client input routing.
private final class MultiClientDelegate: AESPServerDelegate, @unchecked Sendable {
    let storage = MultiClientDelegateStorage()

    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        await storage.addMessage(message, from: clientId)

        switch message.type {
        case .pause:
            await server.sendMessage(.ack(for: .pause), to: clientId, channel: .control)

        case .resume:
            await server.sendMessage(.ack(for: .resume), to: clientId, channel: .control)

        case .status:
            let response = AESPMessage.statusResponse(
                isRunning: true,
                mountedDrives: []
            )
            await server.sendMessage(response, to: clientId, channel: .control)

        case .reset:
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
// MARK: - Test Timing Constants
// =============================================================================

/// Standard delay for server startup (100ms).
/// Network listeners need time to initialize before accepting connections.
private let mcServerStartDelay: UInt64 = 100_000_000

/// Standard delay for message propagation through TCP (200ms).
/// Accounts for TCP delivery, buffering, and async processing.
private let mcMessagePropagationDelay: UInt64 = 200_000_000

// =============================================================================
// MARK: - Stream Collection Helpers
// =============================================================================

/// Reads the first element from an AsyncStream with a timeout.
///
/// Uses a task group with a racing timeout task. If no element arrives
/// before the deadline, returns nil. Defined as a free function (not an
/// instance method) to avoid Swift strict concurrency "sending self" errors
/// when used with `async let`.
private func mcFirstElement(from stream: AsyncStream<Data>, timeout: TimeInterval) async -> Data? {
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

/// Collects up to `count` elements from an AsyncStream with a timeout.
///
/// Returns the collected elements when either `count` is reached or the
/// timeout expires, whichever comes first. Free function for the same
/// concurrency-safety reason as `mcFirstElement`.
private func mcCollectElements(from stream: AsyncStream<Data>, count: Int, timeout: TimeInterval) async -> [Data] {
    return await withTaskGroup(of: [Data].self) { group in
        group.addTask {
            var collected: [Data] = []
            for await element in stream {
                collected.append(element)
                if collected.count >= count { break }
            }
            return collected
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return []
        }
        let result = await group.next() ?? []
        group.cancelAll()
        return result
    }
}

// =============================================================================
// MARK: - Test Helpers
// =============================================================================

/// Creates a server and multiple clients with the given port configuration.
///
/// This helper handles the boilerplate of creating matching server/client
/// configurations, starting the server, and connecting all clients.
///
/// - Parameters:
///   - controlPort: Base port for control channel (video = +1, audio = +2).
///   - clientCount: Number of clients to create and connect.
///   - connectVideo: Whether clients should connect to the video channel.
///   - connectAudio: Whether clients should connect to the audio channel.
///   - delegate: The server delegate to use (optional).
/// - Returns: Tuple of (server, [clients]) ready for testing.
private func createServerAndClients(
    controlPort: Int,
    clientCount: Int,
    connectVideo: Bool = false,
    connectAudio: Bool = false,
    delegate: MultiClientDelegate? = nil
) async throws -> (AESPServer, [AESPClient]) {
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
    try await Task.sleep(nanoseconds: mcServerStartDelay)

    let clientConfig = AESPClientConfiguration(
        host: "localhost",
        controlPort: controlPort,
        videoPort: controlPort + 1,
        audioPort: controlPort + 2
    )

    var clients: [AESPClient] = []
    for _ in 0..<clientCount {
        let client = AESPClient(configuration: clientConfig)
        try await client.connect(connectVideo: connectVideo, connectAudio: connectAudio)
        clients.append(client)
    }

    // Wait for all connections to stabilize
    try await Task.sleep(nanoseconds: mcServerStartDelay)

    return (server, clients)
}

/// Extension to set delegate on AESPServer (convenience for tests).
private extension AESPServer {
    func setDelegate(_ delegate: AESPServerDelegate) {
        self.delegate = delegate
    }
}

// =============================================================================
// MARK: - 14.1 Multiple GUI Clients Tests
// =============================================================================

/// Tests for multiple GUI clients connecting to the same server simultaneously.
///
/// A "GUI client" connects to all three channels (control, video, audio).
/// These tests verify that when two such clients are connected:
/// - Both receive video frames from the server
/// - Both receive audio samples from the server
/// - Input (keyboard, joystick) from either client reaches the server
/// - Client connection/disconnection doesn't affect the other client
///
/// Port range: 50000-50099 (3 ports per test: control, video, audio).
final class AESPMultipleGUIClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    // -------------------------------------------------------------------------
    // MARK: Connection Tests
    // -------------------------------------------------------------------------

    /// Test that two clients can connect simultaneously to all three channels.
    ///
    /// Verifies the server's client count reflects both connections on each
    /// channel (control, video, audio).
    func test_twoClientsConnect() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50000,
            clientCount: 2,
            connectVideo: true,
            connectAudio: true
        )

        // Verify both clients report connected
        for (i, client) in clients.enumerated() {
            let isConnected = await client.isConnected
            XCTAssertTrue(isConnected, "Client \(i) should be connected")
        }

        // Verify server sees clients on all channels
        let counts = await server.clientCounts
        XCTAssertGreaterThanOrEqual(counts.control, 2,
            "Server should have at least 2 control clients")
        XCTAssertGreaterThanOrEqual(counts.video, 2,
            "Server should have at least 2 video clients")
        XCTAssertGreaterThanOrEqual(counts.audio, 2,
            "Server should have at least 2 audio clients")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that disconnecting one client doesn't affect the other.
    ///
    /// After client 1 disconnects, client 2 should still be connected and
    /// able to receive frames.
    func test_oneClientDisconnectsOtherSurvives() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50003,
            clientCount: 2,
            connectVideo: true,
            connectAudio: false
        )

        // Disconnect client 0
        await clients[0].disconnect()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Client 1 should still be connected
        let isConnected = await clients[1].isConnected
        XCTAssertTrue(isConnected, "Client 1 should still be connected after client 0 disconnects")

        // Client 1 should still receive frames
        let frameStream = await clients[1].frameStream
        let testPixels: [UInt8] = Array(repeating: 0xCD, count: 100)
        await server.broadcastFrame(testPixels)

        let frame = await mcFirstElement(from: frameStream, timeout: 2.0)
        XCTAssertNotNil(frame, "Client 1 should receive frames after client 0 disconnects")
        XCTAssertEqual(frame?.count, 100)

        await clients[1].disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: Video Broadcast Tests
    // -------------------------------------------------------------------------

    /// Test that both clients receive the same video frame.
    ///
    /// The server broadcasts a single frame and both clients should receive
    /// identical data through their independent frame streams.
    func test_bothClientsReceiveVideoFrame() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50006,
            clientCount: 2,
            connectVideo: true
        )

        // Get frame streams before broadcasting
        let stream1 = await clients[0].frameStream
        let stream2 = await clients[1].frameStream

        // Broadcast a test frame
        let testPixels: [UInt8] = Array(repeating: 0xAB, count: 200)
        await server.broadcastFrame(testPixels)

        // Both clients should receive the frame
        async let frame1 = mcFirstElement(from: stream1, timeout: 2.0)
        async let frame2 = mcFirstElement(from: stream2, timeout: 2.0)

        let (f1, f2) = await (frame1, frame2)

        XCTAssertNotNil(f1, "Client 1 should receive the frame")
        XCTAssertNotNil(f2, "Client 2 should receive the frame")
        XCTAssertEqual(f1?.count, 200, "Client 1 frame should be 200 bytes")
        XCTAssertEqual(f2?.count, 200, "Client 2 frame should be 200 bytes")
        XCTAssertEqual(f1, f2, "Both clients should receive identical frame data")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that both clients receive a full-size video frame (336x240x4).
    ///
    /// Full-size frames are 322,560 bytes. This verifies the server can handle
    /// broadcasting large payloads to multiple subscribers without corruption.
    func test_bothClientsReceiveFullSizeFrame() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50009,
            clientCount: 2,
            connectVideo: true
        )

        let stream1 = await clients[0].frameStream
        let stream2 = await clients[1].frameStream

        // Create a full-size frame with a recognizable pattern
        let fullSize = AESPConstants.frameSize
        let testPixels: [UInt8] = (0..<fullSize).map { UInt8($0 & 0xFF) }
        await server.broadcastFrame(testPixels)

        async let frame1 = mcFirstElement(from: stream1, timeout: 3.0)
        async let frame2 = mcFirstElement(from: stream2, timeout: 3.0)

        let (f1, f2) = await (frame1, frame2)

        XCTAssertNotNil(f1, "Client 1 should receive full-size frame")
        XCTAssertNotNil(f2, "Client 2 should receive full-size frame")
        XCTAssertEqual(f1?.count, fullSize,
                       "Client 1 frame should be \(fullSize) bytes")
        XCTAssertEqual(f2?.count, fullSize,
                       "Client 2 frame should be \(fullSize) bytes")

        // Spot-check pattern integrity in both frames
        if let f1 = f1, let f2 = f2 {
            XCTAssertEqual(f1[0], 0x00)
            XCTAssertEqual(f1[255], 0xFF)
            XCTAssertEqual(f2[0], 0x00)
            XCTAssertEqual(f2[255], 0xFF)
        }

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that both clients receive multiple sequential frames.
    ///
    /// Broadcasts 5 frames with distinct patterns and verifies both clients
    /// receive all of them in order.
    func test_bothClientsReceiveMultipleFrames() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50012,
            clientCount: 2,
            connectVideo: true
        )

        let stream1 = await clients[0].frameStream
        let stream2 = await clients[1].frameStream

        // Broadcast 5 frames with distinct fill bytes
        let frameCount = 5
        for i in 0..<frameCount {
            let pixels: [UInt8] = Array(repeating: UInt8(i * 50), count: 256)
            await server.broadcastFrame(pixels)
        }

        // Collect frames from both clients concurrently
        async let frames1 = mcCollectElements(from: stream1, count: frameCount, timeout: 3.0)
        async let frames2 = mcCollectElements(from: stream2, count: frameCount, timeout: 3.0)

        let (received1, received2) = await (frames1, frames2)

        XCTAssertEqual(received1.count, frameCount,
                       "Client 1 should receive \(frameCount) frames")
        XCTAssertEqual(received2.count, frameCount,
                       "Client 2 should receive \(frameCount) frames")

        // Verify each frame has the correct fill byte on both clients
        for i in 0..<min(received1.count, frameCount) {
            XCTAssertEqual(received1[i][0], UInt8(i * 50),
                           "Client 1, frame \(i) should have fill byte \(i * 50)")
        }
        for i in 0..<min(received2.count, frameCount) {
            XCTAssertEqual(received2[i][0], UInt8(i * 50),
                           "Client 2, frame \(i) should have fill byte \(i * 50)")
        }

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: Audio Broadcast Tests
    // -------------------------------------------------------------------------

    /// Test that both clients receive the same audio samples.
    func test_bothClientsReceiveAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50015,
            clientCount: 2,
            connectAudio: true
        )

        let stream1 = await clients[0].audioStream
        let stream2 = await clients[1].audioStream

        // Broadcast audio samples (typical buffer: 735 samples × 2 bytes)
        let testSamples: [UInt8] = (0..<1470).map { UInt8($0 & 0xFF) }
        await server.broadcastAudio(testSamples)

        async let audio1 = mcFirstElement(from: stream1, timeout: 2.0)
        async let audio2 = mcFirstElement(from: stream2, timeout: 2.0)

        let (a1, a2) = await (audio1, audio2)

        XCTAssertNotNil(a1, "Client 1 should receive audio")
        XCTAssertNotNil(a2, "Client 2 should receive audio")
        XCTAssertEqual(a1?.count, 1470, "Client 1 audio should be 1470 bytes")
        XCTAssertEqual(a2?.count, 1470, "Client 2 audio should be 1470 bytes")
        XCTAssertEqual(a1, a2, "Both clients should receive identical audio data")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that both clients receive multiple sequential audio buffers.
    func test_bothClientsReceiveMultipleAudioBuffers() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50018,
            clientCount: 2,
            connectAudio: true
        )

        let stream1 = await clients[0].audioStream
        let stream2 = await clients[1].audioStream

        // Broadcast 5 audio buffers with distinct patterns
        let bufferCount = 5
        for i in 0..<bufferCount {
            let samples: [UInt8] = Array(repeating: UInt8(i * 40), count: 200)
            await server.broadcastAudio(samples)
        }

        async let buffers1 = mcCollectElements(from: stream1, count: bufferCount, timeout: 3.0)
        async let buffers2 = mcCollectElements(from: stream2, count: bufferCount, timeout: 3.0)

        let (received1, received2) = await (buffers1, buffers2)

        XCTAssertEqual(received1.count, bufferCount,
                       "Client 1 should receive \(bufferCount) audio buffers")
        XCTAssertEqual(received2.count, bufferCount,
                       "Client 2 should receive \(bufferCount) audio buffers")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that both clients receive video and audio simultaneously.
    ///
    /// Broadcasts interleaved video frames and audio buffers to verify both
    /// channels work independently for both clients at the same time.
    func test_bothClientsReceiveVideoAndAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let (server, clients) = try await createServerAndClients(
            controlPort: 50021,
            clientCount: 2,
            connectVideo: true,
            connectAudio: true
        )

        let videoStream1 = await clients[0].frameStream
        let audioStream1 = await clients[0].audioStream
        let videoStream2 = await clients[1].frameStream
        let audioStream2 = await clients[1].audioStream

        // Broadcast video and audio in sequence (simulating a real frame cycle)
        let videoPixels: [UInt8] = Array(repeating: 0xAB, count: 256)
        let audioSamples: [UInt8] = Array(repeating: 0xCD, count: 200)

        await server.broadcastFrame(videoPixels)
        await server.broadcastAudio(audioSamples)

        // All four streams should deliver data
        async let v1 = mcFirstElement(from: videoStream1, timeout: 2.0)
        async let v2 = mcFirstElement(from: videoStream2, timeout: 2.0)
        async let a1 = mcFirstElement(from: audioStream1, timeout: 2.0)
        async let a2 = mcFirstElement(from: audioStream2, timeout: 2.0)

        let (video1, video2, audio1, audio2) = await (v1, v2, a1, a2)

        XCTAssertNotNil(video1, "Client 1 should receive video")
        XCTAssertNotNil(video2, "Client 2 should receive video")
        XCTAssertNotNil(audio1, "Client 1 should receive audio")
        XCTAssertNotNil(audio2, "Client 2 should receive audio")

        XCTAssertEqual(video1, video2, "Both should receive same video data")
        XCTAssertEqual(audio1, audio2, "Both should receive same audio data")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: Input Tests
    // -------------------------------------------------------------------------

    /// Test that keyboard input from either client reaches the server.
    ///
    /// Both clients send different key events and the server delegate should
    /// record all of them, proving input routing works regardless of which
    /// client sends it.
    func test_inputFromEitherClientReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, clients) = try await createServerAndClients(
            controlPort: 50024,
            clientCount: 2,
            delegate: delegate
        )

        // Client 0 sends key 'A' (keyChar=65)
        await clients[0].sendKeyDown(keyChar: 65, keyCode: 0x3F)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Client 1 sends key 'B' (keyChar=66)
        await clients[1].sendKeyDown(keyChar: 66, keyCode: 0x15)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Server should have received both keyDown messages
        let keyMessages = await delegate.storage.messages(ofType: .keyDown)
        XCTAssertEqual(keyMessages.count, 2,
                       "Server should have received 2 keyDown messages")

        // The messages should come from different client UUIDs
        if keyMessages.count == 2 {
            XCTAssertNotEqual(keyMessages[0].clientId, keyMessages[1].clientId,
                              "KeyDown messages should come from different clients")
        }

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that joystick input from either client reaches the server.
    func test_joystickInputFromEitherClient() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, clients) = try await createServerAndClients(
            controlPort: 50027,
            clientCount: 2,
            delegate: delegate
        )

        // Client 0 sends joystick up+trigger
        await clients[0].sendJoystick(port: 0, up: true, trigger: true)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Client 1 sends joystick down+left
        await clients[1].sendJoystick(port: 0, down: true, left: true)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let joystickMessages = await delegate.storage.messages(ofType: .joystick)
        XCTAssertEqual(joystickMessages.count, 2,
                       "Server should have received 2 joystick messages")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

    /// Test that console key input from either client reaches the server.
    func test_consoleKeysFromEitherClient() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, clients) = try await createServerAndClients(
            controlPort: 50030,
            clientCount: 2,
            delegate: delegate
        )

        // Client 0 sends START
        await clients[0].sendConsoleKeys(start: true)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Client 1 sends SELECT+OPTION
        await clients[1].sendConsoleKeys(select: true, option: true)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let consoleMessages = await delegate.storage.messages(ofType: .consoleKeys)
        XCTAssertEqual(consoleMessages.count, 2,
                       "Server should have received 2 consoleKeys messages")

        for client in clients { await client.disconnect() }
        await server.stop()
    }

}

// =============================================================================
// MARK: - 14.2 CLI and GUI Together Tests
// =============================================================================

/// Tests for a CLI client (control-only) and GUI client (all channels)
/// connecting to the same server simultaneously.
///
/// In the real application:
/// - The CLI connects only to the control channel (no video/audio needed)
/// - The GUI connects to all three channels (control, video, audio)
///
/// These tests verify:
/// - Both client types can coexist on the same server
/// - CLI commands (pause, resume, reset, status) affect server state
/// - GUI continues receiving frames while CLI issues commands
/// - Both can independently pause/resume the emulator
/// - Server delegate correctly receives messages from both
///
/// Port range: 50100-50199 (3 ports per test).
final class AESPCLIAndGUITogetherTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    // -------------------------------------------------------------------------
    // MARK: Connection Tests
    // -------------------------------------------------------------------------

    /// Test that a CLI (control-only) and GUI (all channels) client can
    /// both connect to the same server.
    func test_cliAndGuiCanConnect() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let serverConfig = AESPServerConfiguration(
            controlPort: 50100,
            videoPort: 50101,
            audioPort: 50102
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: mcServerStartDelay)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 50100,
            videoPort: 50101,
            audioPort: 50102
        )

        // CLI: control only (no video, no audio)
        let cliClient = AESPClient(configuration: clientConfig)
        try await cliClient.connect(connectVideo: false, connectAudio: false)

        // GUI: all channels
        let guiClient = AESPClient(configuration: clientConfig)
        try await guiClient.connect(connectVideo: true, connectAudio: true)

        try await Task.sleep(nanoseconds: mcServerStartDelay)

        // Both should report connected
        let cliConnected = await cliClient.isConnected
        let guiConnected = await guiClient.isConnected
        XCTAssertTrue(cliConnected, "CLI client should be connected")
        XCTAssertTrue(guiConnected, "GUI client should be connected")

        // Server should see 2 control, 1 video, 1 audio
        let counts = await server.clientCounts
        XCTAssertGreaterThanOrEqual(counts.control, 2,
            "Server should have 2+ control clients (CLI + GUI)")
        XCTAssertGreaterThanOrEqual(counts.video, 1,
            "Server should have 1+ video client (GUI only)")
        XCTAssertGreaterThanOrEqual(counts.audio, 1,
            "Server should have 1+ audio client (GUI only)")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: CLI Commands Affect Server State
    // -------------------------------------------------------------------------

    /// Test that a CLI pause command is processed by the server.
    ///
    /// The CLI sends PAUSE on the control channel and the server delegate
    /// receives it and responds with ACK.
    func test_cliPauseReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50103, delegate: delegate
        )

        // CLI sends pause
        await cliClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // Server should have received a pause message
        let pauseMessages = await delegate.storage.messages(ofType: .pause)
        XCTAssertEqual(pauseMessages.count, 1,
                       "Server should receive 1 pause message from CLI")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that a CLI resume command is processed by the server.
    func test_cliResumeReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50106, delegate: delegate
        )

        await cliClient.resume()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let resumeMessages = await delegate.storage.messages(ofType: .resume)
        XCTAssertEqual(resumeMessages.count, 1,
                       "Server should receive 1 resume message from CLI")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that a CLI reset command is processed by the server.
    func test_cliResetReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50109, delegate: delegate
        )

        await cliClient.reset(cold: true)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let resetMessages = await delegate.storage.messages(ofType: .reset)
        XCTAssertEqual(resetMessages.count, 1,
                       "Server should receive 1 reset message from CLI")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: GUI Receives Frames While CLI Commands
    // -------------------------------------------------------------------------

    /// Test that the GUI continues receiving video frames while the CLI
    /// sends control commands.
    ///
    /// This simulates the real use case: a user types commands in the CLI
    /// REPL while watching the emulator display in the GUI window.
    func test_guiReceivesFramesDuringCLICommands() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50112, delegate: delegate
        )

        let frameStream = await guiClient.frameStream

        // CLI sends pause (a common command)
        await cliClient.pause()

        // Server broadcasts a frame (regardless of pause — the protocol
        // layer doesn't enforce pause semantics, only the emulator does)
        let testPixels: [UInt8] = Array(repeating: 0xEF, count: 256)
        await server.broadcastFrame(testPixels)

        // GUI should still receive the frame
        let frame = await mcFirstElement(from: frameStream, timeout: 2.0)
        XCTAssertNotNil(frame, "GUI should receive frames even while CLI sends commands")
        XCTAssertEqual(frame?.count, 256)

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that the GUI continues receiving audio while the CLI commands.
    func test_guiReceivesAudioDuringCLICommands() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50115, delegate: delegate
        )

        let audioStream = await guiClient.audioStream

        // CLI sends status request
        await cliClient.requestStatus()

        // Server broadcasts audio
        let testSamples: [UInt8] = Array(repeating: 0x80, count: 200)
        await server.broadcastAudio(testSamples)

        let audio = await mcFirstElement(from: audioStream, timeout: 2.0)
        XCTAssertNotNil(audio, "GUI should receive audio while CLI sends commands")
        XCTAssertEqual(audio?.count, 200)

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: Both Can Pause/Resume
    // -------------------------------------------------------------------------

    /// Test that both CLI and GUI can send pause commands independently.
    ///
    /// Both clients send PAUSE and the server should process both. This
    /// verifies there's no "ownership" restriction on control commands.
    func test_bothCanPause() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50118, delegate: delegate
        )

        // CLI pauses
        await cliClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // GUI also pauses
        await guiClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let pauseMessages = await delegate.storage.messages(ofType: .pause)
        XCTAssertEqual(pauseMessages.count, 2,
                       "Server should receive pause from both CLI and GUI")

        // Verify they came from different clients
        if pauseMessages.count == 2 {
            XCTAssertNotEqual(pauseMessages[0].clientId, pauseMessages[1].clientId,
                              "Pauses should come from different client UUIDs")
        }

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that both CLI and GUI can send resume commands independently.
    func test_bothCanResume() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50121, delegate: delegate
        )

        // CLI resumes
        await cliClient.resume()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // GUI also resumes
        await guiClient.resume()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let resumeMessages = await delegate.storage.messages(ofType: .resume)
        XCTAssertEqual(resumeMessages.count, 2,
                       "Server should receive resume from both CLI and GUI")

        if resumeMessages.count == 2 {
            XCTAssertNotEqual(resumeMessages[0].clientId, resumeMessages[1].clientId,
                              "Resumes should come from different client UUIDs")
        }

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test interleaved pause/resume from CLI and GUI.
    ///
    /// CLI pauses → GUI resumes → CLI resumes → GUI pauses.
    /// All four messages should reach the server in order.
    func test_interleavedPauseResume() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50124, delegate: delegate
        )

        // Interleaved sequence
        await cliClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        await guiClient.resume()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        await cliClient.resume()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        await guiClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let allMessages = await delegate.storage.receivedMessages
        let pauseResumeMessages = allMessages.filter {
            $0.message.type == .pause || $0.message.type == .resume
        }

        XCTAssertEqual(pauseResumeMessages.count, 4,
                       "Server should receive all 4 pause/resume messages")

        // Verify order: pause, resume, resume, pause
        if pauseResumeMessages.count == 4 {
            XCTAssertEqual(pauseResumeMessages[0].message.type, .pause)
            XCTAssertEqual(pauseResumeMessages[1].message.type, .resume)
            XCTAssertEqual(pauseResumeMessages[2].message.type, .resume)
            XCTAssertEqual(pauseResumeMessages[3].message.type, .pause)
        }

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: CLI Input Reaches Server While GUI Connected
    // -------------------------------------------------------------------------

    /// Test that keyboard input sent by CLI reaches the server even though
    /// the CLI has no video/audio connections.
    func test_cliKeyboardInputReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50127, delegate: delegate
        )

        // CLI sends keyboard input (even though it has no display)
        await cliClient.sendKeyDown(keyChar: 65, keyCode: 0x3F)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let keyMessages = await delegate.storage.messages(ofType: .keyDown)
        XCTAssertEqual(keyMessages.count, 1,
                       "Server should receive keyDown from CLI")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that GUI keyboard input reaches the server while CLI is connected.
    func test_guiKeyboardInputReachesServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50130, delegate: delegate
        )

        // GUI sends keyboard input
        await guiClient.sendKeyDown(keyChar: 66, keyCode: 0x15)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let keyMessages = await delegate.storage.messages(ofType: .keyDown)
        XCTAssertEqual(keyMessages.count, 1,
                       "Server should receive keyDown from GUI")

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that both CLI and GUI can send keyboard input.
    func test_bothCanSendKeyboardInput() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50133, delegate: delegate
        )

        await cliClient.sendKeyDown(keyChar: 65, keyCode: 0x3F)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        await guiClient.sendKeyDown(keyChar: 66, keyCode: 0x15)
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        let keyMessages = await delegate.storage.messages(ofType: .keyDown)
        XCTAssertEqual(keyMessages.count, 2,
                       "Server should receive keyDown from both CLI and GUI")

        if keyMessages.count == 2 {
            XCTAssertNotEqual(keyMessages[0].clientId, keyMessages[1].clientId,
                              "Key inputs should come from different client UUIDs")
        }

        await cliClient.disconnect()
        await guiClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: CLI Disconnect Doesn't Affect GUI
    // -------------------------------------------------------------------------

    /// Test that disconnecting the CLI client leaves the GUI fully functional.
    func test_cliDisconnectDoesNotAffectGUI() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50136, delegate: delegate
        )

        // Disconnect CLI
        await cliClient.disconnect()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // GUI should still be connected
        let guiConnected = await guiClient.isConnected
        XCTAssertTrue(guiConnected, "GUI should remain connected after CLI disconnects")

        // GUI should still receive frames
        let frameStream = await guiClient.frameStream
        await server.broadcastFrame(Array(repeating: 0xAA, count: 100))
        let frame = await mcFirstElement(from: frameStream, timeout: 2.0)
        XCTAssertNotNil(frame, "GUI should still receive frames after CLI disconnects")

        // GUI should still receive audio
        let audioStream = await guiClient.audioStream
        await server.broadcastAudio(Array(repeating: 0xBB, count: 100))
        let audio = await mcFirstElement(from: audioStream, timeout: 2.0)
        XCTAssertNotNil(audio, "GUI should still receive audio after CLI disconnects")

        // GUI can still send commands
        await guiClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        let pauseMessages = await delegate.storage.messages(ofType: .pause)
        XCTAssertEqual(pauseMessages.count, 1,
                       "GUI should still be able to send commands after CLI disconnects")

        await guiClient.disconnect()
        await server.stop()
    }

    /// Test that disconnecting the GUI client leaves the CLI functional.
    func test_guiDisconnectDoesNotAffectCLI() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MultiClientDelegate()
        let (server, cliClient, guiClient) = try await createCLIAndGUI(
            controlPort: 50139, delegate: delegate
        )

        // Disconnect GUI
        await guiClient.disconnect()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)

        // CLI should still be connected
        let cliConnected = await cliClient.isConnected
        XCTAssertTrue(cliConnected, "CLI should remain connected after GUI disconnects")

        // CLI can still send commands
        await cliClient.pause()
        try await Task.sleep(nanoseconds: mcMessagePropagationDelay)
        let pauseMessages = await delegate.storage.messages(ofType: .pause)
        XCTAssertEqual(pauseMessages.count, 1,
                       "CLI should still be able to send commands after GUI disconnects")

        await cliClient.disconnect()
        await server.stop()
    }

    // -------------------------------------------------------------------------
    // MARK: Helpers
    // -------------------------------------------------------------------------

    /// Creates a server with one CLI client (control-only) and one GUI client
    /// (all channels).
    ///
    /// This is the standard setup for CLI+GUI tests, extracting the boilerplate
    /// of creating configs, starting the server, and connecting both clients.
    private func createCLIAndGUI(
        controlPort: Int,
        delegate: MultiClientDelegate? = nil
    ) async throws -> (AESPServer, AESPClient, AESPClient) {
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
        try await Task.sleep(nanoseconds: mcServerStartDelay)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: controlPort,
            videoPort: controlPort + 1,
            audioPort: controlPort + 2
        )

        // CLI: control channel only
        let cliClient = AESPClient(configuration: clientConfig)
        try await cliClient.connect(connectVideo: false, connectAudio: false)

        // GUI: all channels
        let guiClient = AESPClient(configuration: clientConfig)
        try await guiClient.connect(connectVideo: true, connectAudio: true)

        try await Task.sleep(nanoseconds: mcServerStartDelay)

        return (server, cliClient, guiClient)
    }

}
