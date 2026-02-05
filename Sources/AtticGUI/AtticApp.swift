// =============================================================================
// AtticApp.swift - SwiftUI Application Entry Point
// =============================================================================
//
// This is the main entry point for the Attic GUI application.
// It defines the SwiftUI App struct which creates the main window.
//
// The GUI application supports two operation modes:
//
// 1. **Client Mode (default)**: Connects to AtticServer via AESP protocol.
//    The server runs as a subprocess and handles all emulation. The GUI
//    receives video frames and audio samples via the protocol.
//
// 2. **Embedded Mode**: Runs the EmulatorEngine directly within the GUI
//    process. Used for debugging or when server launch fails.
//    Enabled with --embedded flag.
//
// Architecture:
// The App struct creates a single main window containing the ContentView.
// AtticViewModel manages either the protocol client or embedded emulator.
//
// =============================================================================

import SwiftUI
import AtticCore
import AtticProtocol

// MARK: - Operation Mode

/// The operation mode for the GUI application.
enum OperationMode: Sendable {
    /// Client mode: connects to AtticServer via AESP protocol.
    /// This is the default mode for normal operation.
    case client

    /// Embedded mode: runs EmulatorEngine directly in the GUI process.
    /// Used for debugging or when server launch fails.
    case embedded
}

/// The main SwiftUI application for Attic.
///
/// This struct conforms to the App protocol, which is the entry point
/// for a SwiftUI application. The @main attribute tells Swift to use
/// this as the program's entry point.
@main
struct AtticApp: App {
    // =========================================================================
    // MARK: - State
    // =========================================================================

    /// The view model, shared across the app.
    /// Using @StateObject ensures it persists across view updates.
    @StateObject private var viewModel: AtticViewModel

    /// App delegate for handling application lifecycle events.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    init() {
        // Parse command-line arguments to determine operation mode
        let mode = AtticApp.parseOperationMode()
        _viewModel = StateObject(wrappedValue: AtticViewModel(mode: mode))
    }

    /// Parses command-line arguments to determine operation mode.
    private static func parseOperationMode() -> OperationMode {
        let arguments = CommandLine.arguments

        // Check for --embedded flag
        if arguments.contains("--embedded") {
            print("[AtticGUI] Running in embedded mode")
            return .embedded
        }

        // Default to client mode
        print("[AtticGUI] Running in client mode")
        return .client
    }

    // =========================================================================
    // MARK: - Body
    // =========================================================================

    /// The main scene of the application.
    ///
    /// A WindowGroup creates a new window for each scene. For a single-window
    /// app like an emulator, this typically means one main window.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.hiddenTitleBar)  // For a cleaner look
        .defaultSize(width: 1152, height: 720)  // 384x240 * 3
        .commands {
            // Add custom menu commands
            AtticCommands(viewModel: viewModel)
        }
    }
}

// =============================================================================
// MARK: - App Delegate
// =============================================================================

/// NSApplicationDelegate for handling app lifecycle events.
///
/// While SwiftUI handles most lifecycle events, some macOS-specific features
/// still require an NSApplicationDelegate:
/// - Opening files via Finder
/// - Handling URL schemes
/// - Custom termination behavior
/// - Setting activation policy for proper GUI behavior
///
/// Important: When running via `swift run`, the application is launched as
/// a child process of the terminal. By default, this means:
/// - No menu bar appears
/// - Keyboard events go to the terminal, not the app
/// - The app doesn't appear in the Dock
///
/// We fix this by setting the activation policy to `.regular`, which makes
/// the app behave as a normal foreground GUI application.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Called before the app finishes launching.
    ///
    /// We set the activation policy here to ensure the app becomes a proper
    /// GUI application with a menu bar and keyboard focus.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Make this a regular GUI application (shows in Dock, has menu bar)
        // This is essential when running via `swift run` which otherwise
        // treats the app as a background/accessory process.
        NSApp.setActivationPolicy(.regular)
    }

    /// Called when the app finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AtticGUI] Application launched")

        // Bring the app to the foreground and make it the active app
        // This ensures our window receives keyboard events instead of the terminal
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called when the app is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        print("[AtticGUI] Application terminating")
        // Server cleanup is handled by AtticViewModel's deinit
    }

    /// Called when a file is opened via Finder (double-click on .atr file).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("[AtticGUI] Open file: \(url.path)")
            // TODO: Mount disk image or load state file
        }
    }

    /// Determines whether the app should terminate when the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true  // Quit when window is closed
    }
}

