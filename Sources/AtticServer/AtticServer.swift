// =============================================================================
// AtticServer.swift - Attic Emulator Server
// =============================================================================
//
// This is the standalone emulator server process that runs the Atari 800 XL
// emulation and broadcasts video frames and audio samples via the Attic
// Emulator Server Protocol (AESP).
//
// The server provides two protocol interfaces:
//
// 1. AESP (Binary Protocol) - For GUI/web clients
//    - Control (47800): Commands, status, memory access, input events
//    - Video (47801): Frame broadcasts to subscribed clients
//    - Audio (47802): Audio sample broadcasts to subscribed clients
//
// 2. CLI Protocol (Text Protocol) - For CLI/Emacs integration
//    - Unix socket at /tmp/attic-<pid>.sock
//    - Text-based commands for REPL interaction
//
// Usage:
//   AtticServer [options]
//
// Options:
//   --rom-path <path>    Path to ROM directory (default: auto-detect)
//   --control-port <n>   Control port (default: 47800)
//   --video-port <n>     Video port (default: 47801)
//   --audio-port <n>     Audio port (default: 47802)
//   --socket-path <p>    Unix socket path (default: /tmp/attic-<pid>.sock)
//   --no-cli-socket      Disable CLI socket server
//   --silent             Disable audio generation
//   --help               Show usage information
//
// Clients can connect using the AESPClient from the AtticProtocol module,
// or any implementation that speaks the AESP binary protocol.
//
// CLI clients connect via the Unix socket using the text protocol.
//
// =============================================================================

import Foundation
import AtticCore
import AtticProtocol

// MARK: - Server Configuration

/// Configuration parsed from command-line arguments.
struct ServerConfiguration {
    var romPath: URL?
    var controlPort: Int = AESPConstants.defaultControlPort
    var videoPort: Int = AESPConstants.defaultVideoPort
    var audioPort: Int = AESPConstants.defaultAudioPort
    var socketPath: String? = nil  // nil means use default /tmp/attic-<pid>.sock
    var enableCLISocket: Bool = true
    var silent: Bool = false
    var showHelp: Bool = false

    /// Parses configuration from command-line arguments.
    static func parse(arguments: [String]) -> ServerConfiguration {
        var config = ServerConfiguration()
        var index = 1  // Skip program name

        while index < arguments.count {
            let arg = arguments[index]

            switch arg {
            case "--rom-path":
                index += 1
                if index < arguments.count {
                    config.romPath = URL(fileURLWithPath: arguments[index])
                }

            case "--control-port":
                index += 1
                if index < arguments.count, let port = Int(arguments[index]) {
                    config.controlPort = port
                }

            case "--video-port":
                index += 1
                if index < arguments.count, let port = Int(arguments[index]) {
                    config.videoPort = port
                }

            case "--audio-port":
                index += 1
                if index < arguments.count, let port = Int(arguments[index]) {
                    config.audioPort = port
                }

            case "--socket-path":
                index += 1
                if index < arguments.count {
                    config.socketPath = arguments[index]
                }

            case "--no-cli-socket":
                config.enableCLISocket = false

            case "--silent":
                config.silent = true

            case "--help", "-h":
                config.showHelp = true

            default:
                print("Warning: Unknown argument: \(arg)")
            }

            index += 1
        }

        return config
    }

    /// Prints usage information.
    static func printUsage() {
        print("""
        Attic Emulator Server - Atari 800 XL Emulation via AESP

        Usage: AtticServer [options]

        Options:
          --rom-path <path>    Path to ROM directory containing ATARIXL.ROM and
                               ATARIBAS.ROM (default: auto-detect)
          --control-port <n>   Control port (default: 47800)
          --video-port <n>     Video port (default: 47801)
          --audio-port <n>     Audio port (default: 47802)
          --socket-path <p>    Unix socket path for CLI protocol
                               (default: /tmp/attic-<pid>.sock)
          --no-cli-socket      Disable CLI socket server
          --silent             Disable audio generation
          --help, -h           Show this help message

        The server broadcasts video frames and audio samples to connected clients.
        Use AESPClient to connect from Swift applications, or implement the AESP
        binary protocol for other languages.

        CLI clients can connect via the Unix socket using the text-based CLI protocol.

        Example:
          AtticServer --rom-path ~/ROMs --control-port 47800
        """)
    }
}

// MARK: - ROM Path Discovery

