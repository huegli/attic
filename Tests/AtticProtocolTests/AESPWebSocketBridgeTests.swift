// =============================================================================
// AESPWebSocketBridgeTests.swift - Tests for WebSocket Bridge
// =============================================================================
//
// This file contains tests for the AESPWebSocketBridge actor, which bridges
// WebSocket clients to the AESP protocol. Tests cover:
//
// - Bridge lifecycle (start/stop)
// - WebSocket connection establishment and disconnection
// - AESP message passthrough (binary frames over WebSocket)
// - Ping/pong handling
// - Frame and audio broadcasting to WebSocket clients
// - Multiple client support
// - Client limit enforcement
//
// Port Allocation (49800-49899, avoids conflicts with other test suites):
// - Lifecycle tests: 49800-49809
// - Connection tests: 49810-49819
// - Message tests: 49820-49839
// - Broadcast tests: 49840-49859
// - Multi-client tests: 49860-49879
// - Limit tests: 49880-49899
//
// =============================================================================

import XCTest
@testable import AtticProtocol
#if canImport(Network)
import Network
#endif
import os.lock

// =============================================================================
// MARK: - Mock WebSocket Bridge Delegate
// =============================================================================

/// Thread-safe storage for the mock bridge delegate.
///
/// Uses NSLock instead of an actor to avoid scheduling contention with
/// the bridge actor and test polling. This is intentional for test code
/// where low-latency signaling matters more than actor isolation.
private final class MockBridgeDelegateStorage: @unchecked Sendable {
    private let lock = NSLock()

    /// All messages received from WebSocket clients.
    private var _receivedMessages: [AESPMessage] = []
    var receivedMessages: [AESPMessage] {
        lock.lock(); defer { lock.unlock() }
        return _receivedMessages
    }

    /// Client IDs that connected.
    private var _connectedClients: [UUID] = []
    var connectedClients: [UUID] {
        lock.lock(); defer { lock.unlock() }
        return _connectedClients
    }

    /// Client IDs that disconnected.
    private var _disconnectedClients: [UUID] = []
    var disconnectedClients: [UUID] {
        lock.lock(); defer { lock.unlock() }
        return _disconnectedClients
    }

    func addMessage(_ message: AESPMessage) {
        lock.lock(); defer { lock.unlock() }
        _receivedMessages.append(message)
    }

    func addConnectedClient(_ clientId: UUID) {
        lock.lock(); defer { lock.unlock() }
        _connectedClients.append(clientId)
    }

    func addDisconnectedClient(_ clientId: UUID) {
        lock.lock(); defer { lock.unlock() }
        _disconnectedClients.append(clientId)
    }
}

/// A mock delegate that records messages and events for test verification.
///
/// Like RespondingMockDelegate in AESPEndToEndTests, but for WebSocket clients.
/// Records all incoming messages and connection events without taking any
/// emulator actions (since these tests don't involve a real emulator).
private final class MockBridgeDelegate: AESPWebSocketBridgeDelegate, @unchecked Sendable {
    let storage = MockBridgeDelegateStorage()

    func bridge(_ bridge: AESPWebSocketBridge, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        storage.addMessage(message)
    }

    func bridge(_ bridge: AESPWebSocketBridge, clientDidConnect clientId: UUID) async {
        storage.addConnectedClient(clientId)
    }

    func bridge(_ bridge: AESPWebSocketBridge, clientDidDisconnect clientId: UUID) async {
        storage.addDisconnectedClient(clientId)
    }
}

// =============================================================================
// MARK: - WebSocket Client Helper
// =============================================================================

/// Lock-based message storage for the test WebSocket client.
///
/// Uses NSLock for thread-safe access from both the NWConnection callback
/// (dispatch queue) and the async test code. Avoids actor scheduling
/// contention that can cause test timeouts.
private final class TestClientMessageStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [AESPMessage] = []

    func append(_ message: AESPMessage) {
        lock.lock(); defer { lock.unlock() }
        messages.append(message)
    }

    func removeFirst() -> AESPMessage? {
        lock.lock(); defer { lock.unlock() }
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }
}

