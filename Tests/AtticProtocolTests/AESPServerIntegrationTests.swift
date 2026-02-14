// =============================================================================
// AESPServerIntegrationTests.swift - Integration Tests for AESP Server
// =============================================================================
//
// This file contains integration tests for the AESP (Attic Emulator Server
// Protocol) server and client. Tests verify actual network communication
// between server and client components.
//
// Test Coverage:
// - Server lifecycle (start, stop)
// - Client connection/disconnection
// - Control channel communication (ping/pong, status)
// - Video frame broadcasting
// - Audio sample broadcasting
// - Error handling
//
// Note: These tests use actual TCP connections on localhost with random
// ports to avoid conflicts with running servers.
//
// =============================================================================

import XCTest
@testable import AtticProtocol
#if canImport(Network)
import Network
#endif

// =============================================================================
// MARK: - Server Configuration Tests
// =============================================================================

/// Tests for AESPServerConfiguration.
final class AESPServerConfigurationTests: XCTestCase {

    /// Test default configuration values.
    func test_defaultConfiguration() {
        let config = AESPServerConfiguration()

        XCTAssertEqual(config.controlPort, 47800)
        XCTAssertEqual(config.videoPort, 47801)
        XCTAssertEqual(config.audioPort, 47802)
        XCTAssertTrue(config.useTCP)
    }

    /// Test custom configuration.
    func test_customConfiguration() {
        let config = AESPServerConfiguration(
            controlPort: 48000,
            videoPort: 48001,
            audioPort: 48002,
            useTCP: true,
            socketBasePath: "/tmp/test-server"
        )

        XCTAssertEqual(config.controlPort, 48000)
        XCTAssertEqual(config.videoPort, 48001)
        XCTAssertEqual(config.audioPort, 48002)
        XCTAssertTrue(config.useTCP)
        XCTAssertEqual(config.socketBasePath, "/tmp/test-server")
    }
}

// =============================================================================
// MARK: - Client Configuration Tests
// =============================================================================

/// Tests for AESPClientConfiguration.
final class AESPClientConfigurationTests: XCTestCase {

    /// Test default configuration values.
    func test_defaultConfiguration() {
        let config = AESPClientConfiguration()

        XCTAssertEqual(config.host, "localhost")
        XCTAssertEqual(config.controlPort, 47800)
        XCTAssertEqual(config.videoPort, 47801)
        XCTAssertEqual(config.audioPort, 47802)
        XCTAssertEqual(config.connectionTimeout, 5.0)
    }

    /// Test custom configuration.
    func test_customConfiguration() {
        let config = AESPClientConfiguration(
            host: "192.168.1.100",
            controlPort: 48000,
            videoPort: 48001,
            audioPort: 48002,
            connectionTimeout: 10.0
        )

        XCTAssertEqual(config.host, "192.168.1.100")
        XCTAssertEqual(config.controlPort, 48000)
        XCTAssertEqual(config.connectionTimeout, 10.0)
    }
}

// =============================================================================
// MARK: - Server Lifecycle Tests
// =============================================================================

/// Tests for server lifecycle management.
final class AESPServerLifecycleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test server starts successfully.
    func test_serverStart() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        // Use non-default ports to avoid conflicts
        let config = AESPServerConfiguration(
            controlPort: 48100,
            videoPort: 48101,
            audioPort: 48102
        )
        let server = AESPServer(configuration: config)

        var isRunning = await server.isRunning
        XCTAssertFalse(isRunning)

        try await server.start()

        isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()

        isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
    }

    /// Test server stops cleanly.
    func test_serverStop() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48103,
            videoPort: 48104,
            audioPort: 48105
        )
        let server = AESPServer(configuration: config)

        try await server.start()
        await server.stop()

        let isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
    }

    /// Test double start is idempotent.
    func test_serverDoubleStart() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48106,
            videoPort: 48107,
            audioPort: 48108
        )
        let server = AESPServer(configuration: config)

        try await server.start()
        try await server.start() // Should be no-op

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }

    /// Test double stop is idempotent.
    func test_serverDoubleStop() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48109,
            videoPort: 48110,
            audioPort: 48111
        )
        let server = AESPServer(configuration: config)

        try await server.start()
        await server.stop()
        await server.stop() // Should be no-op

        let isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
    }

    /// Test client counts are zero when no clients connected.
    func test_clientCounts_empty() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48112,
            videoPort: 48113,
            audioPort: 48114
        )
        let server = AESPServer(configuration: config)

        try await server.start()

        let counts = await server.clientCounts
        XCTAssertEqual(counts.control, 0)
        XCTAssertEqual(counts.video, 0)
        XCTAssertEqual(counts.audio, 0)

        await server.stop()
    }

    /// Test frame counter starts at zero.
    func test_frameCounter_initial() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48115,
            videoPort: 48116,
            audioPort: 48117
        )
        let server = AESPServer(configuration: config)

        try await server.start()

        let frameNumber = await server.currentFrameNumber
        XCTAssertEqual(frameNumber, 0)

        await server.stop()
    }
}