/// Finds the ROM directory by searching standard locations.
func findROMPath() -> URL? {
    let fileManager = FileManager.default

    // Search paths in order of preference
    let searchPaths: [URL] = [
        // Current working directory
        URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("Resources/ROM"),
        // User's home directory
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".attic/ROM"),
        // Source repo location (for development)
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/ROM"),
        // Standard macOS locations
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Attic/ROM"),
    ]

    for path in searchPaths {
        let osRom = path.appendingPathComponent("ATARIXL.ROM")
        if fileManager.fileExists(atPath: osRom.path) {
            return path
        }
    }

    print("ROM search paths tried:")
    for path in searchPaths {
        print("  - \(path.path)")
    }

    return nil
}

// MARK: - Server Delegate

/// Handles incoming AESP messages from clients.
final class ServerDelegate: AESPServerDelegate, @unchecked Sendable {
    /// Reference to the emulator engine.
    private let emulator: EmulatorEngine

    /// Lock for thread-safe access.
    private let lock = NSLock()

    /// Whether the server should continue running.
    var shouldRun: Bool = true

    init(emulator: EmulatorEngine) {
        self.emulator = emulator
    }

    func server(_ server: AESPServer, didReceiveMessage message: AESPMessage, from clientId: UUID) async {
        switch message.type {
        // Control messages
        case .pause:
            print("[Server] Pausing emulation (requested by \(clientId))")
            await emulator.pause()
            await server.sendMessage(.ack(for: .pause), to: clientId, channel: .control)

        case .resume:
            print("[Server] Resuming emulation (requested by \(clientId))")
            await emulator.resume()
            await server.sendMessage(.ack(for: .resume), to: clientId, channel: .control)

        case .reset:
            let cold = message.payload.first == 0x01
            print("[Server] Resetting emulation (cold=\(cold), requested by \(clientId))")
            await emulator.reset(cold: cold)
            await server.sendMessage(.ack(for: .reset), to: clientId, channel: .control)

        case .status:
            let state = await emulator.state
            let isRunning = state == .running
            var payload = Data()
            payload.append(isRunning ? 0x01 : 0x00)
            let response = AESPMessage(type: .status, payload: payload)
            await server.sendMessage(response, to: clientId, channel: .control)

        // Memory access
        case .memoryRead:
            if let (address, count) = message.parseMemoryReadRequest() {
                let bytes = await emulator.readMemoryBlock(at: address, count: Int(count))
                let response = AESPMessage(type: .memoryRead, payload: bytes)
                await server.sendMessage(response, to: clientId, channel: .control)
            }

        case .memoryWrite:
            if let (address, data) = message.parseMemoryWriteRequest() {
                await emulator.writeMemoryBlock(at: address, bytes: Array(data))
                await server.sendMessage(.ack(for: .memoryWrite), to: clientId, channel: .control)
            }

        // Input messages
        case .keyDown:
            if let (keyChar, keyCode, shift, control) = message.parseKeyPayload() {
                await emulator.pressKey(keyChar: keyChar, keyCode: keyCode, shift: shift, control: control)
            }

        case .keyUp:
            await emulator.releaseKey()

        case .joystick:
            if let (port, up, down, left, right, trigger) = message.parseJoystickPayload() {
                var direction: UInt8 = 0
                if up { direction |= 0x01 }
                if down { direction |= 0x02 }
                if left { direction |= 0x04 }
                if right { direction |= 0x08 }
                await emulator.setJoystick(port: Int(port), direction: direction, trigger: trigger)
            }

        case .consoleKeys:
            if let (start, select, option) = message.parseConsoleKeysPayload() {
                await emulator.setConsoleKeys(start: start, select: select, option: option)
            }

        default:
            print("[Server] Unhandled message type: \(message.type)")
        }
    }

    func server(_ server: AESPServer, clientDidConnect clientId: UUID, channel: AESPChannel) async {
        print("[Server] Client connected: \(clientId) on \(channel.rawValue)")
    }

    func server(_ server: AESPServer, clientDidDisconnect clientId: UUID, channel: AESPChannel) async {
        print("[Server] Client disconnected: \(clientId) from \(channel.rawValue)")
    }
}

// MARK: - CLI Socket Server Delegate

/// Handles incoming CLI protocol commands from CLI clients.
///
/// This delegate implements the text-based CLI protocol, translating CLI commands
/// into emulator operations and returning formatted responses.
final class CLIServerDelegate: CLISocketServerDelegate, @unchecked Sendable {
    /// Reference to the emulator engine.
    private let emulator: EmulatorEngine

