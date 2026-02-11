// =============================================================================
// AtticApp.swift - SwiftUI Application Entry Point
// =============================================================================
//
// This is the main entry point for the Attic GUI application.
// It defines the SwiftUI App struct which creates the main window.
//
// The GUI connects to AtticServer via the AESP protocol. The server runs
// as a subprocess and handles all emulation. The GUI receives video frames
// and audio samples via the protocol and sends input back.
//
// Architecture:
// The App struct creates a single main window containing the ContentView.
// AtticViewModel manages the AESP protocol client connection to the server.
//
// =============================================================================

import SwiftUI
import UniformTypeIdentifiers
import AtticCore
import AtticProtocol

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
        _viewModel = StateObject(wrappedValue: AtticViewModel())
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
    /// Callback for handling file open events from Finder.
    /// Set by AtticViewModel during initialization so the AppDelegate
    /// can forward file open requests to the view model.
    /// Marked @MainActor because AppDelegate and the callback both run on the main thread.
    @MainActor static var onOpenFile: ((URL) -> Void)?

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

    /// Called when a file is opened via Finder (double-click on .atr file, drag-and-drop, etc.).
    ///
    /// Forwards the file URL to the view model via the static callback.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("[AtticGUI] Open file: \(url.path)")
            AppDelegate.onOpenFile?(url)
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
/// Connects to AtticServer via the AESP protocol. The view model:
/// 1. Launches AtticServer as a subprocess
/// 2. Connects via AESPClient
/// 3. Receives video frames via AsyncStream
/// 4. Receives audio samples via AsyncStream
/// 5. Sends input via protocol messages
///
/// Note: @MainActor ensures all UI-related updates happen on the main thread.
@MainActor
class AtticViewModel: ObservableObject {
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

    /// Task for periodic status polling (disk mounts, running state).
    /// Polls the server every few seconds so the GUI reflects changes made
    /// by other clients (e.g. CLI mount/unmount operations).
    private var statusPollingTask: Task<Void, Never>?

    /// Task for heartbeat monitoring via PING/PONG.
    /// Detects server loss and triggers the "Server Connection Lost" alert.
    private var heartbeatTask: Task<Void, Never>?

    /// PID of the AtticServer process if we launched it.
    /// Used for shutdown functionality.
    private var serverPID: Int32?

    /// Path to the CLI socket for sending the shutdown command to AtticServer.
    private var cliSocketPath: String?

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

    /// FPS counter (driven by FrameRateMonitor).
    @Published var fps: Int = 0

    /// Mounted disk names for display in the status bar (e.g. "D1:GAME.ATR").
    /// Updated when the AESP status response includes disk information.
    @Published var mountedDiskNames: String = ""

    /// Whether the "Server Connection Lost" alert should be displayed.
    /// Set to true by the heartbeat monitor when the server stops responding.
    @Published var showServerLostAlert: Bool = false

    /// Whether audio is enabled.
    @Published var isAudioEnabled: Bool = true {
        didSet {
            audioEngine.isEnabled = isAudioEnabled
            if !isAudioEnabled {
                audioEngine.clearBuffer()
            }
        }
    }

    /// Whether joystick emulation is enabled.
    /// When enabled, arrow keys map to joystick directions and spacebar maps
    /// to the fire button (port 0). Toggling off resets all joystick state
    /// so no directions remain "stuck".
    @Published var isJoystickEmulationEnabled: Bool = false {
        didSet {
            if !isJoystickEmulationEnabled {
                resetJoystickState()
            }
        }
    }

    // =========================================================================
    // MARK: - Internal State
    // =========================================================================

    /// Frame rate monitor for FPS calculation and drop detection.
    /// Tracks frame timing, detects drops (frames exceeding 1.5× target interval),
    /// and provides statistics (average/min/max frame time, jitter).
    private let frameRateMonitor = FrameRateMonitor()

    // Joystick emulation key-held tracking.
    // Each boolean tracks whether the corresponding key is currently held down.
    // Multiple keys can be held simultaneously for diagonal movement.
    private var joystickUpHeld: Bool = false
    private var joystickDownHeld: Bool = false
    private var joystickLeftHeld: Bool = false
    private var joystickRightHeld: Bool = false
    private var joystickTriggerHeld: Bool = false

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new view model.
    init() {
        self.audioEngine = AudioEngine()
        self.keyboardHandler = KeyboardInputHandler()
    }