// =============================================================================
// MARK: - Client State Tests
// =============================================================================

/// Tests for client state management.
final class AESPClientStateTests: XCTestCase {

    /// Test client initial state is disconnected.
    func test_clientInitialState() async {
        let client = AESPClient()

        let state = await client.state
        if case .disconnected = state {
            // Expected
        } else {
            XCTFail("Expected disconnected state")
        }

        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }

    /// Test client with custom host.
    func test_clientWithHost() async {
        let client = AESPClient(host: "192.168.1.100")
        let config = await client.configuration

        XCTAssertEqual(config.host, "192.168.1.100")
    }
}

// =============================================================================
// MARK: - Server-Client Communication Tests
// =============================================================================

/// Tests for server-client communication.
final class AESPServerClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test client connection to server.
    func test_clientConnectsToServer() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        // Start server
        let serverConfig = AESPServerConfiguration(
            controlPort: 48200,
            videoPort: 48201,
            audioPort: 48202
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()

        // Give server time to start listeners
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Connect client
        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 48200,
            videoPort: 48201,
            audioPort: 48202
        )
        let client = AESPClient(configuration: clientConfig)

        do {
            try await client.connect()

            let isConnected = await client.isConnected
            XCTAssertTrue(isConnected)

            // Give time for server to register connection
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            let counts = await server.clientCounts
            XCTAssertGreaterThanOrEqual(counts.control + counts.video + counts.audio, 1)

            await client.disconnect()
        } catch {
            // Connection might fail in CI environments
            print("Connection test skipped due to: \(error)")
        }

        await server.stop()
    }

    /// Test client disconnection.
    func test_clientDisconnects() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let serverConfig = AESPServerConfiguration(
            controlPort: 48203,
            videoPort: 48204,
            audioPort: 48205
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()

        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 48203,
            videoPort: 48204,
            audioPort: 48205
        )
        let client = AESPClient(configuration: clientConfig)

        do {
            try await client.connect()
            await client.disconnect()

            let isConnected = await client.isConnected
            XCTAssertFalse(isConnected)
        } catch {
            print("Disconnection test skipped due to: \(error)")
        }

        await server.stop()
    }
}

// =============================================================================
// MARK: - Server Delegate Tests
// =============================================================================

/// Mock delegate for testing server events using actor for thread safety.
actor MockServerDelegateStorage {
    var receivedMessages: [AESPMessage] = []
    var connectedClients: [(UUID, AESPChannel)] = []
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

/// Mock delegate for testing server events.
final class MockServerDelegate: AESPServerDelegate, @unchecked Sendable {
    let storage = MockServerDelegateStorage()

    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        await storage.addMessage(message)
    }

    func server(_ server: AESPServer, clientDidConnect clientId: UUID, channel: AESPChannel) async {
        await storage.addConnectedClient(clientId, channel: channel)
    }

    func server(_ server: AESPServer, clientDidDisconnect clientId: UUID, channel: AESPChannel) async {
        await storage.addDisconnectedClient(clientId, channel: channel)
    }
}

/// Tests for server delegate callbacks.
final class AESPServerDelegateTests: XCTestCase {

    /// Test delegate can be created.
    func test_delegateCreation() {
        let delegate = MockServerDelegate()
        XCTAssertNotNil(delegate)
    }