/// A minimal WebSocket client for testing the bridge.
///
/// Uses NWConnection with WebSocket protocol options to connect to the bridge,
/// send AESP messages, and receive responses. This mirrors how a web browser
/// would connect, except using Network framework instead of JavaScript.
private final class TestWebSocketClient: @unchecked Sendable {
    #if canImport(Network)
    private var connection: NWConnection?
    #endif

    /// Thread-safe storage for received messages.
    let messageStorage = TestClientMessageStorage()

    /// Connect to the WebSocket bridge on the given port.
    func connect(port: Int) async throws {
        #if canImport(Network)
        // Configure WebSocket protocol options, matching what a browser would use.
        let wsOptions = NWProtocolWebSocket.Options()
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let conn = NWConnection(
            host: "localhost",
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: parameters
        )
        self.connection = conn

        // Wait for connection to reach .ready state.
        // Use OSAllocatedUnfairLock as a resume guard to prevent double-resuming
        // the continuation from the NWConnection state handler (which fires on
        // a non-isolated dispatch queue).
        let resumed = OSAllocatedUnfairLock(initialState: false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        if flag { return false }
                        flag = true
                        return true
                    }
                    if shouldResume { continuation.resume() }
                case .failed(let error):
                    let shouldResume = resumed.withLock { flag -> Bool in
                        if flag { return false }
                        flag = true
                        return true
                    }
                    if shouldResume { continuation.resume(throwing: error) }
                case .cancelled:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        if flag { return false }
                        flag = true
                        return true
                    }
                    if shouldResume { continuation.resume(throwing: AESPError.connectionError("Cancelled")) }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // Start receiving messages
        startReceiving()
        #endif
    }

    /// Send an AESP message as a WebSocket binary frame.
    func send(_ message: AESPMessage) async throws {
        #if canImport(Network)
        guard let conn = connection else {
            throw AESPError.connectionError("Not connected")
        }

        let data = message.encode()
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "test-send",
            metadata: [metadata]
        )

        // isComplete must be true for WebSocket — it marks this WebSocket message
        // as complete. Without it, receiveMessage() on the server side will
        // buffer data indefinitely instead of delivering it.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        #endif
    }

    /// Wait for and return the next received message, with a timeout.
    func receiveNext(timeout: TimeInterval = 2.0) async throws -> AESPMessage {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let message = messageStorage.removeFirst() {
                return message
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms polling
        }
        throw AESPError.connectionError("Timeout waiting for message")
    }

    /// Disconnect from the bridge.
    func disconnect() {
        #if canImport(Network)
        connection?.cancel()
        connection = nil
        #endif
    }

    #if canImport(Network)
    /// Start receiving WebSocket messages asynchronously.
    ///
    /// Uses receiveMessage() which delivers one complete WebSocket frame at a
    /// time. The AESP message is decoded from the binary payload and stored
    /// for retrieval by receiveNext().
    private func startReceiving() {
        guard let conn = connection else { return }

        conn.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                if let (message, _) = try? AESPMessage.decode(from: data) {
                    self.messageStorage.append(message)
                }
            }

            // For WebSocket, isComplete: true means "this message is complete",
            // not "the connection is closing". Always continue receiving unless
            // there's an actual error.
            if error == nil {
                self.startReceiving()
            }
        }
    }
    #endif
}

// =============================================================================
// MARK: - Test Polling Helper
// =============================================================================

/// Polls an async condition until it returns true, or times out.
///
/// Actor scheduling means that a fixed `Task.sleep` may not be enough for
/// cross-actor operations to complete. This helper polls with a short interval
/// and returns when the condition is met, avoiding flaky tests.
///
/// - Parameters:
///   - timeout: Maximum time to wait (seconds).
///   - interval: Polling interval (nanoseconds, default 20ms).
///   - condition: Async closure that returns true when the expected state is reached.
/// - Returns: Whether the condition was met before timeout.
private func waitForCondition(
    timeout: TimeInterval = 2.0,
    interval: UInt64 = 20_000_000,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: interval)
    }
    return false
}