    /// BASIC line handler for tokenization and memory injection.
    private let basicHandler: BASICLineHandler

    /// Reference to the CLI socket server for sending events.
    private weak var cliServer: CLISocketServer?

    /// Lock for thread-safe access.
    private let lock = NSLock()

    init(emulator: EmulatorEngine) {
        self.emulator = emulator
        self.basicHandler = BASICLineHandler(emulator: emulator)
    }

    /// Sets the CLI server reference for sending async events.
    func setServer(_ server: CLISocketServer) {
        cliServer = server
    }

    func server(
        _ server: CLISocketServer,
        didReceiveCommand command: CLICommand,
        from clientId: UUID
    ) async -> CLIResponse {
        switch command {
        // Connection commands
        case .ping:
            return .ok("pong")

        case .version:
            return .ok(CLIProtocolConstants.protocolVersion)

        case .quit:
            return .ok("goodbye")

        case .shutdown:
            // Signal shutdown (handled in main loop)
            return .ok("shutting down")

        // Emulator control
        case .pause:
            await emulator.pause()
            return .ok("paused")

        case .resume:
            await emulator.resume()
            return .ok("resumed")

        case .step(let count):
            // Execute frames (libatari800 steps by frames, not instructions)
            for _ in 0..<count {
                let result = await emulator.executeFrame()
                if result == .breakpoint {
                    let regs = await emulator.getRegisters()
                    return .ok("stepped \(formatRegisters(regs))\n* Breakpoint hit at $\(String(format: "%04X", regs.pc))")
                }
            }
            let regs = await emulator.getRegisters()
            return .ok("stepped \(formatRegisters(regs))")

        case .reset(let cold):
            await emulator.reset(cold: cold)
            return .ok("reset \(cold ? "cold" : "warm")")

        case .status:
            return await formatStatus()

        // Memory operations
        case .read(let address, let count):
            let bytes = await emulator.readMemoryBlock(at: address, count: Int(count))
            let hexBytes = bytes.map { String(format: "%02X", $0) }.joined(separator: ",")
            return .ok("data \(hexBytes)")

        case .write(let address, let data):
            await emulator.writeMemoryBlock(at: address, bytes: data)
            return .ok("written \(data.count)")

        case .registers(let modifications):
            if let mods = modifications {
                var regs = await emulator.getRegisters()
                for (regName, value) in mods {
                    switch regName.uppercased() {
                    case "A": regs.a = UInt8(value & 0xFF)
                    case "X": regs.x = UInt8(value & 0xFF)
                    case "Y": regs.y = UInt8(value & 0xFF)
                    case "S": regs.s = UInt8(value & 0xFF)
                    case "P": regs.p = UInt8(value & 0xFF)
                    case "PC": regs.pc = value
                    default: break
                    }
                }
                await emulator.setRegisters(regs)
            }
            let regs = await emulator.getRegisters()
            return .ok(formatRegisters(regs))

        // Breakpoints
        case .breakpointSet(let address):
            if await emulator.setBreakpoint(at: address) {
                return .ok("breakpoint set $\(String(format: "%04X", address))")
            } else {
                return .error("Breakpoint already set at $\(String(format: "%04X", address))")
            }

        case .breakpointClear(let address):
            if await emulator.clearBreakpoint(at: address) {
                return .ok("breakpoint cleared $\(String(format: "%04X", address))")
            } else {
                return .error("No breakpoint at $\(String(format: "%04X", address))")
            }

        case .breakpointClearAll:
            await emulator.clearAllBreakpoints()
            return .ok("breakpoints cleared")

        case .breakpointList:
            let bps = await emulator.getBreakpoints()
            if bps.isEmpty {
                return .ok("breakpoints (none)")
            }
            let bpStrs = bps.map { "$\(String(format: "%04X", $0))" }.joined(separator: ",")
            return .ok("breakpoints \(bpStrs)")

        // Disk operations
        case .mount(let drive, let path):
            // Check if file exists
            guard FileManager.default.fileExists(atPath: path) else {
                return .error("File not found '\(path)'")
            }
            if await emulator.mountDisk(drive: drive, path: path, readOnly: false) {
                return .ok("mounted \(drive) \(path)")
            } else {
                return .error("Failed to mount '\(path)'")
            }

        case .unmount(let drive):
            await emulator.unmountDisk(drive: drive)
            return .ok("unmounted \(drive)")

        case .drives:
            // TODO: Get mounted drives from emulator
            return .ok("drives (none)")

        // State management
        case .stateSave(let path):
            do {
                // Create minimal metadata for server-initiated saves
                // (no REPL mode or disk info available at server level)
                let metadata = StateMetadata.create(
                    replMode: .basic(variant: .atari),  // Default mode
                    mountedDisks: []
                )
                try await emulator.saveState(to: URL(fileURLWithPath: path), metadata: metadata)
                return .ok("state saved \(path)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .stateLoad(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                return .error("File not found '\(path)'")
            }
            do {
                // Clear breakpoints before loading (RAM contents will change)
                await emulator.clearAllBreakpoints()

                // Load state (metadata is returned but server doesn't use it)
                let metadata = try await emulator.loadState(from: URL(fileURLWithPath: path))
                return .ok("state loaded \(path) (from \(metadata.timestamp))")
            } catch {
                return .error(error.localizedDescription)
            }

        // Display
        case .screenshot(let path):
            // TODO: Implement screenshot capture
            let actualPath = path ?? "~/Desktop/Attic-\(Date()).png"
            return .ok("screenshot \(actualPath)")

        // BASIC injection
        case .injectBasic(let base64Data):
            // TODO: Implement BASIC injection
            guard Data(base64Encoded: base64Data) != nil else {
                return .error("Invalid base64 data")
            }
            return .ok("injected basic (not yet implemented)")

        case .injectKeys(let text):
            // TODO: Implement keyboard injection
            return .ok("injected keys \(text.count)")

        // Disassembly
        case .disassemble(let address, let lines):
            return await handleDisassemble(address: address, lines: lines)

        // Phase 11: Monitor mode commands (not fully implemented yet)
        case .assemble(let address):
            // Interactive assembly mode - not supported via CLI protocol
            return .error("Interactive assembly not supported via protocol. Use assembleLine for single instructions.")

        case .assembleLine(let address, let instruction):
            // Single-line assembly
            let assembler = Assembler()
            do {
                let result = try assembler.assembleLine(instruction, at: address)
                // Write bytes to memory
                for (offset, byte) in result.bytes.enumerated() {
                    await emulator.writeMemory(at: address &+ UInt16(offset), value: byte)
                }
                let bytesHex = result.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                return .ok("$\(String(format: "%04X", address)): \(bytesHex)")
            } catch {
                return .error("Assembly error: \(error)")
            }

        case .stepOver:
            // Step over (treat JSR as single step)
            let monitor = MonitorStepper(
                emulator: emulator,
                breakpoints: BreakpointManager()
            )
            let result = await monitor.stepOver()
            if !result.success, let msg = result.errorMessage {
                return .error(msg)
            } else if result.breakpointHit {
                return .ok("breakpoint at $\(String(format: "%04X", result.stoppedAt)) \(formatRegisters(result.registers))")
            } else {
                return .ok("stepped to $\(String(format: "%04X", result.stoppedAt)) \(formatRegisters(result.registers))")
            }

        case .runUntil(let address):
            // Run until address (set temp breakpoint and resume)
            let breakpointMgr = BreakpointManager()
            let memoryAdapter = EmulatorMemoryAdapter(emulator: emulator)
            await breakpointMgr.setTemporaryBreakpoint(at: address, memory: memoryAdapter)
            await emulator.resume()
            // Note: Actual stopping happens through normal execution
            return .ok("running until $\(String(format: "%04X", address))")

        case .memoryFill(let start, let end, let value):
            // Fill memory range with value
            guard end >= start else {
                return .error("End address must be >= start address")
            }
            var addr = start
            while addr <= end {
                await emulator.writeMemory(at: addr, value: value)
                if addr == 0xFFFF { break }  // Prevent overflow
                addr &+= 1
            }
            return .ok("filled $\(String(format: "%04X", start))-$\(String(format: "%04X", end)) with $\(String(format: "%02X", value))")

        // BASIC line entry and commands
        case .basicLine(let line):
            let result = await basicHandler.enterLine(line)
            if result.success {
                return .ok(result.message)
            } else {
                return .error(result.message)
            }

        case .basicNew:
            let result = await basicHandler.newProgram()
            if result.success {
                return .ok(result.message)
            } else {
                return .error(result.message)
            }

        case .basicRun:
            let result = await basicHandler.runProgram()
            if result.success {
                return .ok(result.message)
            } else {
                return .error(result.message)
            }

        case .basicList:
            // Use the detokenizer to list the program
            let listing = await basicHandler.listProgram(range: nil)
            if listing.isEmpty {
                return .ok("No program in memory")
            }
            // Split by newlines and use okMultiLine to properly format for CLI protocol
            let lines = listing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return .okMultiLine(lines)
        }
    }

    /// Handles the disassemble command.
    ///
    /// - Parameters:
    ///   - address: Starting address, or nil to use current PC.
    ///   - lines: Number of lines to disassemble, or nil for default (16).
    /// - Returns: CLI response with disassembly output.
    private func handleDisassemble(address: UInt16?, lines: Int?) async -> CLIResponse {
        // Get starting address (from parameter or current PC)
        let startAddress: UInt16
        if let addr = address {
            startAddress = addr
        } else {
            let regs = await emulator.getRegisters()
            startAddress = regs.pc
        }

        // Default to 16 lines
        let lineCount = lines ?? 16

        // Create disassembler with standard Atari labels
        let disasm = Disassembler(labels: AddressLabels.atariStandard)

        // Get memory bus from emulator for reading
        // We need to read bytes through the emulator's memory access
        // Since MemoryBus requires synchronous reads and emulator is async,
        // we read the needed bytes first
        let maxBytesNeeded = lineCount * 3  // Max 3 bytes per instruction
        let memoryBytes = await emulator.readMemoryBlock(at: startAddress, count: maxBytesNeeded)

        // Create an array-backed memory bus for the disassembler
        let memoryBus = ArrayMemoryBus(data: memoryBytes, baseAddress: startAddress)

        // Disassemble the range
        let instructions = disasm.disassembleRange(from: startAddress, lines: lineCount, memory: memoryBus)

        // Format output
        let outputLines = instructions.map { $0.formattedWithLabel }
        let output = outputLines.joined(separator: CLIProtocolConstants.multiLineSeparator)

        return .ok(output)
    }

    func server(_ server: CLISocketServer, clientDidConnect clientId: UUID) async {
        print("[CLISocket] Client connected: \(clientId)")
    }

    func server(_ server: CLISocketServer, clientDidDisconnect clientId: UUID) async {
        print("[CLISocket] Client disconnected: \(clientId)")
    }

    // MARK: - Helper Methods

    /// Formats CPU registers for response.
    private func formatRegisters(_ regs: CPURegisters) -> String {
        "A=$\(String(format: "%02X", regs.a)) X=$\(String(format: "%02X", regs.x)) Y=$\(String(format: "%02X", regs.y)) S=$\(String(format: "%02X", regs.s)) P=$\(String(format: "%02X", regs.p)) PC=$\(String(format: "%04X", regs.pc))"
    }

    /// Formats emulator status for response.
    private func formatStatus() async -> CLIResponse {
        let state = await emulator.state
        let regs = await emulator.getRegisters()
        let bps = await emulator.getBreakpoints()

        var status = ""
        switch state {
        case .running:
            status += "running"
        case .paused:
            status += "paused"
        case .breakpoint(let addr):
            status += "breakpoint $\(String(format: "%04X", addr))"
        case .uninitialized:
            status += "uninitialized"
        }

        status += " PC=$\(String(format: "%04X", regs.pc))"

        // TODO: Add disk mount status (D1=..., D2=..., etc.)
        status += " D1=(none) D2=(none)"

        if bps.isEmpty {
            status += " BP=(none)"
        } else {
            let bpStrs = bps.map { "$\(String(format: "%04X", $0))" }.joined(separator: ",")
            status += " BP=\(bpStrs)"
        }

        return .ok("status \(status)")
    }
}

// MARK: - Main Entry Point

@main
struct AtticServer {