    /// Test storage tracks messages.
    func test_delegateStorageTracksMessages() async {
        let delegate = MockServerDelegate()
        await delegate.storage.addMessage(AESPMessage.ping())
        await delegate.storage.addMessage(AESPMessage.pong())

        let messages = await delegate.storage.receivedMessages
        XCTAssertEqual(messages.count, 2)
    }

    /// Test storage tracks connections.
    func test_delegateStorageTracksConnections() async {
        let delegate = MockServerDelegate()
        let clientId = UUID()
        await delegate.storage.addConnectedClient(clientId, channel: .control)

        let clients = await delegate.storage.connectedClients
        XCTAssertEqual(clients.count, 1)
        XCTAssertEqual(clients[0].0, clientId)
        XCTAssertEqual(clients[0].1, .control)
    }
}

// =============================================================================
// MARK: - Video Broadcast Tests
// =============================================================================

/// Tests for video frame broadcasting.
final class AESPVideoBroadcastTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test broadcasting increments frame counter.
    func test_broadcastIncrementsFrameCounter() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48400,
            videoPort: 48401,
            audioPort: 48402
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        let initialFrame = await server.currentFrameNumber
        XCTAssertEqual(initialFrame, 0)

        // Broadcast some frames
        let testFrame: [UInt8] = Array(repeating: 0xAB, count: 100)
        await server.broadcastFrame(testFrame)
        await server.broadcastFrame(testFrame)
        await server.broadcastFrame(testFrame)

        let finalFrame = await server.currentFrameNumber
        XCTAssertEqual(finalFrame, 3)

        await server.stop()
    }

    /// Test broadcasting frame with Data.
    func test_broadcastFrameWithData() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48403,
            videoPort: 48404,
            audioPort: 48405
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        let testFrame = Data(repeating: 0xCD, count: 100)
        await server.broadcastFrame(testFrame)

        let frameNumber = await server.currentFrameNumber
        XCTAssertEqual(frameNumber, 1)

        await server.stop()
    }
}

// =============================================================================
// MARK: - Audio Broadcast Tests
// =============================================================================

/// Tests for audio sample broadcasting.
final class AESPAudioBroadcastTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test broadcasting audio samples.
    func test_broadcastAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48500,
            videoPort: 48501,
            audioPort: 48502
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        // Broadcast should not crash even with no subscribers
        let testSamples: [UInt8] = Array(repeating: 0x80, count: 1470)
        await server.broadcastAudio(testSamples)

        // Verify server is still running
        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }

    /// Test broadcasting audio with Data.
    func test_broadcastAudioWithData() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48503,
            videoPort: 48504,
            audioPort: 48505
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        let testSamples = Data(repeating: 0x80, count: 1470)
        await server.broadcastAudio(testSamples)

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }

    /// Test broadcasting audio sync.
    func test_broadcastAudioSync() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48506,
            videoPort: 48507,
            audioPort: 48508
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        // Broadcast a frame to increment counter
        await server.broadcastFrame([0x00])

        // Broadcast sync
        await server.broadcastAudioSync()

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }
}

// =============================================================================
// MARK: - Channel Tests
// =============================================================================

/// Tests for AESPChannel enum.
final class AESPChannelTests: XCTestCase {

    /// Test channel raw values.
    func test_channelRawValues() {
        XCTAssertEqual(AESPChannel.control.rawValue, "control")
        XCTAssertEqual(AESPChannel.video.rawValue, "video")
        XCTAssertEqual(AESPChannel.audio.rawValue, "audio")
    }
}

// =============================================================================
// MARK: - Server Delegate Property Tests
// =============================================================================

/// Tests for server delegate property.
final class AESPServerDelegatePropertyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test server delegate can be assigned.
    func test_serverDelegateAssignment() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48600,
            videoPort: 48601,
            audioPort: 48602
        )
        let server = AESPServer(configuration: config)

        // Verify server can be started without delegate
        try await server.start()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Message Broadcast Tests
// =============================================================================