// =============================================================================
// MARK: - View Model
// =============================================================================

/// Main view model for the Attic application.
///
/// This class supports two operation modes:
/// - **Client mode**: Connects to AtticServer via AESP protocol
/// - **Embedded mode**: Runs EmulatorEngine directly
///
/// In client mode, the view model:
/// 1. Launches AtticServer as a subprocess
/// 2. Connects via AESPClient
/// 3. Receives video frames via AsyncStream
/// 4. Receives audio samples via AsyncStream
/// 5. Sends input via protocol messages
///
/// In embedded mode, the view model:
/// 1. Creates and initializes EmulatorEngine directly
/// 2. Runs an emulation loop that executes frames
/// 3. Gets frame/audio data directly from the emulator
/// 4. Sends input directly to the emulator
///
/// Note: @MainActor ensures all UI-related updates happen on the main thread.
@MainActor
class AtticViewModel: ObservableObject {
    // =========================================================================
    // MARK: - Mode Configuration
    // =========================================================================

    /// The current operation mode.
    let mode: OperationMode

    // =========================================================================
    // MARK: - Shared Components
    // =========================================================================

    /// The Metal renderer (set by EmulatorMetalView).
    /// This displays the Atari screen using GPU acceleration.
    var renderer: MetalRenderer?

    /// The audio engine for POKEY sound output.
    /// This buffers and plays audio samples generated by the emulator.
    let audioEngine: AudioEngine

    /// The keyboard input handler.
    /// This maps Mac keyboard events to Atari key codes.
    let keyboardHandler: KeyboardInputHandler

    // =========================================================================
    // MARK: - Client Mode Components
    // =========================================================================

    /// The AESP protocol client (client mode only).
    private var client: AESPClient?

    /// Task for receiving video frames.
    private var frameReceiverTask: Task<Void, Never>?

    /// Task for receiving audio samples.
    private var audioReceiverTask: Task<Void, Never>?

    /// PID of the AtticServer process if we launched it.
    /// Used for shutdown functionality.
    private var serverPID: Int32?

    /// Path to the CLI socket for sending shutdown commands.
    private var cliSocketPath: String?

    // =========================================================================
    // MARK: - Embedded Mode Components
    // =========================================================================

    /// The emulator engine (embedded mode only).
    /// This is the core emulation that wraps libatari800.
    private var emulator: EmulatorEngine?

    /// The emulation loop task (embedded mode only).
    private var emulationTask: Task<Void, Never>?

    // =========================================================================
    // MARK: - Published State
    // =========================================================================

    /// Whether the emulator is initialized/connected.
    @Published var isInitialized: Bool = false

    /// Initialization error message, if any.
    @Published var initializationError: String?

    /// Current emulator running state for UI binding.
    @Published var isRunning: Bool = false

    /// Status message for display.
    @Published var statusMessage: String = "Not Initialized"

    /// FPS counter.
    @Published var fps: Int = 0

    /// Whether audio is enabled.
    @Published var isAudioEnabled: Bool = true {
        didSet {
            audioEngine.isEnabled = isAudioEnabled
            if !isAudioEnabled {
                audioEngine.clearBuffer()
            }
        }
    }

    // =========================================================================
    // MARK: - Internal State
    // =========================================================================

    /// Frame counter for FPS calculation.
    private var frameCounter: Int = 0

    /// Last FPS update time.
    private var lastFPSUpdate: Date = Date()

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new view model with the specified operation mode.
    ///
    /// - Parameter mode: The operation mode (client or embedded).
    init(mode: OperationMode = .client) {
        self.mode = mode
        self.audioEngine = AudioEngine()
        self.keyboardHandler = KeyboardInputHandler()

        // Only create emulator in embedded mode
        if mode == .embedded {
            self.emulator = EmulatorEngine()
        }
    }

    /// Initializes the emulator (embedded mode) or connects to server (client mode).
    ///
    /// This should be called when the view appears.
    func initializeEmulator() async {
        switch mode {
        case .client:
            await initializeClientMode()
        case .embedded:
            await initializeEmbeddedMode()
        }
    }

    // =========================================================================
    // MARK: - Client Mode Initialization
    // =========================================================================

    /// Writes a debug message to a log file (for debugging GUI startup).
    private func debugLog(_ message: String) {
        let logPath = "/tmp/attic-gui-debug.log"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }

