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
//    - Control (47800): Commands, status, input events
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
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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
///
/// When running inside an .app bundle, the ROMs are in Contents/Resources/ROM/.
/// The executable lives at Contents/MacOS/AtticServer, so we navigate up to
/// Contents/ and then into Resources/ROM/. This is checked first so bundled
/// ROMs take priority.
func findROMPath() -> URL? {
    let fileManager = FileManager.default

    // Path to the running executable (e.g. .../Attic.app/Contents/MacOS/AtticServer)
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardized

    // Search paths in order of preference
    var searchPaths: [URL] = [
        // App bundle: Contents/MacOS/../Resources/ROM
        executableURL
            .deletingLastPathComponent()           // Contents/MacOS/
            .deletingLastPathComponent()           // Contents/
            .appendingPathComponent("Resources/ROM"),
        // Adjacent to executable (for non-bundle installs)
        executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("ROM"),
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

    // Also check Bundle.main.resourceURL (works when loaded as a bundle)
    if let bundleROM = Bundle.main.resourceURL?.appendingPathComponent("ROM") {
        searchPaths.insert(bundleROM, at: 0)
    }

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

    /// Disk manager for querying mounted drives.
    /// Shared with CLIServerDelegate so both AESP and CLI handlers see
    /// the same disk state.
    var diskManager: DiskManager?

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

        case .bootFile:
            if let filePath = message.parseBootFileRequest() {
                print("[Server] Boot file: \(filePath) (requested by \(clientId))")
                let result = await emulator.bootFile(filePath)
                if result.success, let dm = diskManager {
                    // libatari800_reboot_with_file() mounts disk images on D1.
                    // Tell DiskManager so listDrives() reports the booted disk.
                    // For non-disk files (XEX, BAS, etc.) this silently does nothing.
                    await dm.trackBootedDisk(drive: 1, path: filePath)
                }
                let response = AESPMessage.bootFileResponse(
                    success: result.success,
                    message: result.success ? "Booted \(filePath)" : (result.errorMessage ?? "Unknown error")
                )
                await server.sendMessage(response, to: clientId, channel: .control)
            } else {
                await server.sendMessage(
                    .error(code: 0x01, message: "Invalid boot file request"),
                    to: clientId, channel: .control
                )
            }

        case .status:
            let state = await emulator.state
            let isRunning = state == .running
            // Build mounted drives list from disk manager (if available)
            var mountedDrives: [(drive: Int, filename: String)] = []
            if let dm = diskManager {
                let drives = await dm.listDrives()
                for driveStatus in drives where driveStatus.mounted {
                    let filename = driveStatus.path.map {
                        URL(fileURLWithPath: $0).lastPathComponent
                    } ?? "?"
                    mountedDrives.append((drive: driveStatus.drive, filename: filename))
                }
            }
            let response = AESPMessage.statusResponse(
                isRunning: isRunning,
                mountedDrives: mountedDrives
            )
            await server.sendMessage(response, to: clientId, channel: .control)

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
///
/// Disk operations (mount, unmount, drives) go through DiskManager, which
/// coordinates with both the emulator's C library and Swift-side ATR parsing.
/// This ensures that disk state is always consistent between libatari800 and
/// the REPL file system view.
final class CLIServerDelegate: CLISocketServerDelegate, @unchecked Sendable {
    /// Reference to the emulator engine.
    private let emulator: EmulatorEngine

    /// Disk manager — the single API for all disk mount/unmount operations.
    /// Coordinates with EmulatorEngine so that libatari800 and Swift-side
    /// file system state stay in sync. Exposed as internal so the AESP
    /// ServerDelegate can share the same instance.
    let diskManager: DiskManager

    /// BASIC line handler for tokenization and memory injection.
    private let basicHandler: BASICLineHandler

    /// Reference to the CLI socket server for sending events.
    private weak var cliServer: CLISocketServer?

    /// Callback to signal server shutdown.
    /// Called when the .shutdown command is received.
    var onShutdown: (() -> Void)?

    /// Lock for thread-safe access.
    private let lock = NSLock()

    /// Tracks active interactive assembly sessions per connected CLI client.
    /// Each session holds an `InteractiveAssembler` that auto-advances the
    /// address and a record of the starting address and total bytes written.
    private var assemblySessions: [UUID: AssemblySession] = [:]

    /// State for an active interactive assembly session.
    private struct AssemblySession {
        let assembler: InteractiveAssembler
        let startAddress: UInt16
        var totalBytes: Int = 0
    }

    init(emulator: EmulatorEngine) {
        self.emulator = emulator
        self.diskManager = DiskManager(emulator: emulator)
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
            // Signal shutdown to main loop via callback
            onShutdown?()
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

        case .boot(let path):
            // Validate file exists on the server side
            guard FileManager.default.fileExists(atPath: path) else {
                return .error("File not found '\(path)'")
            }
            let result = await emulator.bootFile(path)
            if result.success {
                // libatari800_reboot_with_file() mounts disk images on D1.
                // Tell DiskManager so listDrives() reports the booted disk.
                await diskManager.trackBootedDisk(drive: 1, path: path)
                return .ok("booted \(path)")
            } else {
                return .error(result.errorMessage ?? "Boot failed for '\(path)'")
            }

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

        // Disk operations — all go through DiskManager which coordinates
        // with EmulatorEngine so libatari800 and Swift-side state stay in sync.
        case .mount(let drive, let path):
            do {
                let info = try await diskManager.mount(drive: drive, path: path)
                return .ok("mounted \(drive) \(info.filename) (\(info.diskType.shortName), \(info.fileCount) files, \(info.freeSectors) free)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .unmount(let drive):
            do {
                try await diskManager.unmount(drive: drive)
                return .ok("unmounted \(drive)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .drives:
            let drives = await diskManager.listDrives()
            let mountedDrives = drives.filter { $0.mounted }
            if mountedDrives.isEmpty {
                return .ok("drives (none)")
            }
            let lines = mountedDrives.map { $0.displayString }
            return .okMultiLine(lines)

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
            return await handleScreenshot(path: path)

        case .screenText(let atascii):
            return await handleScreenText(atascii: atascii)

        // BASIC injection - DISABLED per attic-ahl (direct memory manipulation)
        case .injectBasic:
            return .error("BASIC injection is disabled. Use keyboard input instead.")

        case .injectKeys(let text):
            return await handleInjectKeys(text: text)

        // Disassembly
        case .disassemble(let address, let lines):
            return await handleDisassemble(address: address, lines: lines)

        // Phase 11: Monitor mode commands
        case .assemble(let address):
            // Start an interactive assembly session for this client.
            let assembler = InteractiveAssembler(startAddress: address)
            assemblySessions[clientId] = AssemblySession(
                assembler: assembler,
                startAddress: address
            )
            return .ok("ASM $\(String(format: "%04X", address))")

        case .assembleLine(let address, let instruction):
            // Single-line assembly (no session needed)
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

        case .assembleInput(let instruction):
            // Feed an instruction to the active assembly session.
            guard var session = assemblySessions[clientId] else {
                return .error("No active assembly session. Start one with: assemble $<address>")
            }
            do {
                let result = try session.assembler.assembleLine(instruction)
                // Write assembled bytes to emulator memory
                await emulator.writeMemoryBlock(at: result.address, bytes: result.bytes)
                session.totalBytes += result.bytes.count
                assemblySessions[clientId] = session
                // Format: assembled line + record separator + next address
                let formatted = session.assembler.format(result)
                let nextAddr = "$\(String(format: "%04X", session.assembler.currentAddress))"
                return .ok("\(formatted)\(CLIProtocolConstants.multiLineSeparator)\(nextAddr)")
            } catch {
                // Return error but keep session alive so the user can retry
                return .error("Assembly error: \(error)")
            }

        case .assembleEnd:
            // End the active assembly session and return summary.
            guard let session = assemblySessions.removeValue(forKey: clientId) else {
                return .error("No active assembly session")
            }
            if session.totalBytes == 0 {
                return .ok("Assembly complete: 0 bytes")
            }
            let endAddr = session.startAddress &+ UInt16(session.totalBytes) &- 1
            return .ok("Assembly complete: \(session.totalBytes) bytes at $\(String(format: "%04X", session.startAddress))-$\(String(format: "%04X", endAddr))")

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

        // BASIC line entry and commands - DISABLED per attic-ahl (direct memory manipulation)
        case .basicLine:
            return .error("BASIC line injection is disabled. Use keyboard input instead.")

        case .basicNew:
            return .error("BASIC NEW injection is disabled. Use keyboard input instead.")

        case .basicRun:
            return .error("BASIC RUN injection is disabled. Use keyboard input instead.")

        // BASIC editing commands
        case .basicDelete(let lineOrRange):
            let result = await basicHandler.deleteLines(lineOrRange: lineOrRange)
            return result.success ? .ok(result.message) : .error(result.message)

        case .basicStop:
            await emulator.sendBreak()
            return .ok("STOPPED")

        case .basicCont:
            let result = await basicHandler.continueProgram()
            return .ok(result.message)

        case .basicVars:
            let variables = await basicHandler.listVariablesWithValues()
            if variables.isEmpty {
                return .ok("(no variables)")
            }
            let lines = variables.map { "\($0.name.fullName) = \($0.value)" }
            return .okMultiLine(lines)

        case .basicVar(let name):
            if let value = await basicHandler.readVariableValue(name: name) {
                let varName = BASICVariableName.parse(name)
                return .ok("\(varName?.fullName ?? name) = \(value)")
            } else {
                return .error("Variable not found: \(name)")
            }

        case .basicInfo:
            let info = await basicHandler.getProgramInfo()
            return .ok("\(info.lines) lines, \(info.bytes) bytes, \(info.variables) variables")

        case .basicExport(let path):
            do {
                let message = try await basicHandler.exportProgram(to: path)
                return .ok(message)
            } catch {
                return .error(error.localizedDescription)
            }

        case .basicImport(let path):
            do {
                let result = try await basicHandler.importProgram(from: path)
                return result.success ? .ok(result.message) : .error(result.message)
            } catch {
                return .error(error.localizedDescription)
            }

        case .basicRenumber(let start, let step):
            let result = await basicHandler.renumberProgram(start: start, step: step)
            return result.success ? .ok(result.message) : .error(result.message)

        case .basicSave(let drive, let filename):
            guard let data = await basicHandler.getRawProgram() else {
                return .error("No program to save")
            }
            do {
                let sectors = try await diskManager.writeFile(drive: drive, name: filename, data: data)
                return .ok("Saved \(data.count) bytes to \(filename) (\(sectors) sectors)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .basicLoad(let drive, let filename):
            do {
                let data = try await diskManager.readFile(drive: drive, name: filename)
                let result = await basicHandler.loadRawProgram(data: data)
                return result.success ? .ok(result.message) : .error(result.message)
            } catch {
                return .error(error.localizedDescription)
            }

        case .basicDir(let drive):
            do {
                let entries = try await diskManager.listDirectory(drive: drive)
                if entries.isEmpty {
                    return .ok("(empty disk)")
                }
                let lines = entries.map { entry in
                    let lock = entry.isLocked ? "*" : " "
                    return "\(lock) \(entry.fullName.padding(toLength: 12, withPad: " ", startingAt: 0)) \(entry.sectorCount) sectors"
                }
                return .okMultiLine(lines)
            } catch {
                return .error(error.localizedDescription)
            }

        // BASIC listing is read-only, so it remains enabled
        case .basicList(let atascii, let start, let end):
            // List the BASIC program using the detokenizer, optionally
            // filtered to a line number range.
            let mode: ATASCIIRenderMode = atascii ? .rich : .plain
            let range: (start: Int?, end: Int?)? =
                (start != nil || end != nil) ? (start, end) : nil
            let listing = await basicHandler.listProgram(range: range, renderMode: mode)
            if listing.isEmpty {
                return .ok("(no program)")
            }
            // Convert newlines to multi-line separator for CLI protocol
            let lines = listing.split(separator: "\n", omittingEmptySubsequences: false)
            return .okMultiLine(lines.map(String.init))

        // DOS mode commands — all delegate to DiskManager which handles
        // ATR filesystem operations and coordinates with EmulatorEngine.
        case .dosChangeDrive(let drive):
            do {
                try await diskManager.changeDrive(to: drive)
                return .ok("D\(drive):")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosDirectory(let pattern):
            do {
                let entries = try await diskManager.listDirectory(pattern: pattern)
                if entries.isEmpty {
                    return .ok("(empty disk)")
                }
                let lines = entries.map { entry in
                    let lock = entry.isLocked ? "*" : " "
                    return "\(lock) \(entry.fullName.padding(toLength: 12, withPad: " ", startingAt: 0)) \(String(format: "%3d", entry.sectorCount)) sectors"
                }
                return .okMultiLine(lines)
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosFileInfo(let filename):
            do {
                let info = try await diskManager.getFileInfo(name: filename)
                var lines: [String] = []
                lines.append("Name:    \(info.entry.fullName)")
                lines.append("Size:    \(info.fileSize) bytes (\(info.entry.sectorCount) sectors)")
                lines.append("Locked:  \(info.entry.isLocked ? "yes" : "no")")
                if info.isCorrupted {
                    lines.append("WARNING: File appears corrupted")
                }
                return .okMultiLine(lines)
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosType(let filename):
            do {
                let data = try await diskManager.readFile(name: filename)
                // Convert to string, treating data as ATASCII/ASCII text
                let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) ?? "(binary data)"
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                return .okMultiLine(lines.map(String.init))
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosDump(let filename):
            do {
                let data = try await diskManager.readFile(name: filename)
                let lines = formatHexDump(data: data)
                return .okMultiLine(lines)
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosCopy(let source, let destination):
            do {
                // Parse drive prefixes from source and destination
                let (srcDrive, srcName) = parseDrivePrefix(source)
                let (dstDrive, dstName) = parseDrivePrefix(destination)
                // Resolve default drive outside ?? (actor isolation + autoclosure)
                let defaultDrive = await diskManager.currentDrive
                let fromDrive = srcDrive ?? defaultDrive
                let toDrive = dstDrive ?? defaultDrive
                let sectors = try await diskManager.copyFile(
                    from: fromDrive, name: srcName,
                    to: toDrive, as: dstName
                )
                return .ok("copied \(sectors) sectors")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosRename(let oldName, let newName):
            do {
                try await diskManager.renameFile(from: oldName, to: newName)
                return .ok("renamed \(oldName) to \(newName)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosDelete(let filename):
            do {
                try await diskManager.deleteFile(name: filename)
                return .ok("deleted \(filename)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosLock(let filename):
            do {
                try await diskManager.lockFile(name: filename)
                return .ok("locked \(filename)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosUnlock(let filename):
            do {
                try await diskManager.unlockFile(name: filename)
                return .ok("unlocked \(filename)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosExport(let filename, let hostPath):
            do {
                let bytes = try await diskManager.exportFile(name: filename, to: hostPath)
                return .ok("exported \(bytes) bytes to \(hostPath)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosImport(let hostPath, let filename):
            do {
                let sectors = try await diskManager.importFile(from: hostPath, name: filename)
                return .ok("imported \(sectors) sectors")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosNewDisk(let path, let type):
            do {
                let diskType = parseDiskType(type)
                let url = try await diskManager.createDisk(at: path, type: diskType)
                return .ok("created \(url.path)")
            } catch {
                return .error(error.localizedDescription)
            }

        case .dosFormat:
            do {
                let drive = await diskManager.currentDrive
                try await diskManager.formatDisk()
                return .ok("formatted D\(drive):")
            } catch {
                return .error(error.localizedDescription)
            }
        }
    }

    /// Parses a `Dn:FILENAME` prefix to extract drive number and filename.
    ///
    /// Used by DOS copy command to determine source/destination drives.
    /// Supports: `D:FILE` (default drive), `D1:FILE` (specific drive), `FILE` (no prefix).
    private func parseDrivePrefix(_ input: String) -> (drive: Int?, filename: String) {
        let upper = input.uppercased()

        if upper.hasPrefix("D") && upper.count > 1 {
            let afterD = upper.dropFirst()
            if afterD.hasPrefix(":") {
                // D:FILENAME — default drive
                let filename = String(input.dropFirst(2))
                return (nil, filename)
            }
            if let colonIndex = afterD.firstIndex(of: ":") {
                let driveStr = String(afterD[afterD.startIndex..<colonIndex])
                if let drive = Int(driveStr), drive >= 1, drive <= 8 {
                    let filenameStart = afterD.index(after: colonIndex)
                    let filename = String(afterD[filenameStart...])
                    return (drive, filename)
                }
            }
        }

        // No drive prefix
        return (nil, input)
    }

    /// Converts a disk type string ("sd", "ed", "dd") to a DiskType enum value.
    ///
    /// Returns `.singleDensity` as the default if the string is nil or unrecognized.
    private func parseDiskType(_ type: String?) -> DiskType {
        switch type?.lowercased() {
        case "sd", nil: return .singleDensity
        case "ed": return .enhancedDensity
        case "dd": return .doubleDensity
        default: return .singleDensity
        }
    }

    /// Formats raw data as a hex dump with 16 bytes per line.
    ///
    /// Output format: `0000: 48 65 6C 6C 6F 20 57 6F 72 6C 64 21 00 00 00 00  Hello World!....`
    private func formatHexDump(data: Data) -> [String] {
        var lines: [String] = []
        let bytesPerLine = 16

        for offset in stride(from: 0, to: data.count, by: bytesPerLine) {
            let end = min(offset + bytesPerLine, data.count)
            let chunk = data[offset..<end]

            // Address
            var line = String(format: "%04X: ", offset)

            // Hex bytes
            for (i, byte) in chunk.enumerated() {
                line += String(format: "%02X ", byte)
                if i == 7 { line += " " }  // Extra space at midpoint
            }

            // Pad if less than 16 bytes
            let missing = bytesPerLine - chunk.count
            for i in 0..<missing {
                line += "   "
                if chunk.count + i == 7 { line += " " }
            }

            // ASCII representation
            line += " "
            for byte in chunk {
                if byte >= 0x20 && byte <= 0x7E {
                    line += String(UnicodeScalar(byte))
                } else {
                    line += "."
                }
            }

            lines.append(line)
        }

        return lines
    }

    /// Handles the screenshot command by capturing the current frame buffer and saving as PNG.
    ///
    /// The frame buffer is 384x240 pixels in BGRA format. This method converts it to
    /// a PNG image and saves it to the specified path.
    ///
    /// - Parameter path: The file path to save the screenshot, or nil for auto-generated path.
    /// - Returns: CLI response with the path where the screenshot was saved.
    private func handleScreenshot(path: String?) async -> CLIResponse {
        // Generate default path if not provided
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let defaultFilename = "Attic-\(timestamp).png"

        let actualPath: String
        if let providedPath = path {
            // Expand ~ to home directory
            actualPath = NSString(string: providedPath).expandingTildeInPath
        } else {
            // Save to Desktop by default
            let desktopURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            actualPath = desktopURL.appendingPathComponent(defaultFilename).path
        }

        // Get the frame buffer from the emulator
        let frameBuffer = await emulator.getFrameBuffer()

        // Frame buffer dimensions (Atari 800 XL standard)
        let width = 384
        let height = 240
        let bytesPerPixel = 4  // BGRA
        let bytesPerRow = width * bytesPerPixel

        // Verify we have enough data
        guard frameBuffer.count >= width * height * bytesPerPixel else {
            return .error("Invalid frame buffer size: expected \(width * height * bytesPerPixel), got \(frameBuffer.count)")
        }

        // Create CGImage from BGRA data
        guard let dataProvider = CGDataProvider(data: Data(frameBuffer) as CFData) else {
            return .error("Failed to create data provider for screenshot")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return .error("Failed to create CGImage for screenshot")
        }

        // Create destination URL
        let destinationURL = URL(fileURLWithPath: actualPath)

        // Create the directory if it doesn't exist
        let directoryURL = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return .error("Failed to create directory: \(error.localizedDescription)")
        }

        // Create PNG file
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return .error("Failed to create image destination for screenshot")
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            return .error("Failed to write screenshot to \(actualPath)")
        }

        return .ok("screenshot saved to \(actualPath)")
    }

    /// Handles the screen text command by reading GRAPHICS 0 display memory.
    ///
    /// Reads the 40x24 character screen RAM and converts Atari screen codes to
    /// printable Unicode characters. Atari screen codes are NOT the same as
    /// ATASCII — the mapping is:
    ///   - Screen $00-$1F → ATASCII $20-$3F (space, digits, punctuation)
    ///   - Screen $20-$3F → ATASCII $40-$5F (uppercase letters, @, [, etc.)
    ///   - Screen $40-$5F → control characters → rendered as "."
    ///   - Screen $60-$7F → ATASCII $60-$7F (lowercase letters)
    ///   - Screen $80-$FF → inverse video of $00-$7F
    ///
    /// When `atascii` is true, inverse video characters (bit 7 set) are wrapped
    /// with ANSI reverse video escape codes (`\e[7m`...`\e[27m`).
    ///
    /// Key memory locations:
    ///   - DINDEX ($0057) — current display mode (must be 0 for text)
    ///   - SAVMSC ($0058-$0059) — 16-bit pointer to screen RAM base
    ///
    /// - Parameter atascii: Whether to render inverse chars with ANSI codes.
    /// - Returns: CLI response with the screen text as multi-line output.
    private func handleScreenText(atascii: Bool = false) async -> CLIResponse {
        // Check display mode — DINDEX at $0057 must be 0 (GRAPHICS 0)
        let dindex = await emulator.readMemory(at: 0x0057)
        guard dindex == 0 else {
            return .error("Not in GRAPHICS 0 mode (DINDEX=\(dindex))")
        }

        // Read SAVMSC ($0058-$0059) — little-endian pointer to screen RAM
        let savmscLo = await emulator.readMemory(at: 0x0058)
        let savmscHi = await emulator.readMemory(at: 0x0059)
        let screenBase = UInt16(savmscHi) << 8 | UInt16(savmscLo)

        // Read 960 bytes (40 columns x 24 rows) of screen RAM
        let screenData = await emulator.readMemoryBlock(at: screenBase, count: 960)

        // Convert screen codes to printable characters and split into lines.
        // screenCodeToString returns a String (not Character) because ANSI
        // escape codes may wrap the character when atascii mode is enabled.
        var lines: [String] = []
        for row in 0..<24 {
            var line = ""
            for col in 0..<40 {
                let screenCode = screenData[row * 40 + col]
                line.append(screenCodeToString(screenCode, atascii: atascii))
            }
            lines.append(line)
        }

        // Trim trailing blank lines
        while let last = lines.last, last.allSatisfy({ $0 == " " }) {
            lines.removeLast()
        }

        return .okMultiLine(lines)
    }

    /// Converts an Atari screen code byte to a printable string.
    ///
    /// Screen codes differ from ATASCII. The mapping strips the inverse-video
    /// bit (bit 7), then maps the low 7 bits:
    ///   - $00-$1F → characters ' ' through '?' (ASCII $20-$3F)
    ///   - $20-$3F → characters '@' through '_' (ASCII $40-$5F)
    ///   - $40-$5F → control characters → rendered as "."
    ///   - $60-$7F → characters '`' through DEL → lowercase letters, etc.
    ///
    /// When `atascii` is true and bit 7 is set, the character is wrapped with
    /// ANSI reverse video codes (`\e[7m`...`\e[27m`) to visually indicate
    /// inverse video.
    ///
    /// - Parameters:
    ///   - code: The screen code byte from screen RAM.
    ///   - atascii: Whether to use ANSI codes for inverse video characters.
    /// - Returns: A string containing the character, possibly with ANSI codes.
    private func screenCodeToString(_ code: UInt8, atascii: Bool) -> String {
        let inverse = (code & 0x80) != 0
        let base = code & 0x7F

        // Map screen code to the base printable character
        let char: Character
        switch base {
        case 0x00...0x1F:
            // Screen $00-$1F → ASCII $20-$3F (space, digits, punctuation)
            char = Character(UnicodeScalar(base + 0x20))
        case 0x20...0x3F:
            // Screen $20-$3F → ASCII $40-$5F (uppercase letters, @, [, etc.)
            char = Character(UnicodeScalar(base + 0x20))
        case 0x40...0x5F:
            // Screen $40-$5F → control characters, render as "."
            char = "."
        case 0x60...0x7F:
            // Screen $60-$7F → ASCII $60-$7F (lowercase letters)
            char = Character(UnicodeScalar(base))
        default:
            char = "."
        }

        // Wrap with ANSI reverse video if inverse and atascii mode is enabled
        if atascii && inverse {
            return "\u{1B}[7m\(char)\u{1B}[27m"
        }
        return String(char)
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

    /// Handles the inject keys command by typing each character into the emulator.
    ///
    /// This injects keystrokes one at a time, executing frames between key presses
    /// to ensure the emulator sees each key. This is the "natural input" method
    /// that goes through the normal keyboard input pipeline.
    ///
    /// - Parameter text: The text to type, with escape sequences already parsed.
    /// - Returns: CLI response indicating success or failure.
    private func handleInjectKeys(text: String) async -> CLIResponse {
        // Number of frames to hold each key down (for emulator to see it)
        let framesPerKeyPress = 3
        // Number of frames between key release and next key press
        let framesBetweenKeys = 2
        // Extra frames needed when pressing the same key twice in a row
        // The Atari OS keyboard handler needs to see the key released for
        // several frames before it will accept a new press of the same key
        let extraFramesForRepeat = 4

        var injectedCount = 0
        var previousKeyChar: UInt8 = 0
        var previousKeyCode: UInt8 = 0xFF

        for char in text {
            // Convert character to Atari key codes
            let (keyChar, keyCode, shift, control) = characterToAtariKey(char)

            // Skip if we couldn't map the character
            if keyChar == 0 && keyCode == 0xFF {
                continue
            }

            // Check if this is the same key as the previous one
            let isSameKey = (keyChar == previousKeyChar && keyChar != 0) ||
                           (keyCode == previousKeyCode && keyCode != 0xFF)

            // If same key, add extra frames for keyboard debounce
            if isSameKey {
                for _ in 0..<extraFramesForRepeat {
                    await emulator.executeFrame()
                }
            }

            // Press the key
            await emulator.pressKey(keyChar: keyChar, keyCode: keyCode, shift: shift, control: control)

            // Execute frames while key is held
            for _ in 0..<framesPerKeyPress {
                await emulator.executeFrame()
            }

            // Release the key
            await emulator.releaseKey()

            // Execute frames for key release
            for _ in 0..<framesBetweenKeys {
                await emulator.executeFrame()
            }

            // Remember this key for repeat detection
            previousKeyChar = keyChar
            previousKeyCode = keyCode

            injectedCount += 1
        }

        return .ok("injected \(injectedCount) keys")
    }

    /// Converts a character to Atari keyChar and keyCode values.
    ///
    /// - Parameter char: The character to convert.
    /// - Returns: Tuple of (keyChar, keyCode, shift, control) for the emulator.
    private func characterToAtariKey(_ char: Character) -> (keyChar: UInt8, keyCode: UInt8, shift: Bool, control: Bool) {
        // Handle special characters
        switch char {
        case "\n", "\r":
            // Return/Enter - use keyCode, not keyChar
            return (0, AtariKeyCode.return, false, false)

        case "\t":
            // Tab
            return (0, AtariKeyCode.tab, false, false)

        case "\u{1B}":
            // Escape
            return (0, AtariKeyCode.escape, false, false)

        case "\u{7F}", "\u{08}":
            // Delete/Backspace
            return (0, AtariKeyCode.backspace, false, false)

        case " ":
            // Space
            return (0x20, AtariKeyCode.space, false, false)

        default:
            break
        }

        // Get ASCII value
        guard let ascii = char.asciiValue else {
            // Non-ASCII character - skip
            return (0, 0xFF, false, false)
        }

        // Control characters (Ctrl+A through Ctrl+Z produce codes 1-26)
        if ascii >= 1 && ascii <= 26 {
            return (ascii, 0xFF, false, true)
        }

        // Lowercase letters - convert to uppercase for Atari
        if ascii >= 0x61 && ascii <= 0x7A {
            let uppercase = ascii - 0x20
            return (uppercase, 0xFF, false, false)
        }

        // Uppercase letters - need shift
        if ascii >= 0x41 && ascii <= 0x5A {
            return (ascii, 0xFF, true, false)
        }

        // Numbers and most punctuation pass through as-is
        if ascii >= 0x20 && ascii <= 0x7E {
            return (ascii, 0xFF, false, false)
        }

        // Unknown character
        return (0, 0xFF, false, false)
    }

    func server(_ server: CLISocketServer, clientDidConnect clientId: UUID) async {
        print("[CLISocket] Client connected: \(clientId)")
    }

    func server(_ server: CLISocketServer, clientDidDisconnect clientId: UUID) async {
        // Clean up any active assembly session for this client
        if assemblySessions.removeValue(forKey: clientId) != nil {
            print("[CLISocket] Cleaned up assembly session for \(clientId)")
        }
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
        let drives = await diskManager.listDrives()

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

        // Show disk mount status for drives 1-8
        for driveStatus in drives {
            let d = driveStatus.drive
            if driveStatus.mounted {
                let filename = driveStatus.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
                status += " D\(d)=\(filename)"
            } else {
                status += " D\(d)=(none)"
            }
        }

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

        // Create a DiskManager for AESP status responses.
        // If CLI socket is enabled, this will be replaced by the shared one.
        delegate.diskManager = DiskManager(emulator: emulator)

        // Create and start CLI socket server (if enabled)
        var cliServer: CLISocketServer?
        var cliDelegate: CLIServerDelegate?

        if config.enableCLISocket {
            let socketPath = config.socketPath ?? CLIProtocolConstants.currentSocketPath
            cliServer = CLISocketServer(socketPath: socketPath)
            cliDelegate = CLIServerDelegate(emulator: emulator)

            if let server = cliServer, let del = cliDelegate {
                del.setServer(server)
                // Share the CLI delegate's DiskManager with the AESP delegate
                // so status responses include mounted disk information.
                delegate.diskManager = del.diskManager
                // Set shutdown callback to stop the main loop
                del.onShutdown = { [delegate] in
                    delegate.shouldRun = false
                }
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

        // Set up signal handlers for graceful shutdown.
        // SIGINT handles Ctrl+C from the terminal.
        // SIGTERM handles Process.terminate() / kill(pid, SIGTERM) from parent
        // processes like AtticGUI, which use process lifecycle management
        // instead of the CLI protocol for shutdown.
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigintSource.setEventHandler {
            print("\nShutting down (SIGINT)...")
            delegate.shouldRun = false
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigtermSource.setEventHandler {
            print("\nShutting down (SIGTERM)...")
            delegate.shouldRun = false
        }
        sigtermSource.resume()

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