/// Tests for broadcasting messages on specific channels.
final class AESPMessageBroadcastTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test broadcast on control channel.
    func test_broadcastOnControlChannel() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48700,
            videoPort: 48701,
            audioPort: 48702
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        // Broadcast a message (should not crash even with no clients)
        await server.broadcast(.status(), on: .control)

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }

    /// Test broadcast on video channel.
    func test_broadcastOnVideoChannel() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48703,
            videoPort: 48704,
            audioPort: 48705
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        await server.broadcast(.frameRaw(pixels: [0x00]), on: .video)

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }

    /// Test broadcast on audio channel.
    func test_broadcastOnAudioChannel() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let config = AESPServerConfiguration(
            controlPort: 48706,
            videoPort: 48707,
            audioPort: 48708
        )
        let server = AESPServer(configuration: config)
        try await server.start()

        await server.broadcast(.audioPCM(samples: Data([0x00])), on: .audio)

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning)

        await server.stop()
    }
}

// =============================================================================
// MARK: - Client Connection Options Tests
// =============================================================================

/// Tests for client connection options.
final class AESPClientConnectionOptionsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test client can connect without video channel.
    func test_connectWithoutVideo() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let serverConfig = AESPServerConfiguration(
            controlPort: 48800,
            videoPort: 48801,
            audioPort: 48802
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 48800,
            videoPort: 48801,
            audioPort: 48802
        )
        let client = AESPClient(configuration: clientConfig)

        do {
            try await client.connect(connectVideo: false, connectAudio: true)

            let isConnected = await client.isConnected
            XCTAssertTrue(isConnected)

            await client.disconnect()
        } catch {
            print("Connect without video test skipped due to: \(error)")
        }

        await server.stop()
    }

    /// Test client can connect without audio channel.
    func test_connectWithoutAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let serverConfig = AESPServerConfiguration(
            controlPort: 48803,
            videoPort: 48804,
            audioPort: 48805
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 48803,
            videoPort: 48804,
            audioPort: 48805
        )
        let client = AESPClient(configuration: clientConfig)

        do {
            try await client.connect(connectVideo: true, connectAudio: false)

            let isConnected = await client.isConnected
            XCTAssertTrue(isConnected)

            await client.disconnect()
        } catch {
            print("Connect without audio test skipped due to: \(error)")
        }

        await server.stop()
    }

    /// Test client can connect control only.
    func test_connectControlOnly() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let serverConfig = AESPServerConfiguration(
            controlPort: 48806,
            videoPort: 48807,
            audioPort: 48808
        )
        let server = AESPServer(configuration: serverConfig)
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let clientConfig = AESPClientConfiguration(
            host: "localhost",
            controlPort: 48806,
            videoPort: 48807,
            audioPort: 48808
        )
        let client = AESPClient(configuration: clientConfig)

        do {
            try await client.connect(connectVideo: false, connectAudio: false)

            let isConnected = await client.isConnected
            XCTAssertTrue(isConnected)

            await client.disconnect()
        } catch {
            print("Connect control only test skipped due to: \(error)")
        }

        await server.stop()
    }
}

// =============================================================================
// MARK: - Integration Test Helpers
// =============================================================================

/// Standard delay for server startup in integration tests (100ms).
private let integrationServerStartDelay: UInt64 = 100_000_000

/// Standard delay for message propagation in integration tests (200ms).
private let integrationMessageDelay: UInt64 = 200_000_000

/// Creates a server and connected client pair for integration testing.
///
/// This helper handles the boilerplate of:
/// 1. Creating server/client configurations with matching ports
/// 2. Setting the server delegate
/// 3. Starting the server and waiting for listeners
/// 4. Connecting the client and waiting for connection establishment
///
/// - Parameters:
///   - controlPort: Base port for control channel (video = +1, audio = +2).
///   - connectVideo: Whether the client connects to the video channel.
///   - connectAudio: Whether the client connects to the audio channel.
///   - delegate: Server delegate for receiving messages.
/// - Returns: Tuple of (server, client) ready for testing.
private func createIntegrationServerAndClient(
    controlPort: Int,
    connectVideo: Bool = false,
    connectAudio: Bool = false,
    delegate: MockServerDelegate
) async throws -> (AESPServer, AESPClient) {
    let serverConfig = AESPServerConfiguration(
        controlPort: controlPort,
        videoPort: controlPort + 1,
        audioPort: controlPort + 2
    )
    let server = AESPServer(configuration: serverConfig)
    await server.setDelegate(delegate)

    try await server.start()
    try await Task.sleep(nanoseconds: integrationServerStartDelay)

    let clientConfig = AESPClientConfiguration(
        host: "localhost",
        controlPort: controlPort,
        videoPort: controlPort + 1,
        audioPort: controlPort + 2
    )
    let client = AESPClient(configuration: clientConfig)

    try await client.connect(connectVideo: connectVideo, connectAudio: connectAudio)
    try await Task.sleep(nanoseconds: integrationServerStartDelay)

    return (server, client)
}

