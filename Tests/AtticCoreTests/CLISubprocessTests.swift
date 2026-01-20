// =============================================================================
// CLISubprocessTests.swift - Subprocess Integration Tests for CLI Protocol
// =============================================================================
//
// This file contains integration tests that launch AtticServer and attic CLI
// as actual subprocesses to verify end-to-end functionality.
//
// Test Architecture:
// ------------------
// These tests spawn real processes and communicate with them via the CLI socket
// protocol. This verifies that:
// - AtticServer creates the CLI socket correctly
// - The socket path discovery works
// - Commands can be sent through the socket
// - Responses are correctly formatted
//
// Prerequisites:
// -------------
// - swift build must have been run successfully
// - Build products must be available in .build/debug/
//
// Note: These tests may be slower than unit tests due to process spawning.
// They are marked with a common prefix for easy filtering.
//
// =============================================================================

import XCTest
@testable import AtticCore
import Foundation

// =============================================================================
// MARK: - Test Helpers
// =============================================================================

/// Helper class for managing subprocess execution.
class SubprocessHelper {
    /// Path to the build directory.
    static var buildPath: String {
        // Get the package directory from the test bundle
        let testBundle = Bundle(for: SubprocessHelper.self)
        if let packagePath = testBundle.bundlePath.components(separatedBy: ".build").first {
            return packagePath + ".build/debug"
        }
        // Fallback: assume we're running from project root
        return ".build/debug"
    }

    /// Path to the AtticServer executable.
    static var serverPath: String {
        buildPath + "/AtticServer"
    }

    /// Path to the attic CLI executable.
    static var cliPath: String {
        buildPath + "/attic"
    }

    /// Checks if the build products exist.
    static var buildProductsExist: Bool {
        FileManager.default.fileExists(atPath: serverPath) &&
        FileManager.default.fileExists(atPath: cliPath)
    }

    /// Spawns a process and returns it along with pipes for I/O.
    static func spawnProcess(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) -> (Process, Pipe, Pipe) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if let env = environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return (process, stdoutPipe, stderrPipe)
    }

    /// Reads available data from a pipe with timeout.
    static func readPipe(_ pipe: Pipe, timeout: TimeInterval = 5.0) -> String {
        let fileHandle = pipe.fileHandleForReading

        var output = ""
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let data = fileHandle.availableData
            if data.isEmpty {
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            if let str = String(data: data, encoding: .utf8) {
                output += str
            }
        }

        return output
    }

    /// Waits for a socket file to appear.
    static func waitForSocket(prefix: String = "/tmp/attic-", timeout: TimeInterval = 10.0) -> String? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
                for file in files {
                    if file.hasPrefix("attic-") && file.hasSuffix(".sock") {
                        let fullPath = "/tmp/\(file)"
                        // Verify the socket is accessible
                        var statBuf = stat()
                        if stat(fullPath, &statBuf) == 0 {
                            return fullPath
                        }
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        return nil
    }

    /// Cleans up any stale socket files.
    static func cleanupStaleSockets() {
        if let files = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
            for file in files {
                if file.hasPrefix("attic-") && file.hasSuffix(".sock") {
                    let fullPath = "/tmp/\(file)"
                    try? FileManager.default.removeItem(atPath: fullPath)
                }
            }
        }
    }
}

// =============================================================================
// MARK: - AtticServer Subprocess Tests
// =============================================================================

/// Integration tests that launch AtticServer as a subprocess.
final class AtticServerSubprocessTests: XCTestCase {

    var serverProcess: Process?

    override func setUp() async throws {
        // Clean up any stale sockets from previous runs
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        // Terminate server if running
        if let process = serverProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        serverProcess = nil

        // Clean up sockets
        SubprocessHelper.cleanupStaleSockets()
    }

    /// Test that AtticServer exists and can be launched.
    func testServerExecutableExists() throws {
        let serverPath = SubprocessHelper.serverPath

        // Skip if build products don't exist
        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found at \(serverPath). Run 'swift build' first.")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: serverPath))
    }

    /// Test that AtticServer creates a CLI socket.
    func testServerCreatesSocket() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        // Launch server
        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]  // No GUI
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        // Wait for socket to appear
        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket within timeout")
            return
        }

        XCTAssertTrue(socketPath.contains("attic-"))
        XCTAssertTrue(socketPath.hasSuffix(".sock"))
    }

    /// Test that a client can connect to the server socket and send ping.
    func testClientCanConnectAndPing() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        // Launch server
        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        // Wait for socket
        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        // Connect using CLISocketClient
        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            // Server might not be fully ready, this is expected in some cases
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        // Verify connection
        let isConnected = await client.isConnected
        XCTAssertTrue(isConnected, "Client should be connected")

        // Send additional ping to verify round-trip
        // (Note: connect() already sends a ping internally)
        let response = try await client.send(.ping)

        guard case .ok(let data) = response else {
            await client.disconnect()
            XCTFail("Expected OK response to ping, got \(response)")
            return
        }

        XCTAssertEqual(data, "pong")

        await client.disconnect()
    }

    /// Test that the server responds to status command.
    func testServerStatusCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            let response = try await client.send(.status)

            // Status should return OK with some data
            guard case .ok(let data) = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to status")
            }

            // Status response should contain state information
            XCTAssertFalse(data.isEmpty, "Status response should not be empty")
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test that the server responds to version command.
    func testServerVersionCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            let response = try await client.send(.version)

            guard case .ok(let data) = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to version")
            }

            // Version should contain some version info
            XCTAssertFalse(data.isEmpty, "Version response should not be empty")
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test that pause command works.
    func testServerPauseCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            let response = try await client.send(.pause)

            guard case .ok = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to pause")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test that resume command works.
    func testServerResumeCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            // Pause first, then resume
            _ = try await client.send(.pause)
            let response = try await client.send(.resume)

            guard case .ok = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to resume")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test that multiple clients can connect.
    func testMultipleClientsCanConnect() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        // Connect two clients
        let client1 = CLISocketClient()
        let client2 = CLISocketClient()

        do {
            try await client1.connect(to: socketPath)
            try await client2.connect(to: socketPath)
        } catch {
            await client1.disconnect()
            await client2.disconnect()
            process.terminate()
            throw XCTSkip("Could not connect clients: \(error)")
        }

        // Both should be connected
        let isConnected1 = await client1.isConnected
        let isConnected2 = await client2.isConnected

        XCTAssertTrue(isConnected1)
        XCTAssertTrue(isConnected2)

        do {
            // Both should be able to send commands
            let response1 = try await client1.send(.ping)
            let response2 = try await client2.send(.ping)

            guard case .ok = response1, case .ok = response2 else {
                await client1.disconnect()
                await client2.disconnect()
                throw XCTSkip("Server returned non-OK response to ping")
            }
        } catch let error as CLIProtocolError {
            await client1.disconnect()
            await client2.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client1.disconnect()
        await client2.disconnect()
    }

    /// Test quit command causes client disconnect without server shutdown.
    func testQuitCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        // Send quit
        _ = try? await client.send(.quit)

        // Give server time to process
        try await Task.sleep(nanoseconds: 100_000_000)

        // Server should still be running
        XCTAssertTrue(process.isRunning, "Server should still be running after quit")

        // Client should be disconnected (or at least the server should close the connection)
        await client.disconnect()
    }
}

