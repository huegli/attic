// =============================================================================
// CLISocketTests.swift - Unit Tests for CLI Socket Server and Client
// =============================================================================
//
// This file contains tests for the Unix domain socket communication layer:
// - CLISocketServer: Server lifecycle, client management, command handling
// - CLISocketClient: Connection, discovery, command sending, event handling
// - Integration tests: Server and client working together
//
// Test Architecture:
// ------------------
// These tests use mock delegates to verify behavior without requiring
// a full emulator. Integration tests spin up actual server/client pairs
// and verify end-to-end communication.
//
// =============================================================================

import XCTest
@testable import AtticCore

// =============================================================================
// MARK: - Mock Delegate for Server
// =============================================================================

/// Mock delegate for testing CLISocketServer behavior.
///
/// This delegate records all calls and allows tests to configure responses.
/// It automatically returns "pong" for ping commands to support connection verification.
final class MockServerDelegate: CLISocketServerDelegate, @unchecked Sendable {
    /// Commands received from clients.
    var receivedCommands: [(command: CLICommand, clientId: UUID)] = []

    /// Client connection events.
    var connectedClients: [UUID] = []

    /// Client disconnection events.
    var disconnectedClients: [UUID] = []

    /// Response to return for non-ping commands.
    var responseToReturn: CLIResponse = .ok("default")

    /// Continuation to signal when a command is received.
    var commandContinuation: CheckedContinuation<Void, Never>?

    /// Continuation to signal when a client connects.
    var connectContinuation: CheckedContinuation<UUID, Never>?

    /// Continuation to signal when a client disconnects.
    var disconnectContinuation: CheckedContinuation<UUID, Never>?

    func server(
        _ server: CLISocketServer,
        didReceiveCommand command: CLICommand,
        from clientId: UUID
    ) async -> CLIResponse {
        receivedCommands.append((command, clientId))
        commandContinuation?.resume()
        commandContinuation = nil

        // Always return "pong" for ping commands (required for connection verification)
        if case .ping = command {
            return .ok("pong")
        }

        return responseToReturn
    }

    func server(_ server: CLISocketServer, clientDidConnect clientId: UUID) async {
        connectedClients.append(clientId)
        connectContinuation?.resume(returning: clientId)
        connectContinuation = nil
    }

    func server(_ server: CLISocketServer, clientDidDisconnect clientId: UUID) async {
        disconnectedClients.append(clientId)
        disconnectContinuation?.resume(returning: clientId)
        disconnectContinuation = nil
    }

    /// Waits for a command to be received.
    func waitForCommand() async {
        await withCheckedContinuation { continuation in
            commandContinuation = continuation
        }
    }

    /// Waits for a client to connect.
    func waitForConnect() async -> UUID {
        await withCheckedContinuation { continuation in
            connectContinuation = continuation
        }
    }

    /// Waits for a client to disconnect.
    func waitForDisconnect() async -> UUID {
        await withCheckedContinuation { continuation in
            disconnectContinuation = continuation
        }
    }
}

// =============================================================================
// MARK: - Mock Delegate for Client
// =============================================================================

/// Mock delegate for testing CLISocketClient behavior.
final class MockClientDelegate: CLISocketClientDelegate, @unchecked Sendable {
    /// Events received from server.
    var receivedEvents: [CLIEvent] = []

    /// Disconnection errors.
    var disconnectErrors: [Error?] = []

    /// Continuation to signal when an event is received.
    var eventContinuation: CheckedContinuation<CLIEvent, Never>?

    /// Continuation to signal when disconnected.
    var disconnectContinuation: CheckedContinuation<Void, Never>?

    func client(_ client: CLISocketClient, didReceiveEvent event: CLIEvent) async {
        receivedEvents.append(event)
        eventContinuation?.resume(returning: event)
        eventContinuation = nil
    }

    func client(_ client: CLISocketClient, didDisconnectWithError error: Error?) async {
        disconnectErrors.append(error)
        disconnectContinuation?.resume()
        disconnectContinuation = nil
    }

    /// Waits for an event to be received.
    func waitForEvent() async -> CLIEvent {
        await withCheckedContinuation { continuation in
            eventContinuation = continuation
        }
    }