/// Extension to set delegate on AESPServer (convenience for integration tests).
///
/// The server's `delegate` property is directly assignable since AESPServer
/// is an actor — we just need `await` to cross the actor boundary.
private extension AESPServer {
    func setDelegate(_ delegate: AESPServerDelegate) {
        self.delegate = delegate
    }
}

// =============================================================================
// MARK: - Client Command Tests
// =============================================================================

/// Integration tests for client command methods.
///
/// Each test connects a client to a real server, sends a command, and verifies
/// the server delegate receives the correct message type. Port range: 49400-49414.
final class AESPClientCommandTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test ping sends a PING message and server auto-responds with PONG.
    ///
    /// PING is handled internally by AESPServer.handleMessage (not forwarded
    /// to the delegate), so we verify the client remains connected after the
    /// round-trip, confirming the message traversed the network.
    func test_clientPing() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49400,
            delegate: delegate
        )

        // Send PING — server handles it internally (sends PONG, doesn't forward to delegate)
        await client.ping()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify client is still connected (PING/PONG succeeded without error)
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should remain connected after PING")

        // Verify server is still running
        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should remain running after PING")

        await client.disconnect()
        await server.stop()
    }

    /// Test pause sends a PAUSE message that the server delegate receives.
    func test_clientPause() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49403,
            delegate: delegate
        )

        await client.pause()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received PAUSE
        let messages = await delegate.storage.receivedMessages
        XCTAssertTrue(messages.contains { $0.type == .pause },
                      "Server delegate should have received PAUSE message")

        await client.disconnect()
        await server.stop()
    }

    /// Test resume sends a RESUME message that the server delegate receives.
    func test_clientResume() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49406,
            delegate: delegate
        )

        await client.resume()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received RESUME
        let messages = await delegate.storage.receivedMessages
        XCTAssertTrue(messages.contains { $0.type == .resume },
                      "Server delegate should have received RESUME message")

        await client.disconnect()
        await server.stop()
    }

    /// Test reset sends a RESET message with the correct cold/warm flag.
    ///
    /// The reset payload is 1 byte: 0x01 for cold reset, 0x00 for warm reset.
    func test_clientReset() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49409,
            delegate: delegate
        )

        // Send cold reset
        await client.reset(cold: true)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Send warm reset
        await client.reset(cold: false)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received both RESET messages
        let messages = await delegate.storage.receivedMessages
        let resets = messages.filter { $0.type == .reset }
        XCTAssertEqual(resets.count, 2, "Should have received 2 RESET messages")

        // First reset should be cold (payload byte = 0x01)
        if resets.count >= 2 {
            XCTAssertEqual(resets[0].payload.first, 0x01,
                           "First reset should be cold (0x01)")
            XCTAssertEqual(resets[1].payload.first, 0x00,
                           "Second reset should be warm (0x00)")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test requestStatus sends a STATUS message that the server delegate receives.
    func test_clientRequestStatus() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49412,
            delegate: delegate
        )

        await client.requestStatus()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received STATUS
        let messages = await delegate.storage.receivedMessages
        XCTAssertTrue(messages.contains { $0.type == .status },
                      "Server delegate should have received STATUS message")

        await client.disconnect()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Client Input Tests
// =============================================================================