    /// Connects to the AtticServer via AESP protocol.
    ///
    /// This should be called when the view appears.
    func initializeEmulator() async {
        await initializeClientMode()

        // Register file open handler so AppDelegate can forward
        // Finder file-open events (double-click, drag-and-drop) to us
        AppDelegate.onOpenFile = { [weak self] url in
            guard let self = self else { return }
            Task { @MainActor in
                await self.bootFile(url: url)
            }
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

                        Try starting the server manually:
                          swift run AtticServer
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
                    """
                statusMessage = "Server Not Found"
                await cleanup()

            case .launchFailed(let error):
                print("[AtticGUI] Failed to launch AtticServer: \(error)")
                initializationError = """
                    Failed to launch AtticServer: \(error.localizedDescription)

                    Try starting it manually:
                      swift run AtticServer
                    """
                statusMessage = "Launch Failed"
                await cleanup()

            case .socketTimeout(let pid):
                print("[AtticGUI] AtticServer started (PID: \(pid)) but socket not ready")
                initializationError = """
                    AtticServer started but socket not ready.

                    Try starting the server manually:
                      swift run AtticServer
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

            // Start receiving frames, audio, periodic status polling, and heartbeat
            startFrameReceiver()
            startAudioReceiver()
            startStatusPolling()
            startHeartbeat()

            // Discover the CLI socket path if we don't already have one.
            // This is needed when connecting to a pre-existing AtticServer
            // that wasn't launched by this GUI instance. Without the CLI
            // socket path, the shutdown command can't reach the server.
            if cliSocketPath == nil {
                let cliClient = CLISocketClient()
                if let discoveredPath = cliClient.discoverSocket() {
                    cliSocketPath = discoveredPath
                    print("[AtticGUI] Discovered CLI socket: \(discoveredPath)")
                }
            }

            isInitialized = true
            isRunning = true
            statusMessage = "Connected"
            audioEngine.resume()

            // Fetch initial disk status from the server
            await refreshDiskStatus()

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

    /// Starts periodic status polling to detect changes made by other clients.
    ///
    /// Polls the server every 3 seconds for the current status including
    /// mounted disk information. This ensures the GUI reflects CLI-initiated
    /// mount/unmount operations without requiring a push notification mechanism.
    private func startStatusPolling() {
        statusPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
                guard !Task.isCancelled else { break }
                await self?.refreshDiskStatus()
            }
        }
    }

    /// Starts the heartbeat monitor that detects server loss.
    ///
    /// Every 5 seconds, sends a PING to the server and checks whether a PONG
    /// has been received within the last 10 seconds. If the server stops
    /// responding, sets `showServerLostAlert` to trigger a user-facing alert.
    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            // Wait 5 seconds before the first check to let the connection settle
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            while !Task.isCancelled {
                guard let self = self, let client = self.client else { break }

                // Send PING
                await client.ping()

                // Wait 5 seconds for the PONG to arrive
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }

                // Check if we received a PONG recently (within last 10 seconds)
                let lastPong = await client.lastPongReceived
                let stale: Bool
                if let lastPong = lastPong {
                    stale = Date().timeIntervalSince(lastPong) > 10.0
                } else {
                    // Never received a PONG — server is not responding
                    stale = true
                }

                if stale {
                    print("[AtticGUI] Heartbeat: server not responding, showing alert")
                    self.showServerLostAlert = true
                    break
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Control Methods
    // =========================================================================

    /// Starts/resumes the emulator.
    func start() async {
        guard isInitialized else { return }
        await client?.resume()
        audioEngine.resume()
        isRunning = true
        statusMessage = "Running"
    }

    /// Pauses the emulator.
    func pause() async {
        await client?.pause()
        audioEngine.pause()
        isRunning = false
        statusMessage = "Paused"
    }

    /// Performs a reset.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    func reset(cold: Bool = true) async {
        await client?.reset(cold: cold)
        audioEngine.clearBuffer()
        keyboardHandler.reset()
        if isJoystickEmulationEnabled { resetJoystickState() }
        statusMessage = cold ? "Cold Reset" : "Warm Reset"
    }

    // =========================================================================
    // MARK: - Boot File
    // =========================================================================