    /// Initializes client mode by connecting to AtticServer.
    ///
    /// If no server is running, automatically launches one first.
    private func initializeClientMode() async {
        debugLog("initializeClientMode() called")
        statusMessage = "Connecting to server..."

        // Try to connect to existing server first
        let connected = await tryConnectToServer()
        debugLog("tryConnectToServer() returned: \(connected)")

        if !connected {
            // No server running - try to launch one
            debugLog("No server running, attempting to launch...")
            statusMessage = "Starting server..."

            let launcher = ServerLauncher()
            if let execPath = launcher.findServerExecutable() {
                debugLog("Found server executable at: \(execPath)")
            } else {
                debugLog("Server executable NOT found")
            }
            let result = launcher.launchServer(options: ServerLaunchOptions(silent: false))
            debugLog("launchServer result: \(result)")

            switch result {
            case .success(let socketPath, let pid):
                debugLog("AtticServer started (PID: \(pid)) at \(socketPath)")
                // Store server info for shutdown functionality
                serverPID = pid
                cliSocketPath = socketPath
                // Wait a moment for AESP to initialize
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                // Try connecting again
                let retryConnected = await tryConnectToServer()
                if !retryConnected {
                    initializationError = """
                        AtticServer started but connection failed.

                        Try running in embedded mode:
                          swift run AtticGUI --embedded
                        """
                    statusMessage = "Connection Failed"
                    await cleanup()
                }

            case .executableNotFound:
                print("[AtticGUI] AtticServer executable not found")
                initializationError = """
                    AtticServer executable not found.

                    Make sure AtticServer is built:
                      swift build

                    Or run in embedded mode:
                      swift run AtticGUI --embedded
                    """
                statusMessage = "Server Not Found"
                await cleanup()

            case .launchFailed(let error):
                print("[AtticGUI] Failed to launch AtticServer: \(error)")
                initializationError = """
                    Failed to launch AtticServer: \(error.localizedDescription)

                    Try starting it manually:
                      swift run AtticServer

                    Or run in embedded mode:
                      swift run AtticGUI --embedded
                    """
                statusMessage = "Launch Failed"
                await cleanup()

            case .socketTimeout(let pid):
                print("[AtticGUI] AtticServer started (PID: \(pid)) but socket not ready")
                initializationError = """
                    AtticServer started but socket not ready.

                    Try running in embedded mode:
                      swift run AtticGUI --embedded
                    """
                statusMessage = "Server Timeout"
                await cleanup()
            }
        }
    }

    /// Attempts to connect to an existing AtticServer via AESP protocol.
    ///
    /// - Returns: True if connection successful, false otherwise.
    private func tryConnectToServer() async -> Bool {
        do {
            // Create and connect client
            let clientConfig = AESPClientConfiguration(
                host: "localhost",
                controlPort: AESPConstants.defaultControlPort,
                videoPort: AESPConstants.defaultVideoPort,
                audioPort: AESPConstants.defaultAudioPort
            )
            client = AESPClient(configuration: clientConfig)

            try await client?.connect()

            // Subscribe to video and audio streams
            await client?.subscribeToVideo()
            await client?.subscribeToAudio()

            // Configure audio engine
            // libatari800 typically outputs 44100 Hz, 16-bit mono audio
            let audioConfig = AudioConfiguration(sampleRate: 44100, channels: 1, sampleSize: 2)
            audioEngine.configure(from: audioConfig)

            // Start audio engine in a background task to avoid blocking
            // This is a workaround for AVAudioEngine sometimes blocking on start()
            Task.detached {
                do {
                    try self.audioEngine.start()
                } catch {
                    print("[AtticGUI] Warning: Failed to start audio: \(error)")
                }
            }

            // Start receiving frames and audio
            startFrameReceiver()
            startAudioReceiver()

            isInitialized = true
            isRunning = true
            statusMessage = "Connected"
            audioEngine.resume()

            print("[AtticGUI] Connected to server")
            return true

        } catch {
            print("[AtticGUI] Failed to connect to server: \(error)")
            // Clean up partial state
            client = nil
            return false
        }
    }

    /// Starts the frame receiver task.
    private func startFrameReceiver() {
        frameReceiverTask = Task { [weak self] in
            guard let self = self, let client = self.client else { return }

            for await frameBuffer in await client.frameStream {
                // Update renderer on main actor
                await MainActor.run {
                    self.renderer?.updateTexture(with: frameBuffer)
                    self.updateFPS()
                }
            }
        }
    }