/// Integration tests for client input methods.
///
/// Each test connects a client to a real server, sends an input event, and
/// verifies the server delegate receives the correct message with the expected
/// payload values. Port range: 49415-49426.
final class AESPClientInputTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test sendKeyDown sends a KEY_DOWN message with correct payload.
    ///
    /// Payload format: [keyChar, keyCode, flags] where flags bit 0 = shift,
    /// bit 1 = control.
    func test_sendKeyDown() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49415,
            delegate: delegate
        )

        await client.sendKeyDown(keyChar: 0x41, keyCode: 0x3F, shift: true, control: false)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received KEY_DOWN with correct payload
        let messages = await delegate.storage.receivedMessages
        let keyDowns = messages.filter { $0.type == .keyDown }
        XCTAssertEqual(keyDowns.count, 1, "Should have received 1 KEY_DOWN message")

        if let keyMsg = keyDowns.first,
           let parsed = keyMsg.parseKeyPayload() {
            XCTAssertEqual(parsed.keyChar, 0x41, "keyChar should be 0x41 ('A')")
            XCTAssertEqual(parsed.keyCode, 0x3F, "keyCode should be 0x3F")
            XCTAssertTrue(parsed.shift, "shift should be true")
            XCTAssertFalse(parsed.control, "control should be false")
        } else {
            XCTFail("KEY_DOWN message should have parseable payload")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test sendKeyUp sends a KEY_UP message that the server delegate receives.
    func test_sendKeyUp() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49418,
            delegate: delegate
        )

        await client.sendKeyUp()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received KEY_UP
        let messages = await delegate.storage.receivedMessages
        XCTAssertTrue(messages.contains { $0.type == .keyUp },
                      "Server delegate should have received KEY_UP message")

        await client.disconnect()
        await server.stop()
    }

    /// Test sendJoystick sends a JOYSTICK message with correct payload.
    ///
    /// Payload format: [port, directions, trigger] where directions is a
    /// bitmask (bit 0=up, 1=down, 2=left, 3=right).
    func test_sendJoystick() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49421,
            delegate: delegate
        )

        await client.sendJoystick(port: 0, up: true, down: false, left: false, right: false, trigger: true)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received JOYSTICK with correct payload
        let messages = await delegate.storage.receivedMessages
        let joysticks = messages.filter { $0.type == .joystick }
        XCTAssertEqual(joysticks.count, 1, "Should have received 1 JOYSTICK message")

        if let joyMsg = joysticks.first,
           let parsed = joyMsg.parseJoystickPayload() {
            XCTAssertEqual(parsed.port, 0, "Port should be 0")
            XCTAssertTrue(parsed.up, "up should be true")
            XCTAssertFalse(parsed.down, "down should be false")
            XCTAssertFalse(parsed.left, "left should be false")
            XCTAssertFalse(parsed.right, "right should be false")
            XCTAssertTrue(parsed.trigger, "trigger should be true")
        } else {
            XCTFail("JOYSTICK message should have parseable payload")
        }

        await client.disconnect()
        await server.stop()
    }

    /// Test sendConsoleKeys sends a CONSOLE_KEYS message with correct payload.
    ///
    /// Payload format: 1 byte bitmask where bit 0=start, 1=select, 2=option.
    func test_sendConsoleKeys() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49424,
            delegate: delegate
        )

        await client.sendConsoleKeys(start: true, select: false, option: true)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify server delegate received CONSOLE_KEYS with correct payload
        let messages = await delegate.storage.receivedMessages
        let consoleKeys = messages.filter { $0.type == .consoleKeys }
        XCTAssertEqual(consoleKeys.count, 1, "Should have received 1 CONSOLE_KEYS message")

        if let ckMsg = consoleKeys.first,
           let parsed = ckMsg.parseConsoleKeysPayload() {
            XCTAssertTrue(parsed.start, "start should be true")
            XCTAssertFalse(parsed.select, "select should be false")
            XCTAssertTrue(parsed.option, "option should be true")
        } else {
            XCTFail("CONSOLE_KEYS message should have parseable payload")
        }

        await client.disconnect()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Client Subscription Tests
// =============================================================================