    /// Boots the emulator with a file (disk image, executable, BASIC program, etc.).
    ///
    /// Sends a boot file command to the server via AESP protocol, which loads
    /// the file and performs a cold start.
    ///
    /// - Parameter url: URL of the file to boot.
    func bootFile(url: URL) async {
        let path = url.path

        await client?.bootFile(filePath: path)
        audioEngine.clearBuffer()
        keyboardHandler.reset()
        isRunning = true
        statusMessage = "Booting \(url.lastPathComponent)..."
        // Refresh disk status after boot so the status bar shows the new disk
        await refreshDiskStatus()
    }

    // =========================================================================
    // MARK: - Disk Status
    // =========================================================================

    /// Requests the current status (including mounted disks) from the server
    /// and updates the `mountedDiskNames` published property.
    ///
    /// Sends an AESP status request and parses the enhanced response.
    func refreshDiskStatus() async {
        guard let client = client else { return }
        let status = await client.requestStatusWithDisks()

        // Build the new display string for the status bar
        let newDiskNames: String
        if status.mountedDrives.isEmpty {
            newDiskNames = ""
        } else {
            newDiskNames = status.mountedDrives
                .map { "D\($0.drive):\($0.filename)" }
                .joined(separator: "  ")
        }

        // Only update @Published property when the value actually changes.
        // Unconditional assignment fires objectWillChange every poll cycle,
        // which causes SwiftUI to rebuild menus unnecessarily.
        if newDiskNames != mountedDiskNames {
            mountedDiskNames = newDiskNames
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

        // When joystick emulation is active, intercept arrow keys and spacebar
        // before they reach the normal keyboard handler. This allows games to be
        // played using the keyboard as a virtual joystick on port 0.
        if isJoystickEmulationEnabled {
            switch event.keyCode {
            case MacKeyCode.upArrow:
                joystickUpHeld = true
                sendJoystickState()
                return
            case MacKeyCode.downArrow:
                joystickDownHeld = true
                sendJoystickState()
                return
            case MacKeyCode.leftArrow:
                joystickLeftHeld = true
                sendJoystickState()
                return
            case MacKeyCode.rightArrow:
                joystickRightHeld = true
                sendJoystickState()
                return
            case MacKeyCode.space:
                joystickTriggerHeld = true
                sendJoystickState()
                return
            default:
                break  // Fall through to normal keyboard handling
            }
        }

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
            // Send to server via AESP protocol
            Task {
                await client?.sendKeyDown(
                    keyChar: keyChar,
                    keyCode: keyCode,
                    shift: atariShift,
                    control: atariControl
                )
            }
        }

        // Update console keys
        sendConsoleKeys()
    }

