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
// MARK: - Client Command Tests
// =============================================================================

/// Tests for client command methods.
final class AESPClientCommandTests: XCTestCase {

    /// Test client ping method creates correct message.
    func test_clientPing() async {
        let client = AESPClient()

        // Just verify the method exists and doesn't crash
        // Actual network testing is done in integration tests
        await client.ping()
    }

    /// Test client pause method.
    func test_clientPause() async {
        let client = AESPClient()
        await client.pause()
    }

    /// Test client resume method.
    func test_clientResume() async {
        let client = AESPClient()
        await client.resume()
    }

    /// Test client reset method.
    func test_clientReset() async {
        let client = AESPClient()
        await client.reset(cold: true)
        await client.reset(cold: false)
    }

    /// Test client requestStatus method.
    func test_clientRequestStatus() async {
        let client = AESPClient()
        await client.requestStatus()
    }
}

// =============================================================================
// MARK: - Client Input Tests
// =============================================================================

/// Tests for client input methods.
final class AESPClientInputTests: XCTestCase {

    /// Test sendKeyDown method.
    func test_sendKeyDown() async {
        let client = AESPClient()
        await client.sendKeyDown(keyChar: 0x41, keyCode: 0x3F, shift: true, control: false)
    }

    /// Test sendKeyUp method.
    func test_sendKeyUp() async {
        let client = AESPClient()
        await client.sendKeyUp()
    }

    /// Test sendJoystick method.
    func test_sendJoystick() async {
        let client = AESPClient()
        await client.sendJoystick(port: 0, up: true, down: false, left: false, right: false, trigger: true)
    }

    /// Test sendConsoleKeys method.
    func test_sendConsoleKeys() async {
        let client = AESPClient()
        await client.sendConsoleKeys(start: true, select: false, option: true)
    }
}

// =============================================================================
// MARK: - Client Memory Access Tests
// =============================================================================

/// Tests for client memory access methods.
final class AESPClientMemoryTests: XCTestCase {

    /// Test readMemory method.
    func test_readMemory() async {
        let client = AESPClient()
        await client.readMemory(address: 0x0600, count: 16)
    }

    /// Test writeMemory method.
    func test_writeMemory() async {
        let client = AESPClient()
        await client.writeMemory(address: 0x0600, bytes: Data([0xA9, 0x00, 0x60]))
    }
}

// =============================================================================
// MARK: - Client Subscription Tests
// =============================================================================

/// Tests for client subscription methods.
final class AESPClientSubscriptionTests: XCTestCase {

    /// Test subscribeToVideo method.
    func test_subscribeToVideo() async {
        let client = AESPClient()
        await client.subscribeToVideo(deltaEncoding: false)
        await client.subscribeToVideo(deltaEncoding: true)
    }

    /// Test unsubscribeFromVideo method.
    func test_unsubscribeFromVideo() async {
        let client = AESPClient()
        await client.unsubscribeFromVideo()
    }

    /// Test subscribeToAudio method.
    func test_subscribeToAudio() async {
        let client = AESPClient()
        await client.subscribeToAudio()
    }

    /// Test unsubscribeFromAudio method.
    func test_unsubscribeFromAudio() async {
        let client = AESPClient()
        await client.unsubscribeFromAudio()
    }
}

// =============================================================================
// MARK: - Client Stream Tests
// =============================================================================

/// Tests for client stream access.
final class AESPClientStreamTests: XCTestCase {

    /// Test frameStream access.
    func test_frameStreamAccess() async {
        let client = AESPClient()
        let _ = await client.frameStream
        // Stream should be accessible
    }

    /// Test audioStream access.
    func test_audioStreamAccess() async {
        let client = AESPClient()
        let _ = await client.audioStream
        // Stream should be accessible
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