    static func main() async {
        // Parse command-line arguments
        let config = ServerConfiguration.parse(arguments: CommandLine.arguments)

        if config.showHelp {
            ServerConfiguration.printUsage()
            return
        }

        // Disable output buffering for immediate feedback
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        print("=== Attic Emulator Server ===")
        print("Starting server...")

        // Find ROM path
        let romPath: URL
        if let path = config.romPath {
            romPath = path
        } else if let path = findROMPath() {
            romPath = path
        } else {
            print("Error: Could not find ROM directory.")
            print("Please specify --rom-path or place ROMs in one of the search paths.")
            return
        }

        print("Using ROMs from: \(romPath.path)")

        // Initialize emulator
        let emulator = EmulatorEngine()

        do {
            try await emulator.initialize(romPath: romPath)
            // Run cold reset to complete boot sequence and initialize BASIC memory.
            // Without this, BASIC pointers (MEMTOP, RUNSTK, etc.) are uninitialized,
            // causing "Out of memory" errors when entering BASIC lines.
            await emulator.reset(cold: true)
            print("Emulator initialized successfully")
        } catch {
            print("Error initializing emulator: \(error)")
            return
        }

        // Create server configuration
        let serverConfig = AESPServerConfiguration(
            controlPort: config.controlPort,
            videoPort: config.videoPort,
            audioPort: config.audioPort
        )

        // Create and start AESP server
        let server = AESPServer(configuration: serverConfig)
        let delegate = ServerDelegate(emulator: emulator)
        await server.setDelegate(delegate)

        do {
            try await server.start()
            print("AESP server listening on:")
            print("  Control: localhost:\(config.controlPort)")
            print("  Video:   localhost:\(config.videoPort)")
            print("  Audio:   localhost:\(config.audioPort)")
        } catch {
            print("Error starting AESP server: \(error)")
            return
        }

        // Create and start CLI socket server (if enabled)
        var cliServer: CLISocketServer?
        var cliDelegate: CLIServerDelegate?

        if config.enableCLISocket {
            let socketPath = config.socketPath ?? CLIProtocolConstants.currentSocketPath
            cliServer = CLISocketServer(socketPath: socketPath)
            cliDelegate = CLIServerDelegate(emulator: emulator)

            if let server = cliServer, let del = cliDelegate {
                del.setServer(server)
                await server.setDelegate(del)

                do {
                    try await server.start()
                    print("CLI socket server listening on:")
                    print("  Socket: \(socketPath)")
                } catch {
                    print("Warning: Failed to start CLI socket server: \(error)")
                    // Continue without CLI socket - AESP is still available
                    cliServer = nil
                    cliDelegate = nil
                }
            }
        }

        // Start emulation
        await emulator.resume()
        print("Emulation started")
        print("Press Ctrl+C to stop")

        // Set up signal handler for graceful shutdown
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigintSource.setEventHandler {
            print("\nShutting down...")
            delegate.shouldRun = false
        }
        sigintSource.resume()

        // Main emulation loop with proper frame timing
        // We measure elapsed time and only sleep for the remainder to maintain 60fps
        let targetFrameTime: UInt64 = 16_666_667  // ~60fps in nanoseconds
        var nextFrameTime = DispatchTime.now().uptimeNanoseconds + targetFrameTime

        while delegate.shouldRun {
            // Execute one frame
            let result = await emulator.executeFrame()

            // Check for errors
            if result == .notInitialized || result == .error {
                print("Emulator error: \(result)")
                break
            }

            // Get frame buffer and broadcast to video clients
            let frameBuffer = await emulator.getFrameBuffer()
            await server.broadcastFrame(frameBuffer)

            // Get audio samples and broadcast to audio clients
            if !config.silent {
                let audioSamples = await emulator.getAudioSamples()
                if !audioSamples.isEmpty {
                    await server.broadcastAudio(audioSamples)
                }
            }

            // Calculate remaining time until next frame
            let now = DispatchTime.now().uptimeNanoseconds
            if now < nextFrameTime {
                // Sleep only for the remaining time
                let sleepTime = nextFrameTime - now
                try? await Task.sleep(nanoseconds: sleepTime)
            } else {
                // Even when running behind schedule, yield to prevent actor starvation.
                // Without this, CLI commands (like pause) that need emulator actor access
                // could be starved because the main loop continuously makes actor calls.
                await Task.yield()
            }
            // Schedule next frame (even if we're behind, this keeps us on pace)
            nextFrameTime += targetFrameTime
        }

        // Shutdown
        print("Stopping servers...")

        // Stop CLI socket server first
        if let cliServer = cliServer {
            await cliServer.stop()
        }

        // Stop AESP server
        await server.stop()

        // Shutdown emulator
        await emulator.pause()
        await emulator.shutdown()
        print("Server stopped")
    }
}

// MARK: - Server Extension

extension AESPServer {
    /// Sets the server delegate.
    func setDelegate(_ delegate: AESPServerDelegate) {
        self.delegate = delegate
    }
}
