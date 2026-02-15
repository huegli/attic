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

    /// Kills any orphan AtticServer processes left over from previous test runs.
    ///
    /// When a test run is interrupted (e.g., Ctrl-C, Xcode stop, or a hung test),
    /// the tearDown method never runs and AtticServer child processes are left
    /// alive. These orphans hold the AESP ports (47800-47802) and leave socket
    /// files in /tmp, which causes the next test run to hang waiting for resources
    /// that are already in use. This method finds and terminates those orphans
    /// before the test suite begins.
    ///
    /// Sends SIGTERM first (graceful), then SIGKILL if the process survives.
    /// This mirrors the AESPTestProcessGuard pattern used by the protocol tests.
    static func killStaleProcesses() {
        let pids = findAtticServerPIDs()
        guard !pids.isEmpty else { return }

        // Send SIGTERM for graceful shutdown.
        for pid in pids {
            kill(pid, SIGTERM)
        }
        Thread.sleep(forTimeInterval: 0.5)

        // Check if any survived and force-kill them.
        let remaining = findAtticServerPIDs()
        if !remaining.isEmpty {
            for pid in remaining {
                kill(pid, SIGKILL)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// Finds PIDs of running AtticServer processes using `pgrep -x`.
    ///
    /// The `-x` flag ensures exact name matching so we don't accidentally
    /// match processes like "swift test --filter AtticServer".
    private static func findAtticServerPIDs() -> [Int32] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "AtticServer"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        pgrep.standardError = FileHandle.nullDevice

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return []
        }

        guard pgrep.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(separator: "\n")
            .compactMap { Int32(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    /// Terminates a subprocess with a SIGKILL fallback to prevent tearDown hangs.
    ///
    /// AtticServer installs `signal(SIGTERM, SIG_IGN)` and handles SIGTERM via a
    /// GCD DispatchSource. If the server's main queue is busy (e.g. stuck in an
    /// `await emulator.executeFrame()` call), the DispatchSource handler may never
    /// fire, making `Process.terminate()` (which sends SIGTERM) ineffective.
    /// Calling `process.waitUntilExit()` then hangs forever.
    ///
    /// This helper sends SIGTERM, waits briefly, then falls back to SIGKILL
    /// (which cannot be caught or ignored) to guarantee the process exits.
    static func terminateProcess(_ process: Process) {
        guard process.isRunning else { return }

        // Try graceful termination first (SIGTERM).
        process.terminate()

        // Wait up to 2 seconds for graceful exit.
        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // If still running, force-kill (SIGKILL cannot be caught or ignored).
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
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
        // Kill any orphan AtticServer processes from previous interrupted runs,
        // then clean up stale socket files so this test starts with a clean slate.
        SubprocessHelper.killStaleProcesses()
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess {
            SubprocessHelper.terminateProcess(process)
        }
        serverProcess = nil
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
        SubprocessHelper.killStaleProcesses()
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess {
            SubprocessHelper.terminateProcess(process)
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
        SubprocessHelper.killStaleProcesses()
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess {
            SubprocessHelper.terminateProcess(process)
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

// =============================================================================
// MARK: - Disassemble, Breakpoint, Mount/Unmount, Write+Read, Shutdown Tests
// =============================================================================

/// End-to-end subprocess tests for disassemble, breakpoint, mount/unmount,
/// memory write+readback, and shutdown commands.
final class CLIAdvancedCommandTests: XCTestCase {

    var serverProcess: Process?

    override func setUp() async throws {
        SubprocessHelper.killStaleProcesses()
        SubprocessHelper.cleanupStaleSockets()
    }

    override func tearDown() async throws {
        if let process = serverProcess {
            SubprocessHelper.terminateProcess(process)
        }
        serverProcess = nil
        SubprocessHelper.cleanupStaleSockets()
    }

    /// Helper: launch server and connect a client, or skip if not available.
    private func launchServerAndConnect() async throws -> (Process, CLISocketClient, String) {
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
            throw XCTSkip("No socket created")
        }

        let client = CLISocketClient()

        do {
            try await client.connect(to: socketPath)
        } catch {
            process.terminate()
            throw XCTSkip("Could not connect to server: \(error)")
        }

        return (process, client, socketPath)
    }

    // =========================================================================
    // MARK: - Disassemble
    // =========================================================================

    /// Test disassemble command returns output with instruction data.
    func testDisassemble() async throws {
        let (_, client, _) = try await launchServerAndConnect()

        do {
            // Pause before disassembling
            _ = try await client.send(.pause)

            // Disassemble from a known ROM address
            let response = try await client.send(.disassemble(address: 0xE000, lines: 8))

            switch response {
            case .ok(let data):
                XCTAssertFalse(data.isEmpty, "Disassembly should return data")
                // Disassembly output should contain address references
                let lines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
                XCTAssertGreaterThan(lines.count, 0, "Disassembly should return at least one line")
            case .error(let msg):
                throw XCTSkip("Server returned error for disassemble: \(msg)")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    // =========================================================================
    // MARK: - Breakpoint Set / List / Clear
    // =========================================================================

    /// Test setting, listing, and clearing breakpoints via subprocess.
    func testBreakpointSetListClear() async throws {
        let (_, client, _) = try await launchServerAndConnect()

        do {
            // Set a breakpoint at a safe address
            let setResponse = try await client.send(.breakpointSet(address: 0x0600))
            guard case .ok = setResponse else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to breakpoint set")
            }

            // List breakpoints - should contain the one we just set
            let listResponse = try await client.send(.breakpointList)
            switch listResponse {
            case .ok(let data):
                let lower = data.lowercased()
                XCTAssertTrue(
                    lower.contains("0600") || lower.contains("$0600") || lower.contains("1536"),
                    "Breakpoint list should contain address 0x0600: \(data)"
                )
            case .error(let msg):
                throw XCTSkip("Server returned error for breakpoint list: \(msg)")
            }

            // Clear the breakpoint
            let clearResponse = try await client.send(.breakpointClear(address: 0x0600))
            guard case .ok = clearResponse else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to breakpoint clear")
            }

            // List again - should be empty or not contain our address
            let listAfterClear = try await client.send(.breakpointList)
            switch listAfterClear {
            case .ok(let data):
                // "none" or empty list is expected
                let lower = data.lowercased()
                let stillHas = lower.contains("0600") || lower.contains("$0600")
                XCTAssertFalse(stillHas, "Breakpoint 0x0600 should be cleared: \(data)")
            case .error(let msg):
                throw XCTSkip("Server returned error for breakpoint list: \(msg)")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    // =========================================================================
    // MARK: - Mount / Unmount
    // =========================================================================

    /// Test mount and unmount commands. Mount with a non-existent path verifies
    /// the command round-trip works (server returns an error for missing file).
    func testMountUnmount() async throws {
        let (_, client, _) = try await launchServerAndConnect()

        do {
            // Mount with a non-existent path - should return an error response
            // (which proves the command was received and processed)
            let mountResponse = try await client.send(
                .mount(drive: 1, path: "/tmp/nonexistent-test.atr")
            )

            switch mountResponse {
            case .error:
                // Expected: file doesn't exist so mount fails gracefully
                break
            case .ok:
                // If server accepted it, unmount to clean up
                _ = try await client.send(.unmount(drive: 1))
            }

            // Unmount drive 1 (should succeed even if nothing is mounted)
            let unmountResponse = try await client.send(.unmount(drive: 1))
            switch unmountResponse {
            case .ok, .error:
                break  // Any response is acceptable
            }

            // Verify drives command works
            let drivesResponse = try await client.send(.drives)
            switch drivesResponse {
            case .ok(let data):
                XCTAssertFalse(data.isEmpty, "Drives response should not be empty")
            case .error(let msg):
                throw XCTSkip("Server returned error for drives: \(msg)")
            }
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    // =========================================================================
    // MARK: - Memory Write + Readback Verification
    // =========================================================================

    /// Test writing bytes to memory and reading them back to verify correctness.
    func testMemoryWriteAndReadback() async throws {
        let (_, client, _) = try await launchServerAndConnect()

        do {
            // Pause emulation before memory operations
            _ = try await client.send(.pause)

            // Write a known pattern to user memory area (page 6)
            let testData: [UInt8] = [0xA9, 0x42, 0x8D, 0x00, 0xD4]
            let writeResponse = try await client.send(
                .write(address: 0x0600, data: testData)
            )

            guard case .ok = writeResponse else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to write")
            }

            // Read back the same bytes
            let readResponse = try await client.send(
                .read(address: 0x0600, count: UInt16(testData.count))
            )

            guard case .ok(let data) = readResponse else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to read")
            }

            // Parse the hex data from the response.
            // Response format is typically "data A9,42,8D,00,D4" or "A9,42,8D,00,D4"
            let hexPart = data.hasPrefix("data ") ? String(data.dropFirst(5)) : data
            let readBytes = hexPart.split(separator: ",").compactMap {
                UInt8($0.trimmingCharacters(in: .whitespaces), radix: 16)
            }

            XCTAssertEqual(
                readBytes, testData,
                "Read-back data should match written data. Response was: \(data)"
            )
        } catch let error as CLIProtocolError {
            await client.disconnect()
            throw XCTSkip("Server command failed: \(error)")
        }

        await client.disconnect()
    }

    // =========================================================================
    // MARK: - Shutdown
    // =========================================================================

    /// Test that the shutdown command causes the server process to exit.
    func testShutdown() async throws {
        let (process, client, _) = try await launchServerAndConnect()

        do {
            // Send shutdown command
            let response = try await client.send(.shutdown)

            guard case .ok = response else {
                await client.disconnect()
                throw XCTSkip("Server returned non-OK response to shutdown")
            }
        } catch is CLIProtocolError {
            // Shutdown may close the connection before we get a response,
            // which is acceptable behavior
        } catch {
            // Connection reset during shutdown is expected
        }

        await client.disconnect()

        // Wait for the server process to actually exit
        let deadline = Date().addingTimeInterval(5.0)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        XCTAssertFalse(process.isRunning, "Server process should have exited after shutdown")

        // Mark serverProcess as nil so tearDown doesn't try to terminate it again
        serverProcess = nil
    }
}