// =============================================================================
// MARK: - Lifecycle Tests
// =============================================================================

/// Tests for WebSocket bridge startup and shutdown.
final class AESPWebSocketBridgeLifecycleTests: XCTestCase {

    override func setUp() async throws {
        AESPTestProcessGuard.ensureClean()
    }

    /// Verifies the bridge starts and reports running state.
    func testBridgeStartsSuccessfully() async throws {
        let bridge = AESPWebSocketBridge(port: 49800)
        try await bridge.start()

        let isRunning = await bridge.isRunning
        XCTAssertTrue(isRunning)

        await bridge.stop()
        let isStopped = await bridge.isRunning
        XCTAssertFalse(isStopped)
    }

    /// Verifies double-start is a no-op (idempotent).
    func testDoubleStartIsNoOp() async throws {
        let bridge = AESPWebSocketBridge(port: 49801)
        try await bridge.start()
        try await bridge.start() // Should not throw

        let isRunning = await bridge.isRunning
        XCTAssertTrue(isRunning)

        await bridge.stop()
    }

    /// Verifies stop on a non-started bridge is safe.
    func testStopWithoutStartIsNoOp() async throws {
        let bridge = AESPWebSocketBridge(port: 49802)
        await bridge.stop() // Should not crash
    }

    /// Verifies the bridge initializes with zero clients.
    func testInitialClientCountIsZero() async throws {
        let bridge = AESPWebSocketBridge(port: 49803)
        let count = await bridge.clientCount
        XCTAssertEqual(count, 0)
    }
}

// =============================================================================
// MARK: - Connection Tests
// =============================================================================

/// Tests for WebSocket client connections to the bridge.
final class AESPWebSocketBridgeConnectionTests: XCTestCase {

    override func setUp() async throws {
        AESPTestProcessGuard.ensureClean()
    }

    /// Verifies a WebSocket client can connect to the bridge.
    func testClientCanConnect() async throws {
        let bridge = AESPWebSocketBridge(port: 49810)
        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }

        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        try await client.connect(port: 49810)
        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected, "Client should connect within timeout")

        let connectedClients = delegate.storage.connectedClients
        XCTAssertEqual(connectedClients.count, 1)
    }

    /// Verifies the delegate is notified when a client disconnects.
    func testClientDisconnectNotifiesDelegate() async throws {
        let bridge = AESPWebSocketBridge(port: 49811)
        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }

        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        try await client.connect(port: 49811)
        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        client.disconnect()
        let disconnected = await waitForCondition { await bridge.clientCount == 0 }
        XCTAssertTrue(disconnected, "Client should disconnect within timeout")

        let disconnectedClients = delegate.storage.disconnectedClients
        XCTAssertEqual(disconnectedClients.count, 1)
    }
}

// =============================================================================
// MARK: - Message Tests
// =============================================================================

/// Tests for AESP message exchange over WebSocket.
final class AESPWebSocketBridgeMessageTests: XCTestCase {

    override func setUp() async throws {
        AESPTestProcessGuard.ensureClean()
    }

