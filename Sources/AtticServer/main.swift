// =============================================================================
// main.swift - Attic Emulator Server
// =============================================================================
//
// This is the standalone emulator server process that runs the Atari 800 XL
// emulation and broadcasts video frames and audio samples via the Attic
// Emulator Server Protocol (AESP).
//
// The server listens on three ports:
// - Control (47800): Commands, status, memory access, input events
// - Video (47801): Frame broadcasts to subscribed clients
// - Audio (47802): Audio sample broadcasts to subscribed clients
//
// Usage:
//   AtticServer [options]
//
// Options:
//   --rom-path <path>    Path to ROM directory (default: auto-detect)
//   --control-port <n>   Control port (default: 47800)
//   --video-port <n>     Video port (default: 47801)
//   --audio-port <n>     Audio port (default: 47802)
//   --silent             Disable audio generation
//   --help               Show usage information
//
// Clients can connect using the AESPClient from the AtticProtocol module,
// or any implementation that speaks the AESP binary protocol.
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
          --silent             Disable audio generation
          --help, -h           Show this help message

        The server broadcasts video frames and audio samples to connected clients.
        Use AESPClient to connect from Swift applications, or implement the AESP
        binary protocol for other languages.

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

        // Create and start server
        let server = AESPServer(configuration: serverConfig)
        let delegate = ServerDelegate(emulator: emulator)
        await server.setDelegate(delegate)

        do {
            try await server.start()
            print("Server listening on:")
            print("  Control: localhost:\(config.controlPort)")
            print("  Video:   localhost:\(config.videoPort)")
            print("  Audio:   localhost:\(config.audioPort)")
        } catch {
            print("Error starting server: \(error)")
            return
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
            }
            // Schedule next frame (even if we're behind, this keeps us on pace)
            nextFrameTime += targetFrameTime
        }

        // Shutdown
        print("Stopping server...")
        await server.stop()
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