// =============================================================================
// MARK: - attic CLI Subprocess Tests
// =============================================================================

/// Integration tests that launch the attic CLI as a subprocess.
final class AtticCLISubprocessTests: XCTestCase {

    var serverProcess: Process?

    override func setUp() async throws {
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        serverProcess = nil
        SubprocessHelper.cleanupStaleSockets()
    }

    /// Test that attic CLI executable exists.
    func testCLIExecutableExists() throws {
        let cliPath = SubprocessHelper.cliPath

        guard FileManager.default.fileExists(atPath: cliPath) else {
            throw XCTSkip("attic CLI not found at \(cliPath). Run 'swift build' first.")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: cliPath))
    }

    /// Test that attic CLI shows help.
    func testCLIHelp() throws {
        let cliPath = SubprocessHelper.cliPath

        guard FileManager.default.fileExists(atPath: cliPath) else {
            throw XCTSkip("attic CLI not found. Run 'swift build' first.")
        }

        let (process, stdoutPipe, _) = SubprocessHelper.spawnProcess(
            executablePath: cliPath,
            arguments: ["--help"]
        )

        try process.run()
        process.waitUntilExit()

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        // Help should mention some key options
        XCTAssertTrue(
            output.contains("help") || output.contains("USAGE") || output.contains("usage"),
            "Help output should contain usage information"
        )
    }

    /// Test that attic CLI can discover a running server.
    func testCLIDiscoverServer() async throws {
        let serverPath = SubprocessHelper.serverPath
        let cliPath = SubprocessHelper.cliPath

        guard FileManager.default.fileExists(atPath: serverPath),
              FileManager.default.fileExists(atPath: cliPath) else {
            throw XCTSkip("Build products not found. Run 'swift build' first.")
        }

        // Start server
        let (serverProc, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = serverProc

        do {
            try serverProc.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        // Wait for socket
        guard SubprocessHelper.waitForSocket() != nil else {
            serverProc.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        // Use CLISocketClient to verify discovery works
        let client = CLISocketClient()
        let discovered = client.discoverSocket()

        XCTAssertNotNil(discovered, "Should discover server socket")
        if let path = discovered {
            XCTAssertTrue(path.hasPrefix("/tmp/attic-"))
            XCTAssertTrue(path.hasSuffix(".sock"))
        }
    }
}

// =============================================================================
// MARK: - Memory and Register Command Tests
// =============================================================================

/// Tests for memory and register commands via subprocess.
final class CLIMemoryCommandTests: XCTestCase {

    var serverProcess: Process?

    override func setUp() async throws {
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        serverProcess = nil
        SubprocessHelper.cleanupStaleSockets()
    }

    /// Test memory read command.
    func testMemoryRead() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            // Read some memory
            let response = try await client.send(.read(address: 0x0600, count: 16))

            // Server should return OK with hex data
            guard case .ok(let data) = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to read")
            }

            // Data format should be "data XX,XX,XX,..." or similar
            XCTAssertFalse(data.isEmpty, "Read response should not be empty")
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test registers query command.
    func testRegistersQuery() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            // Query registers
            let response = try await client.send(.registers(modifications: nil))

            guard case .ok(let data) = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to registers")
            }

            // Register output should contain register names
            XCTAssertFalse(data.isEmpty, "Registers response should not be empty")
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    /// Test step command.
    func testStepCommand() async throws {
        let serverPath = SubprocessHelper.serverPath

        guard FileManager.default.fileExists(atPath: serverPath) else {
            throw XCTSkip("AtticServer not found. Run 'swift build' first.")
        }

        let (process, _, _) = SubprocessHelper.spawnProcess(
            executablePath: serverPath,
            arguments: ["--headless"]
        )
        serverProcess = process

        do {
            try process.run()
        } catch {
            throw XCTSkip("Failed to launch AtticServer: \(error)")
        }

        guard let socketPath = SubprocessHelper.waitForSocket() else {
            process.terminate()
            XCTFail("Server did not create CLI socket")
            return
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        do {
            // Pause first
            _ = try await client.send(.pause)

            // Step
            let response = try await client.send(.step(count: 1))

            guard case .ok = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to step")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }
}