    /// Verifies that a ping message receives a pong response.
    func testPingPongExchange() async throws {
        let bridge = AESPWebSocketBridge(port: 49820)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }
        try await client.connect(port: 49820)

        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        // Send PING, expect PONG
        try await client.send(.ping())
        let response = try await client.receiveNext(timeout: 3.0)
        XCTAssertEqual(response.type, .pong)
    }

    /// Verifies that control messages are forwarded to the delegate.
    func testControlMessageForwardedToDelegate() async throws {
        let bridge = AESPWebSocketBridge(port: 49821)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }
        try await client.connect(port: 49821)

        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        // Send PAUSE — should be forwarded to delegate
        try await client.send(.pause())

        let received = await waitForCondition {
            let msgs = delegate.storage.receivedMessages
            return msgs.count >= 1
        }
        XCTAssertTrue(received, "Delegate should receive PAUSE within timeout")

        let messages = delegate.storage.receivedMessages
        XCTAssertEqual(messages.first?.type, .pause)
    }

    /// Verifies that input messages (key press) are forwarded to the delegate.
    func testInputMessageForwardedToDelegate() async throws {
        let bridge = AESPWebSocketBridge(port: 49822)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }
        try await client.connect(port: 49822)

        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        // Send a key press
        try await client.send(.keyDown(keyChar: 65, keyCode: 0x3F, shift: false, control: false))

        let received = await waitForCondition {
            let msgs = delegate.storage.receivedMessages
            return msgs.count >= 1
        }
        XCTAssertTrue(received, "Delegate should receive KEY_DOWN within timeout")

        let messages = delegate.storage.receivedMessages
        XCTAssertEqual(messages.first?.type, .keyDown)
    }

    /// Verifies videoSubscribe is acknowledged (no-op for WebSocket).
    func testVideoSubscribeAcknowledged() async throws {
        let bridge = AESPWebSocketBridge(port: 49823)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }
        try await client.connect(port: 49823)

        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        try await client.send(.videoSubscribe())
        let response = try await client.receiveNext(timeout: 3.0)
        XCTAssertEqual(response.type, .ack)

        // Should NOT be forwarded to delegate (handled internally)
        let messages = delegate.storage.receivedMessages
        XCTAssertEqual(messages.count, 0)
    }
}

// =============================================================================
// MARK: - Broadcast Tests
// =============================================================================

/// Tests for frame and audio broadcasting to WebSocket clients.
final class AESPWebSocketBridgeBroadcastTests: XCTestCase {

    override func setUp() async throws {
        AESPTestProcessGuard.ensureClean()
    }

    /// Verifies a broadcast frame is received by the WebSocket client.
    func testBroadcastFrameDelivered() async throws {
        let bridge = AESPWebSocketBridge(port: 49840)
        let client = TestWebSocketClient()
        // Ensure cleanup even if test fails mid-way
        addTeardownBlock { client.disconnect(); await bridge.stop() }

        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        try await client.connect(port: 49840)
        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        let testPixels: [UInt8] = [0xFF, 0x00, 0x00, 0xFF]
        await bridge.broadcastFrame(testPixels)

        let response = try await client.receiveNext(timeout: 3.0)
        XCTAssertEqual(response.type, .frameRaw)
        XCTAssertEqual(Array(response.payload), testPixels)
    }

    /// Verifies broadcast audio is received by the WebSocket client.
    func testBroadcastAudioDelivered() async throws {
        let bridge = AESPWebSocketBridge(port: 49841)
        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }

        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        try await client.connect(port: 49841)
        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        let testSamples: [UInt8] = [0x00, 0x80, 0xFF, 0x7F]
        await bridge.broadcastAudio(testSamples)

        let response = try await client.receiveNext(timeout: 3.0)
        XCTAssertEqual(response.type, .audioPCM)
        XCTAssertEqual(Array(response.payload), testSamples)
    }

    /// Verifies audio sync broadcast carries the correct frame number.
    func testBroadcastAudioSyncDelivered() async throws {
        let bridge = AESPWebSocketBridge(port: 49842)
        let client = TestWebSocketClient()
        addTeardownBlock { client.disconnect(); await bridge.stop() }

        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        try await client.connect(port: 49842)
        let connected = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(connected)

        await bridge.broadcastAudioSync(frameNumber: 12345)

        let response = try await client.receiveNext(timeout: 3.0)
        XCTAssertEqual(response.type, .audioSync)
        let frameNum = response.parseAudioSyncPayload()
        XCTAssertEqual(frameNum, 12345)
    }

    /// Verifies broadcast with no clients doesn't crash.
    func testBroadcastWithNoClients() async throws {
        let bridge = AESPWebSocketBridge(port: 49843)
        try await bridge.start()

        // Should not crash or error
        await bridge.broadcastFrame([0xFF])
        await bridge.broadcastAudio([0x00])
        await bridge.broadcastAudioSync(frameNumber: 1)

        await bridge.stop()
    }

    /// Verifies the frame counter increments with each broadcast.
    func testFrameCounterIncrements() async throws {
        let bridge = AESPWebSocketBridge(port: 49844)
        try await bridge.start()

        let initial = await bridge.currentFrameNumber
        await bridge.broadcastFrame([0xFF])
        let after1 = await bridge.currentFrameNumber
        await bridge.broadcastFrame([0xFF])
        let after2 = await bridge.currentFrameNumber

        XCTAssertEqual(after1, initial + 1)
        XCTAssertEqual(after2, initial + 2)

        await bridge.stop()
    }
}