    /// Waits for disconnection.
    func waitForDisconnect() async {
        await withCheckedContinuation { continuation in
            disconnectContinuation = continuation
        }
    }
}

// =============================================================================
// MARK: - CLISocketServer Tests
// =============================================================================

final class CLISocketServerTests: XCTestCase {
    var server: CLISocketServer!
    var delegate: MockServerDelegate!
    var testSocketPath: String!

    override func setUp() async throws {
        // Create a unique socket path for each test
        testSocketPath = "/tmp/attic-test-\(UUID().uuidString.prefix(8)).sock"
        server = CLISocketServer(socketPath: testSocketPath)
        delegate = MockServerDelegate()
        delegate.responseToReturn = .ok("pong")  // Return pong for ping commands
        await server.setDelegate(delegate)
    }

    override func tearDown() async throws {
        await server.stop()
        try? FileManager.default.removeItem(atPath: testSocketPath)
    }

    func testServerStartAndStop() async throws {
        // Server should start successfully
        try await server.start()

        // Socket file should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketPath))

        // Server path should be correct
        let path = await server.path
        XCTAssertEqual(path, testSocketPath)

        // Stop server
        await server.stop()

        // Socket file should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: testSocketPath))
    }

    func testServerStartTwice() async throws {
        try await server.start()

        // Starting again should not throw (should be idempotent)
        try await server.start()

        await server.stop()
    }

    func testServerStopWithoutStart() async throws {
        // Stopping without starting should not crash
        await server.stop()
    }
}

// =============================================================================
// MARK: - CLISocketClient Tests
// =============================================================================

final class CLISocketClientTests: XCTestCase {

    func testDiscoverSockets() {
        let client = CLISocketClient()

        // Create some test socket files
        let testPaths = [
            "/tmp/attic-test1-\(UUID().uuidString.prefix(8)).sock",
            "/tmp/attic-test2-\(UUID().uuidString.prefix(8)).sock"
        ]

        for path in testPaths {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        defer {
            for path in testPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        let discovered = client.discoverSockets()

        // Should find the test sockets (among any others)
        for path in testPaths {
            // The discovered list might have other real sockets too
            // Just verify our test paths are found somewhere in the list
            XCTAssertTrue(discovered.contains(where: { $0 == path }), "Should discover \(path)")
        }
    }

    func testDiscoverSocketsMostRecentFirst() {
        let client = CLISocketClient()

        // Create test sockets with different modification times
        let olderPath = "/tmp/attic-older-\(UUID().uuidString.prefix(8)).sock"
        let newerPath = "/tmp/attic-newer-\(UUID().uuidString.prefix(8)).sock"

        FileManager.default.createFile(atPath: olderPath, contents: nil)
        // Wait a bit to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.1)
        FileManager.default.createFile(atPath: newerPath, contents: nil)

        defer {
            try? FileManager.default.removeItem(atPath: olderPath)
            try? FileManager.default.removeItem(atPath: newerPath)
        }

        let discovered = client.discoverSockets()

        // Find positions of our test sockets
        if let olderIndex = discovered.firstIndex(of: olderPath),
           let newerIndex = discovered.firstIndex(of: newerPath) {
            // Newer should come before older
            XCTAssertLessThan(newerIndex, olderIndex, "Newer socket should be listed first")
        }
    }

    func testDiscoverSocketReturnsFirst() {
        let client = CLISocketClient()

        // Create a test socket
        let testPath = "/tmp/attic-single-\(UUID().uuidString.prefix(8)).sock"
        FileManager.default.createFile(atPath: testPath, contents: nil)

        defer {
            try? FileManager.default.removeItem(atPath: testPath)
        }

        // discoverSocket should return the most recent one
        if let discovered = client.discoverSocket() {
            // It should be a valid socket path
            XCTAssertTrue(discovered.hasPrefix("/tmp/attic-"))
            XCTAssertTrue(discovered.hasSuffix(".sock"))
        }
        // Note: discoverSocket() might return nil if no sockets exist
    }

    func testConnectToNonexistentSocket() async {
        let client = CLISocketClient()

        do {
            try await client.connect(to: "/tmp/nonexistent-socket.sock")
            XCTFail("Should throw connectionFailed error")
        } catch let error as CLIProtocolError {
            guard case .connectionFailed = error else {
                XCTFail("Expected connectionFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

// =============================================================================
// MARK: - Integration Tests (Server + Client)
// =============================================================================

final class CLISocketIntegrationTests: XCTestCase {
    var server: CLISocketServer!
    var serverDelegate: MockServerDelegate!
    var client: CLISocketClient!
    var clientDelegate: MockClientDelegate!
    var testSocketPath: String!

    override func setUp() async throws {
        testSocketPath = "/tmp/attic-integ-\(UUID().uuidString.prefix(8)).sock"

        // Set up server
        server = CLISocketServer(socketPath: testSocketPath)
        serverDelegate = MockServerDelegate()
        serverDelegate.responseToReturn = .ok("pong")
        await server.setDelegate(serverDelegate)

        // Set up client
        client = CLISocketClient()
        clientDelegate = MockClientDelegate()
    }

    override func tearDown() async throws {
        await client.disconnect()
        await server.stop()
        try? FileManager.default.removeItem(atPath: testSocketPath)
    }

    func testClientConnectsToServer() async throws {
        try await server.start()

        // Give server time to start listening
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Connect client
        try await client.connect(to: testSocketPath)

        // Verify connection
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected)

        // Verify server saw the connection
        // Note: The ping verification during connect will have registered the client
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        XCTAssertGreaterThan(serverDelegate.connectedClients.count, 0)
    }

    func testClientSendsPing() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("pong")
        try await client.connect(to: testSocketPath)

        // Send another ping (one was sent during connect)
        let response = try await client.send(.ping)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response, got \(response)")
            return
        }
        XCTAssertEqual(data, "pong")
    }

    func testClientSendsVersion() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("1.0")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.version)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertEqual(data, "1.0")
    }

    func testClientSendsPause() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("paused")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.pause)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertEqual(data, "paused")

        // Verify server received pause command
        try await Task.sleep(nanoseconds: 50_000_000)
        let pauseCommands = serverDelegate.receivedCommands.filter {
            if case .pause = $0.command { return true }
            return false
        }
        XCTAssertGreaterThan(pauseCommands.count, 0)
    }