    /// Starts the audio receiver task.
    private func startAudioReceiver() {
        audioReceiverTask = Task { [weak self] in
            guard let self = self, let client = self.client else { return }

            for await samples in await client.audioStream {
                // Feed samples to audio engine using Data directly (avoids Array copy)
                self.audioEngine.enqueueSamplesFromEmulator(data: samples)
            }
        }
    }

    // =========================================================================
    // MARK: - Embedded Mode Initialization
    // =========================================================================

    /// Initializes embedded mode with direct EmulatorEngine.
    private func initializeEmbeddedMode() async {
        guard let emulator = emulator else {
            initializationError = "Emulator not created"
            return
        }

        // Try to find ROM directory
        let romPath = findROMPath()

        guard let romPath = romPath else {
            initializationError = "ROM directory not found"
            return
        }

        do {
            // Initialize the emulator
            try await emulator.initialize(romPath: romPath)
            isInitialized = true
            statusMessage = "Ready"

            // Configure audio engine to match emulator's output format
            let audioConfig = await emulator.getAudioConfiguration()
            audioEngine.configure(from: audioConfig)

            // Start audio engine
            do {
                try audioEngine.start()
                let bitsPerSample = audioConfig.sampleSize * 8
                print("[AtticGUI] Audio engine started: \(audioConfig.sampleRate) Hz, \(audioConfig.channels) ch, \(bitsPerSample)-bit")
            } catch {
                print("[AtticGUI] Warning: Failed to start audio: \(error.localizedDescription)")
            }

            // Start the emulation loop
            startEmulationLoop()

            // Auto-start
            await start()
        } catch {
            initializationError = error.localizedDescription
            statusMessage = "Error"
        }
    }

    // =========================================================================
    // MARK: - ROM Path Discovery
    // =========================================================================

    /// Finds the ROM directory.
    ///
    /// Searches in standard locations for the ROM files.
    private func findROMPath() -> URL? {
        let fileManager = FileManager.default

        // Check various locations
        let searchPaths: [URL] = [
            // Current working directory
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/ROM"),
            // Bundle resources (for packaged app)
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ROM"),
            // User's home directory
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".attic/ROM"),
            // Source repo location (for development)
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/ROM"),
        ]

        for path in searchPaths {
            let osRom = path.appendingPathComponent("ATARIXL.ROM")
            if fileManager.fileExists(atPath: osRom.path) {
                print("[AtticGUI] Found ROMs at: \(path.path)")
                return path
            }
        }

        print("[AtticGUI] ROM search paths tried:")
        for path in searchPaths {
            print("  - \(path.path)")
        }