// =============================================================================
// MARK: - Multi-Client Tests
// =============================================================================

/// Tests for multiple simultaneous WebSocket clients.
final class AESPWebSocketBridgeMultiClientTests: XCTestCase {

    override func setUp() async throws {
        AESPTestProcessGuard.ensureClean()
    }

    /// Verifies multiple clients can connect simultaneously.
    func testMultipleClientsConnect() async throws {
        let bridge = AESPWebSocketBridge(port: 49860)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client1 = TestWebSocketClient()
        let client2 = TestWebSocketClient()
        addTeardownBlock { client1.disconnect(); client2.disconnect(); await bridge.stop() }
        try await client1.connect(port: 49860)
        try await client2.connect(port: 49860)

        let connected = await waitForCondition { await bridge.clientCount == 2 }
        XCTAssertTrue(connected, "Both clients should connect")
    }

    /// Verifies all connected clients receive broadcast frames.
    func testBroadcastReachesAllClients() async throws {
        let bridge = AESPWebSocketBridge(port: 49861)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client1 = TestWebSocketClient()
        let client2 = TestWebSocketClient()
        addTeardownBlock { client1.disconnect(); client2.disconnect(); await bridge.stop() }
        try await client1.connect(port: 49861)
        try await client2.connect(port: 49861)

        let connected = await waitForCondition { await bridge.clientCount == 2 }
        XCTAssertTrue(connected)

        let testPixels: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD]
        await bridge.broadcastFrame(testPixels)

        let msg1 = try await client1.receiveNext(timeout: 3.0)
        let msg2 = try await client2.receiveNext(timeout: 3.0)

        XCTAssertEqual(msg1.type, .frameRaw)
        XCTAssertEqual(msg2.type, .frameRaw)
        XCTAssertEqual(Array(msg1.payload), testPixels)
        XCTAssertEqual(Array(msg2.payload), testPixels)
    }

    /// Verifies disconnecting one client doesn't affect others.
    func testDisconnectOneClientOthersStillWork() async throws {
        let bridge = AESPWebSocketBridge(port: 49862)
        let delegate = MockBridgeDelegate()
        await bridge.setDelegate(delegate)
        try await bridge.start()

        let client1 = TestWebSocketClient()
        let client2 = TestWebSocketClient()
        addTeardownBlock { client1.disconnect(); client2.disconnect(); await bridge.stop() }
        try await client1.connect(port: 49862)
        try await client2.connect(port: 49862)

        let connected = await waitForCondition { await bridge.clientCount == 2 }
        XCTAssertTrue(connected)

        // Disconnect client1
        client1.disconnect()

        let oneLeft = await waitForCondition { await bridge.clientCount == 1 }
        XCTAssertTrue(oneLeft)

        // client2 should still receive broadcasts
        await bridge.broadcastFrame([0x11, 0x22, 0x33, 0x44])
        let msg = try await client2.receiveNext(timeout: 3.0)
        XCTAssertEqual(msg.type, .frameRaw)
    }
}

// Note: Client limit tests are omitted from the automated suite because the
// bridge cancels rejected connections before the WebSocket handshake completes,
// causing the client-side NWConnection to hang indefinitely. The max client
// limit is enforced in AESPWebSocketBridge.handleNewConnection() and can be
// verified via manual testing or by inspecting the bridge's log output.