    func testClientSendsResume() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("resumed")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.resume)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertEqual(data, "resumed")
    }

    func testClientSendsStep() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("stepped")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.step(count: 5))

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertEqual(data, "stepped")

        // Verify server received step command with correct count
        try await Task.sleep(nanoseconds: 50_000_000)
        let stepCommands = serverDelegate.receivedCommands.filter {
            if case .step(let count) = $0.command {
                return count == 5
            }
            return false
        }
        XCTAssertGreaterThan(stepCommands.count, 0)
    }

    func testClientSendsRead() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("data A9,00,8D,00,D4")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.read(address: 0x0600, count: 16))

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertTrue(data.hasPrefix("data"))

        // Verify server received read command
        try await Task.sleep(nanoseconds: 50_000_000)
        let readCommands = serverDelegate.receivedCommands.filter {
            if case .read(let addr, let count) = $0.command {
                return addr == 0x0600 && count == 16
            }
            return false
        }
        XCTAssertGreaterThan(readCommands.count, 0)
    }

    func testClientSendsWrite() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("written")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.write(address: 0x0600, data: [0xA9, 0x00]))

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertEqual(data, "written")

        // Verify server received write command
        try await Task.sleep(nanoseconds: 50_000_000)
        let writeCommands = serverDelegate.receivedCommands.filter {
            if case .write(let addr, let bytes) = $0.command {
                return addr == 0x0600 && bytes == [0xA9, 0x00]
            }
            return false
        }
        XCTAssertGreaterThan(writeCommands.count, 0)
    }

    func testClientSendsRegisters() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("A=$50 X=$00 Y=$00 S=$FF P=$30 PC=$0600")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.registers(modifications: nil))

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertTrue(data.contains("A=$"))
    }

    func testClientSendsModifyRegisters() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("modified")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.registers(modifications: [("A", 0x50), ("X", 0x10)]))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsBreakpointSet() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("breakpoint set at $0600")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.breakpointSet(address: 0x0600))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsBreakpointClear() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("breakpoint cleared")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.breakpointClear(address: 0x0600))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsBreakpointList() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("$0600\u{1E}$0700\u{1E}$0800")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.breakpointList)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        // Data should contain multi-line separator
        XCTAssertTrue(data.contains(CLIProtocolConstants.multiLineSeparator))
    }

    func testClientSendsMount() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("mounted")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.mount(drive: 1, path: "/path/to/disk.atr"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsUnmount() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("unmounted")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.unmount(drive: 1))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsDrives() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("D1: empty\u{1E}D2: empty")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.drives)

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertTrue(data.contains("D1:"))
    }

    func testClientSendsBoot() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("booted /path/to/game.atr")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.boot(path: "/path/to/game.atr"))

        guard case .ok(let data) = response else {
            XCTFail("Expected ok response")
            return
        }
        XCTAssertTrue(data.contains("booted"))

        // Verify server received boot command with correct path
        try await Task.sleep(nanoseconds: 50_000_000)
        let bootCommands = serverDelegate.receivedCommands.filter {
            if case .boot(let path) = $0.command {
                return path == "/path/to/game.atr"
            }
            return false
        }
        XCTAssertGreaterThan(bootCommands.count, 0)
    }

    func testClientSendsBootError() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .error("File not found: /nonexistent.atr")
        try await client.connect(to: testSocketPath)

        // Reset response after connect's ping
        serverDelegate.responseToReturn = .error("File not found: /nonexistent.atr")

        let response = try await client.send(.boot(path: "/nonexistent.atr"))

        guard case .error(let message) = response else {
            XCTFail("Expected error response")
            return
        }
        XCTAssertTrue(message.contains("File not found"))
    }

    func testClientSendsStateSave() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("saved")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.stateSave(path: "/path/to/state.sav"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsStateLoad() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("loaded")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.stateLoad(path: "/path/to/state.sav"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsScreenshot() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("/path/to/screenshot.png")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.screenshot(path: "/path/to/screenshot.png"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsInjectBasic() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("injected")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.injectBasic(base64Data: "SGVsbG8gV29ybGQh"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientSendsInjectKeys() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("injected")
        try await client.connect(to: testSocketPath)

        let response = try await client.send(.injectKeys(text: "HELLO\n"))

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testClientReceivesErrorResponse() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .error("Command failed")
        try await client.connect(to: testSocketPath)

        // Need to reset the response since connect uses ping
        serverDelegate.responseToReturn = .error("Command failed")

        let response = try await client.send(.pause)

        guard case .error(let message) = response else {
            XCTFail("Expected error response")
            return
        }
        XCTAssertEqual(message, "Command failed")
    }

    func testClientSendRaw() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        serverDelegate.responseToReturn = .ok("pong")
        try await client.connect(to: testSocketPath)

        let response = try await client.sendRaw("status")

        guard case .ok = response else {
            XCTFail("Expected ok response")
            return
        }
    }

    func testServerBroadcastsEvent() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        try await client.connect(to: testSocketPath)

        // Set up client delegate to receive events
        await MainActor.run {
            // Client delegate needs to be set on actor
        }

        // Broadcast an event
        await server.broadcastEvent(.breakpoint(address: 0x0600, a: 0x50, x: 0x10, y: 0x00, s: 0xFF, p: 0x30))

        // Give time for event to be received
        try await Task.sleep(nanoseconds: 200_000_000)

        // Note: Verifying event receipt would require the client delegate to be properly wired up
        // For now, this tests that broadcasting doesn't crash
    }

    func testClientDisconnect() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        try await client.connect(to: testSocketPath)
        var isConnected = await client.isConnected
        XCTAssertTrue(isConnected)

        await client.disconnect()
        isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }

    func testClientDisconnectTwice() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        try await client.connect(to: testSocketPath)

        await client.disconnect()
        await client.disconnect()  // Should not crash

        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }

    func testSendWhileDisconnected() async throws {
        let response = try? await client.send(.ping)
        XCTAssertNil(response)
    }

    func testConnectWhileAlreadyConnected() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        try await client.connect(to: testSocketPath)

        // Connecting again should throw
        do {
            try await client.connect(to: testSocketPath)
            XCTFail("Should throw when already connected")
        } catch let error as CLIProtocolError {
            guard case .connectionFailed = error else {
                XCTFail("Expected connectionFailed, got \(error)")
                return
            }
        }
    }

    func testMultipleClients() async throws {
        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Create multiple clients
        let client1 = CLISocketClient()
        let client2 = CLISocketClient()

        defer {
            Task { await client1.disconnect() }
            Task { await client2.disconnect() }
        }

        // Connect both clients
        try await client1.connect(to: testSocketPath)
        try await client2.connect(to: testSocketPath)

        let isConnected1 = await client1.isConnected
        let isConnected2 = await client2.isConnected

        XCTAssertTrue(isConnected1)
        XCTAssertTrue(isConnected2)

        // Both clients should be able to send commands
        serverDelegate.responseToReturn = .ok("pong")
        let response1 = try await client1.send(.ping)
        let response2 = try await client2.send(.ping)

        guard case .ok = response1, case .ok = response2 else {
            XCTFail("Both clients should receive ok responses")
            return
        }
    }
}