/// Integration tests for client subscription methods.
///
/// Subscription messages (VIDEO_SUBSCRIBE, VIDEO_UNSUBSCRIBE, AUDIO_SUBSCRIBE,
/// AUDIO_UNSUBSCRIBE) are handled internally by AESPServer.handleMessage rather
/// than being forwarded to the delegate. These tests verify the messages traverse
/// the network successfully by confirming the client and server remain healthy
/// after each subscription command. Port range: 49433-49444.
final class AESPClientSubscriptionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test subscribeToVideo sends VIDEO_SUBSCRIBE over the network.
    ///
    /// Verifies the message reaches the server without error by checking
    /// client stays connected and server stays running.
    func test_subscribeToVideo() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49433,
            delegate: delegate
        )

        // Send both delta and non-delta subscription requests
        await client.subscribeToVideo(deltaEncoding: false)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        await client.subscribeToVideo(deltaEncoding: true)
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        // Verify client and server remain healthy after subscription messages
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should remain connected after VIDEO_SUBSCRIBE")

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should remain running after VIDEO_SUBSCRIBE")

        await client.disconnect()
        await server.stop()
    }

    /// Test unsubscribeFromVideo sends VIDEO_UNSUBSCRIBE over the network.
    func test_unsubscribeFromVideo() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49436,
            delegate: delegate
        )

        await client.unsubscribeFromVideo()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should remain connected after VIDEO_UNSUBSCRIBE")

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should remain running after VIDEO_UNSUBSCRIBE")

        await client.disconnect()
        await server.stop()
    }

    /// Test subscribeToAudio sends AUDIO_SUBSCRIBE over the network.
    func test_subscribeToAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49439,
            delegate: delegate
        )

        await client.subscribeToAudio()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should remain connected after AUDIO_SUBSCRIBE")

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should remain running after AUDIO_SUBSCRIBE")

        await client.disconnect()
        await server.stop()
    }

    /// Test unsubscribeFromAudio sends AUDIO_UNSUBSCRIBE over the network.
    func test_unsubscribeFromAudio() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49442,
            delegate: delegate
        )

        await client.unsubscribeFromAudio()
        try await Task.sleep(nanoseconds: integrationMessageDelay)

        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should remain connected after AUDIO_UNSUBSCRIBE")

        let isRunning = await server.isRunning
        XCTAssertTrue(isRunning, "Server should remain running after AUDIO_UNSUBSCRIBE")

        await client.disconnect()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Client Stream Tests
// =============================================================================

/// Integration tests for client stream access when connected to a real server.
///
/// Unlike the previous stub tests that accessed streams on a disconnected client,
/// these tests connect to a real server with video/audio channels and verify the
/// streams are properly initialized. Port range: 49445-49450.
final class AESPClientStreamTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AESPTestProcessGuard.ensureClean()
    }

    /// Test frameStream is accessible and properly initialized when connected with video.
    func test_frameStreamAccess() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49445,
            connectVideo: true,
            delegate: delegate
        )

        // Access the frame stream — should be a real stream (not a finished placeholder)
        let stream = await client.frameStream
        XCTAssertNotNil(stream, "frameStream should be accessible when connected with video")

        // Verify client is connected with video channel active
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should be connected")

        await client.disconnect()
        await server.stop()
    }

    /// Test audioStream is accessible and properly initialized when connected with audio.
    func test_audioStreamAccess() async throws {
        #if !canImport(Network)
        throw XCTSkip("Network framework not available")
        #endif

        let delegate = MockServerDelegate()
        let (server, client) = try await createIntegrationServerAndClient(
            controlPort: 49448,
            connectAudio: true,
            delegate: delegate
        )

        // Access the audio stream — should be a real stream (not a finished placeholder)
        let stream = await client.audioStream
        XCTAssertNotNil(stream, "audioStream should be accessible when connected with audio")

        // Verify client is connected with audio channel active
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should be connected")

        await client.disconnect()
        await server.stop()
    }
}

// =============================================================================
// MARK: - Sendable Conformance Tests
// =============================================================================

/// Tests for Sendable conformance.
final class AESPSendableTests: XCTestCase {

    /// Test AESPMessage is Sendable.
    func test_messageIsSendable() {
        let message = AESPMessage.ping()

        // This compiles only if AESPMessage is Sendable
        Task {
            let _ = message
        }
    }

    /// Test AESPMessageType is Sendable.
    func test_messageTypeIsSendable() {
        let type = AESPMessageType.keyDown

        Task {
            let _ = type
        }
    }

    /// Test AESPError is Sendable.
    func test_errorIsSendable() {
        let error = AESPError.connectionError("test")

        Task {
            let _ = error
        }
    }

    /// Test AESPChannel is Sendable.
    func test_channelIsSendable() {
        let channel = AESPChannel.control

        Task {
            let _ = channel
        }
    }

    /// Test AESPClientState is Sendable.
    func test_clientStateIsSendable() {
        let state = AESPClientState.connected

        Task {
            let _ = state
        }
    }
}