        return nil
    }

    // =========================================================================
    // MARK: - Control Methods
    // =========================================================================

    /// Starts/resumes the emulator.
    func start() async {
        guard isInitialized else { return }

        switch mode {
        case .client:
            await client?.resume()
            audioEngine.resume()
            isRunning = true
            statusMessage = "Running"

        case .embedded:
            guard let emulator = emulator else { return }
            await emulator.resume()
            audioEngine.resume()
            isRunning = true
            statusMessage = "Running"
        }
    }

    /// Pauses the emulator.
    func pause() async {
        switch mode {
        case .client:
            await client?.pause()
            audioEngine.pause()
            isRunning = false
            statusMessage = "Paused"

        case .embedded:
            guard let emulator = emulator else { return }
            await emulator.pause()
            audioEngine.pause()
            isRunning = false
            statusMessage = "Paused"
        }
    }

    /// Performs a reset.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    func reset(cold: Bool = true) async {
        switch mode {
        case .client:
            await client?.reset(cold: cold)
            audioEngine.clearBuffer()
            keyboardHandler.reset()
            statusMessage = cold ? "Cold Reset" : "Warm Reset"

        case .embedded:
            guard let emulator = emulator else { return }
            await emulator.reset(cold: cold)
            audioEngine.clearBuffer()
            keyboardHandler.reset()
            statusMessage = cold ? "Cold Reset" : "Warm Reset"
        }
    }

    // =========================================================================
    // MARK: - Keyboard Input
    // =========================================================================

    /// Handles a key down event from the keyboard.
    func handleKeyDown(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let control = event.modifierFlags.contains(.control)

        // Update modifier state
        keyboardHandler.updateModifiers(
            shift: shift,
            control: control,
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command)
        )

        // F5 triggers warm reset (Atari RESET key)
        // This is handled specially because RESET is not part of the keyboard matrix
        if event.keyCode == 0x60 {  // MacKeyCode.f5
            Task {
                await reset(cold: false)
            }
            return
        }

        // Convert to Atari key
        if let (keyChar, keyCode, atariShift, atariControl) = keyboardHandler.keyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            shift: shift,
            control: control
        ) {
            // Send to emulator/server based on mode
            Task {
                switch mode {
                case .client:
                    await client?.sendKeyDown(
                        keyChar: keyChar,
                        keyCode: keyCode,
                        shift: atariShift,
                        control: atariControl
                    )
                case .embedded:
                    await emulator?.pressKey(
                        keyChar: keyChar,
                        keyCode: keyCode,
                        shift: atariShift,
                        control: atariControl
                    )
                }
            }
        }

        // Update console keys
        sendConsoleKeys()
    }

    /// Handles a key up event from the keyboard.
    func handleKeyUp(_ event: NSEvent) {
        if keyboardHandler.keyUp(keyCode: event.keyCode) {
            // Release the key
            Task {
                switch mode {
                case .client:
                    await client?.sendKeyUp()
                case .embedded:
                    await emulator?.releaseKey()
                }
            }
        }

        // Update console keys (in case F1/F2/F3 was released)
        sendConsoleKeys()
    }

    /// Handles modifier flags changes (Shift, Control, etc.).
    func handleFlagsChanged(_ event: NSEvent) {
        keyboardHandler.updateModifiers(
            shift: event.modifierFlags.contains(.shift),
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command)
        )
    }

    /// Sends current console key states.
    func sendConsoleKeys() {
        let consoleKeys = keyboardHandler.getConsoleKeys()
        Task {
            switch mode {
            case .client:
                await client?.sendConsoleKeys(
                    start: consoleKeys.start,
                    select: consoleKeys.select,
                    option: consoleKeys.option
                )
            case .embedded:
                await emulator?.setConsoleKeys(
                    start: consoleKeys.start,
                    select: consoleKeys.select,
                    option: consoleKeys.option
                )
            }
        }
    }

    /// Sends console key states (for button presses).
    func setConsoleKeys(start: Bool, select: Bool, option: Bool) {
        Task {
            switch mode {
            case .client:
                await client?.sendConsoleKeys(
                    start: start,
                    select: select,
                    option: option
                )
            case .embedded:
                await emulator?.setConsoleKeys(
                    start: start,
                    select: select,
                    option: option
                )
            }
        }
    }

    // =========================================================================
    // MARK: - Emulation Loop (Embedded Mode Only)
    // =========================================================================

    /// Starts the emulation loop (embedded mode only).
    private func startEmulationLoop() {
        guard mode == .embedded else { return }
        emulationTask = Task { [weak self] in
            await self?.emulationLoop()
        }
    }

    /// The main emulation loop (embedded mode only).
    private func emulationLoop() async {
        guard let emulator = emulator else { return }

        // Target 60fps = 16.67ms per frame
        // Use absolute frame scheduling to prevent timing drift
        let targetFrameTime: UInt64 = 16_666_667  // nanoseconds
        var nextFrameTime = DispatchTime.now().uptimeNanoseconds + targetFrameTime

        while !Task.isCancelled {
            if isRunning {
                // Execute one frame
                let result = await emulator.executeFrame()

                // Get frame buffer and update renderer
                let frameBuffer = await emulator.getFrameBuffer()

                // Get audio samples and feed to audio engine
                let audioSamples = await emulator.getAudioSamples()
                if !audioSamples.isEmpty {
                    audioEngine.enqueueSamplesFromEmulator(bytes: audioSamples)
                }

                // Update UI
                renderer?.updateTexture(with: frameBuffer)
                updateFPS()

                // Handle special frame results
                switch result {
                case .breakpoint:
                    isRunning = false
                    statusMessage = "Breakpoint"
                    audioEngine.pause()
                case .cpuCrash:
                    isRunning = false
                    statusMessage = "CPU Crash"
                    audioEngine.pause()
                default:
                    break
                }
            }

            // Sleep until next scheduled frame time
            let now = DispatchTime.now().uptimeNanoseconds
            if now < nextFrameTime {
                let sleepTime = nextFrameTime - now
                try? await Task.sleep(nanoseconds: sleepTime)
            }
            // Schedule next frame (prevents timing drift)
            nextFrameTime += targetFrameTime
        }
    }

    /// Updates the FPS counter.
    private func updateFPS() {
        frameCounter += 1

        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)

        if elapsed >= 1.0 {
            fps = Int(Double(frameCounter) / elapsed)
            frameCounter = 0
            lastFPSUpdate = now
        }
    }

    // =========================================================================
    // MARK: - Server Shutdown
    // =========================================================================

    /// Shuts down the AtticServer if we launched it.
    ///
    /// Sends the shutdown command via CLI socket, which causes the server
    /// to gracefully stop. This should be called before quitting the app
    /// when the user wants to shut down everything.
    func shutdownServer() async {
        guard mode == .client else { return }

        // If we have a CLI socket path, send shutdown command
        if let socketPath = cliSocketPath {
            let cliClient = CLISocketClient()
            do {
                try await cliClient.connect(to: socketPath)
                _ = try await cliClient.send(.shutdown)
                await cliClient.disconnect()
                print("[AtticGUI] Sent shutdown to AtticServer")
            } catch {
                print("[AtticGUI] Failed to send shutdown: \(error)")
                // Fall back to terminating by PID if CLI fails
                if let pid = serverPID {
                    kill(pid, SIGTERM)
                    print("[AtticGUI] Sent SIGTERM to AtticServer (PID: \(pid))")
                }
            }
        } else if let pid = serverPID {
            // No socket path, terminate by PID
            kill(pid, SIGTERM)
            print("[AtticGUI] Sent SIGTERM to AtticServer (PID: \(pid))")
        }

        serverPID = nil
        cliSocketPath = nil
    }

    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    /// Cleans up resources.
    private func cleanup() async {
        // Cancel receiver tasks
        frameReceiverTask?.cancel()
        audioReceiverTask?.cancel()
        frameReceiverTask = nil
        audioReceiverTask = nil

        // Disconnect client
        await client?.disconnect()
        client = nil

        // Cancel emulation task
        emulationTask?.cancel()
        emulationTask = nil

        // Stop audio
        audioEngine.stop()
    }

    /// Called to clean up when the view model is deallocated.
    deinit {
        // Cancel tasks synchronously
        frameReceiverTask?.cancel()
        audioReceiverTask?.cancel()
        emulationTask?.cancel()
    }
}