    /// Handles a key up event from the keyboard.
    func handleKeyUp(_ event: NSEvent) {
        // When joystick emulation is active, intercept arrow/space key releases
        // to clear the held state. Without this, releasing a direction key would
        // also trigger a sendKeyUp which could interfere with keyboard input.
        if isJoystickEmulationEnabled {
            switch event.keyCode {
            case MacKeyCode.upArrow:
                joystickUpHeld = false
                sendJoystickState()
                return
            case MacKeyCode.downArrow:
                joystickDownHeld = false
                sendJoystickState()
                return
            case MacKeyCode.leftArrow:
                joystickLeftHeld = false
                sendJoystickState()
                return
            case MacKeyCode.rightArrow:
                joystickRightHeld = false
                sendJoystickState()
                return
            case MacKeyCode.space:
                joystickTriggerHeld = false
                sendJoystickState()
                return
            default:
                break  // Fall through to normal key up handling
            }
        }

        if keyboardHandler.keyUp(keyCode: event.keyCode) {
            // Release the key
            Task {
                await client?.sendKeyUp()
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
            await client?.sendConsoleKeys(
                start: consoleKeys.start,
                select: consoleKeys.select,
                option: consoleKeys.option
            )
        }
    }

    /// Sends console key states (for button presses).
    func setConsoleKeys(start: Bool, select: Bool, option: Bool) {
        Task {
            await client?.sendConsoleKeys(
                start: start,
                select: select,
                option: option
            )
        }
    }

    /// Presses the HELP key (for HELP button).
    func pressHelpKey() {
        Task {
            await client?.sendKeyDown(
                keyChar: 0,
                keyCode: AtariKeyCode.help,
                shift: false,
                control: false
            )
        }
    }

    /// Releases the HELP key (for HELP button).
    func releaseHelpKey() {
        Task {
            await client?.sendKeyUp()
        }
    }

    // =========================================================================
    // MARK: - Joystick Emulation
    // =========================================================================

    /// Sends the current joystick state to the server based on held key state.
    ///
    /// Reads the five key-held booleans and dispatches to the AESP client.
    private func sendJoystickState() {
        let up = joystickUpHeld
        let down = joystickDownHeld
        let left = joystickLeftHeld
        let right = joystickRightHeld
        let trigger = joystickTriggerHeld

        Task {
            await client?.sendJoystick(
                port: 0,
                up: up,
                down: down,
                left: left,
                right: right,
                trigger: trigger
            )
        }
    }

    /// Resets all joystick held state and sends the neutral position.
    ///
    /// Called when joystick emulation is toggled off or after an emulator reset,
    /// to ensure no directions remain "stuck" from previously held keys.
    private func resetJoystickState() {
        joystickUpHeld = false
        joystickDownHeld = false
        joystickLeftHeld = false
        joystickRightHeld = false
        joystickTriggerHeld = false
        sendJoystickState()
    }

    /// Updates the FPS counter using the frame rate monitor.
    ///
    /// Records a frame timestamp and updates the published `fps` property
    /// when the monitor recalculates (approximately once per second).
    private func updateFPS() {
        frameRateMonitor.recordFrame()
        fps = frameRateMonitor.currentFPS
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
        statusPollingTask?.cancel()
        heartbeatTask?.cancel()
        frameReceiverTask = nil
        audioReceiverTask = nil
        statusPollingTask = nil
        heartbeatTask = nil

        // Disconnect client
        await client?.disconnect()
        client = nil

        // Stop audio
        audioEngine.stop()
    }

    /// Called to clean up when the view model is deallocated.
    deinit {
        // Cancel tasks synchronously
        frameReceiverTask?.cancel()
        audioReceiverTask?.cancel()
        statusPollingTask?.cancel()
        heartbeatTask?.cancel()
    }
}

// =============================================================================
// MARK: - Menu Commands
// =============================================================================

/// Custom menu commands for the Attic application.
struct AtticCommands: Commands {
    @ObservedObject var viewModel: AtticViewModel

    var body: some Commands {
        // Replace the standard New/Open menu with our file operations
        CommandGroup(replacing: .newItem) {
            Button("Open File...") {
                // Present a file picker for all supported Atari file types.
                // NSOpenPanel is used directly because SwiftUI's fileImporter
                // doesn't easily support the Commands context.
                let panel = NSOpenPanel()
                panel.title = "Open Atari File"
                panel.allowedContentTypes = [
                    "atr", "xfd", "atx", "dcm", "pro",  // Disk images
                    "xex", "com", "exe",                  // Executables
                    "bas", "lst",                         // BASIC programs
                    "rom", "car",                         // Cartridges
                    "cas",                                // Cassettes
                ].compactMap { UTType(filenameExtension: $0) }
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false

                if panel.runModal() == .OK, let url = panel.url {
                    Task {
                        await viewModel.bootFile(url: url)
                    }
                }
            }
            .keyboardShortcut("O")
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

            // Joystick emulation toggle: maps arrow keys to joystick directions
            // and spacebar to fire (port 0). Renders as a checkmark menu item.
            Toggle("Joystick Emulation", isOn: $viewModel.isJoystickEmulationEnabled)
                .keyboardShortcut("J")
        }

        // About dialog: replaces the standard "About" menu item in the app menu
        // with a customized version showing the Attic application info.
        CommandGroup(replacing: .appInfo) {
            Button("About Attic") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationName: "Attic",
                    .applicationVersion: "1.0",
                    .version: "1",
                    .credits: NSAttributedString(
                        string: "Atari 800 XL Emulator\nPowered by libatari800",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                ])
            }
        }

        // Full Screen toggle in the View menu.
        // macOS provides a built-in full screen button in the title bar, but since
        // we use .hiddenTitleBar window style, users need a menu/keyboard shortcut.
        CommandGroup(after: .toolbar) {
            Button("Toggle Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("F", modifiers: [.command, .control])
        }

        // Hide the standard Close menu item (we handle it in app termination)
        CommandGroup(replacing: .saveItem) {
            // Empty - removes Save/Save As which we don't need
        }

        // App termination options.
        // Replace the default Quit command with our shutdown options.
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