// =============================================================================
// MARK: - Command Formatting Tests
// =============================================================================

final class CLICommandFormattingTests: XCTestCase {
    // These tests verify that the client correctly formats commands for transmission

    func testFormatStepWithCount() async throws {
        // Set up server and client
        let testSocketPath = "/tmp/attic-fmt-\(UUID().uuidString.prefix(8)).sock"
        let server = CLISocketServer(socketPath: testSocketPath)
        let delegate = MockServerDelegate()
        delegate.responseToReturn = .ok("pong")
        await server.setDelegate(delegate)

        defer {
            Task {
                await server.stop()
                try? FileManager.default.removeItem(atPath: testSocketPath)
            }
        }

        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let client = CLISocketClient()
        defer { Task { await client.disconnect() } }

        try await client.connect(to: testSocketPath)

        // Send step with count
        delegate.responseToReturn = .ok("stepped")
        _ = try await client.send(.step(count: 10))

        // Verify server received correct command
        try await Task.sleep(nanoseconds: 50_000_000)
        let stepCommands = delegate.receivedCommands.filter {
            if case .step(let count) = $0.command {
                return count == 10
            }
            return false
        }
        XCTAssertGreaterThan(stepCommands.count, 0, "Server should receive step 10 command")
    }

    func testFormatResetCold() async throws {
        let testSocketPath = "/tmp/attic-fmt2-\(UUID().uuidString.prefix(8)).sock"
        let server = CLISocketServer(socketPath: testSocketPath)
        let delegate = MockServerDelegate()
        delegate.responseToReturn = .ok("pong")
        await server.setDelegate(delegate)

        defer {
            Task {
                await server.stop()
                try? FileManager.default.removeItem(atPath: testSocketPath)
            }
        }

        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let client = CLISocketClient()
        defer { Task { await client.disconnect() } }

        try await client.connect(to: testSocketPath)

        delegate.responseToReturn = .ok("reset")
        _ = try await client.send(.reset(cold: true))

        try await Task.sleep(nanoseconds: 50_000_000)
        let resetCommands = delegate.receivedCommands.filter {
            if case .reset(let cold) = $0.command {
                return cold == true
            }
            return false
        }
        XCTAssertGreaterThan(resetCommands.count, 0)
    }

    func testFormatResetWarm() async throws {
        let testSocketPath = "/tmp/attic-fmt3-\(UUID().uuidString.prefix(8)).sock"
        let server = CLISocketServer(socketPath: testSocketPath)
        let delegate = MockServerDelegate()
        delegate.responseToReturn = .ok("pong")
        await server.setDelegate(delegate)

        defer {
            Task {
                await server.stop()
                try? FileManager.default.removeItem(atPath: testSocketPath)
            }
        }

        try await server.start()
        try await Task.sleep(nanoseconds: 100_000_000)

        let client = CLISocketClient()
        defer { Task { await client.disconnect() } }

        try await client.connect(to: testSocketPath)

        delegate.responseToReturn = .ok("reset")
        _ = try await client.send(.reset(cold: false))

        try await Task.sleep(nanoseconds: 50_000_000)
        let resetCommands = delegate.receivedCommands.filter {
            if case .reset(let cold) = $0.command {
                return cold == false
            }
            return false
        }
        XCTAssertGreaterThan(resetCommands.count, 0)
    }
}