// =============================================================================
// MARK: - Menu Commands
// =============================================================================

/// Custom menu commands for the Attic application.
struct AtticCommands: Commands {
    @ObservedObject var viewModel: AtticViewModel

    var body: some Commands {
        // Replace the standard New/Open menu with our disk operations
        CommandGroup(replacing: .newItem) {
            Button("Open Disk Image...") {
                // TODO: Show file picker for .atr files
            }
            .keyboardShortcut("O")

            Divider()

            Button("Save State...") {
                // TODO: Save state dialog
            }
            .keyboardShortcut("S")

            Button("Load State...") {
                // TODO: Load state dialog
            }
            .keyboardShortcut("L")
        }

        // Emulator menu
        CommandMenu("Emulator") {
            Button(viewModel.isRunning ? "Pause" : "Run") {
                Task {
                    if viewModel.isRunning {
                        await viewModel.pause()
                    } else {
                        await viewModel.start()
                    }
                }
            }
            .keyboardShortcut(viewModel.isRunning ? "." : "R")

            Divider()

            Button("Reset (Cold)") {
                Task { await viewModel.reset(cold: true) }
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])

            Button("Reset (Warm)") {
                Task { await viewModel.reset(cold: false) }
            }
            .keyboardShortcut("R", modifiers: [.command, .option])

            Divider()

            // Show current mode
            Text("Mode: \(viewModel.mode == .client ? "Client" : "Embedded")")
                .foregroundColor(.secondary)
        }

        // View menu additions
        CommandGroup(after: .windowSize) {
            Divider()

            Button("Actual Size (1x)") {
                // TODO: Resize window
            }
            .keyboardShortcut("1")

            Button("Double Size (2x)") {
                // TODO: Resize window
            }
            .keyboardShortcut("2")

            Button("Triple Size (3x)") {
                // TODO: Resize window
            }
            .keyboardShortcut("3")
        }

        // Hide the standard Close menu item (we handle it in app termination)
        CommandGroup(replacing: .saveItem) {
            // Empty - removes Save/Save As which we don't need
        }

        // App termination options
        // Replace the default Quit command with our shutdown options
        CommandGroup(replacing: .appTermination) {
            // Close window / disconnect from server but leave it running
            Button("Close") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("W")

            Divider()

            // Shutdown server and quit
            Button("Shutdown All") {
                Task {
                    await viewModel.shutdownServer()
                    // Give server a moment to shut down, then quit
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await MainActor.run {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .keyboardShortcut("Q")
        }
    }
}

