// =============================================================================
// AtticApp.swift - SwiftUI Application Entry Point
// =============================================================================
//
// This is the main entry point for the Attic GUI application.
// It defines the SwiftUI App struct which creates the main window.
//
// The GUI application is responsible for:
// - Displaying the Atari screen using Metal rendering
// - Playing audio output
// - Handling keyboard and game controller input
// - Providing a Unix socket for CLI communication
//
// Architecture:
// The App struct creates a single main window containing the ContentView.
// The EmulatorEngine is created as a StateObject and passed to child views.
// This ensures the emulator persists across view updates.
//
// macOS App Lifecycle:
// SwiftUI manages the app lifecycle automatically. Key events:
// - App launch: The @main attribute marks this as the entry point
// - Window creation: The WindowGroup creates the main window
// - App termination: Handled by the system (Cmd-Q or closing window)
//
// =============================================================================

import SwiftUI
import AtticCore

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

    /// The emulator engine, shared across the app.
    /// Using @StateObject ensures it persists across view updates.
    @StateObject private var viewModel = AtticViewModel()

    /// App delegate for handling application lifecycle events.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        print("Attic GUI launched")

        // Bring the app to the foreground and make it the active app
        // This ensures our window receives keyboard events instead of the terminal
        NSApp.activate(ignoringOtherApps: true)

        // TODO: Create Unix socket for CLI communication
        // let socketPath = "/tmp/attic-\(getpid()).sock"
    }

    /// Called when the app is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        print("Attic GUI terminating")

        // TODO: Clean up socket
        // TODO: Save any unsaved state
    }

    /// Called when a file is opened via Finder (double-click on .atr file).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            print("Open file: \(url.path)")
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
/// This class holds the emulator state and provides bindings for the UI.
/// Using ObservableObject allows SwiftUI to update views when state changes.
///
/// The view model also manages the emulation loop, which runs in a background
/// task and executes frames at approximately 60fps.
///
/// Architecture:
/// - EmulatorEngine: Runs the actual emulation (CPU, ANTIC, GTIA, POKEY)
/// - MetalRenderer: Displays the video output
/// - AudioEngine: Plays the audio output from POKEY
/// - KeyboardInputHandler: Maps keyboard events to Atari input
///
/// The emulation loop coordinates all components: it runs a frame of emulation,
/// sends the video frame to the renderer, feeds audio samples to the audio
/// engine, and applies the current keyboard input state.
///
/// Note: @MainActor ensures all UI-related updates happen on the main thread.
@MainActor
class AtticViewModel: ObservableObject {
    /// The emulator engine.
    /// This is the core emulation that wraps libatari800.
    let emulator: EmulatorEngine

    /// The Metal renderer (set by EmulatorMetalView).
    /// This displays the Atari screen using GPU acceleration.
    var renderer: MetalRenderer?

    /// The audio engine for POKEY sound output.
    /// This buffers and plays audio samples generated by the emulator.
    let audioEngine: AudioEngine

    /// The keyboard input handler.
    /// This maps Mac keyboard events to Atari key codes.
    let keyboardHandler: KeyboardInputHandler

    /// Whether the emulator is initialized.
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

    /// The emulation loop task.
    private var emulationTask: Task<Void, Never>?

    /// Frame counter for FPS calculation.
    private var frameCounter: Int = 0

    /// Last FPS update time.
    private var lastFPSUpdate: Date = Date()

    /// Creates a new view model.
    init() {
        self.emulator = EmulatorEngine()
        self.audioEngine = AudioEngine()
        self.keyboardHandler = KeyboardInputHandler()
    }

    /// Initializes the emulator with ROMs.
    ///
    /// This should be called when the view appears. It looks for ROMs
    /// in the standard locations.
    ///
    /// The initialization process:
    /// 1. Find ROM directory (ATARIXL.ROM, ATARIBAS.ROM)
    /// 2. Initialize the emulator engine with ROMs
    /// 3. Configure and start the audio engine
    /// 4. Start the emulation loop
    /// 5. Auto-start emulation
    func initializeEmulator() async {
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
            // libatari800 typically outputs 44100 Hz, 16-bit mono audio
            let audioConfig = await emulator.getAudioConfiguration()
            audioEngine.configure(from: audioConfig)

            // Start audio engine
            do {
                try audioEngine.start()
                // Note: sampleSize from libatari800 is in bytes (1 or 2), convert to bits
                let bitsPerSample = audioConfig.sampleSize * 8
                print("Audio engine started: \(audioConfig.sampleRate) Hz, \(audioConfig.channels) ch, \(bitsPerSample)-bit")
            } catch {
                // Audio failure is non-fatal - continue without sound
                print("Warning: Failed to start audio: \(error.localizedDescription)")
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
                print("Found ROMs at: \(path.path)")
                return path
            }
        }

        print("ROM search paths tried:")
        for path in searchPaths {
            print("  - \(path.path)")
        }

        return nil
    }

    /// Starts the emulator.
    ///
    /// This resumes both the emulation and the audio output.
    func start() async {
        guard isInitialized else { return }
        await emulator.resume()
        audioEngine.resume()
        isRunning = true
        statusMessage = "Running"
    }

    /// Pauses the emulator.
    ///
    /// This pauses both the emulation and the audio output.
    /// The audio buffer is preserved so playback can resume smoothly.
    func pause() async {
        await emulator.pause()
        audioEngine.pause()
        isRunning = false
        statusMessage = "Paused"
    }

    /// Performs a cold reset.
    ///
    /// This clears the audio buffer to prevent old audio from playing
    /// after the reset.
    func reset() async {
        await emulator.reset(cold: true)
        audioEngine.clearBuffer()
        keyboardHandler.reset()
        statusMessage = "Reset"
    }

    // =========================================================================
    // MARK: - Keyboard Input
    // =========================================================================

    /// Handles a key down event from the keyboard.
    ///
    /// Converts the Mac key event to Atari input and sends it to the emulator.
    ///
    /// - Parameter event: The NSEvent for the key press.
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

        // Convert to Atari key
        if let (keyChar, keyCode, atariShift, atariControl) = keyboardHandler.keyDown(
            keyCode: event.keyCode,
            characters: event.characters,
            shift: shift,
            control: control
        ) {
            // Send to emulator
            Task {
                await emulator.pressKey(
                    keyChar: keyChar,
                    keyCode: keyCode,
                    shift: atariShift,
                    control: atariControl
                )
            }
        }

        // Update console keys
        let consoleKeys = keyboardHandler.getConsoleKeys()
        Task {
            await emulator.setConsoleKeys(
                start: consoleKeys.start,
                select: consoleKeys.select,
                option: consoleKeys.option
            )
        }
    }

    /// Handles a key up event from the keyboard.
    ///
    /// - Parameter event: The NSEvent for the key release.
    func handleKeyUp(_ event: NSEvent) {
        if keyboardHandler.keyUp(keyCode: event.keyCode) {
            // Release the key in the emulator
            Task {
                await emulator.releaseKey()
            }
        }

        // Update console keys (in case F1/F2/F3 was released)
        let consoleKeys = keyboardHandler.getConsoleKeys()
        Task {
            await emulator.setConsoleKeys(
                start: consoleKeys.start,
                select: consoleKeys.select,
                option: consoleKeys.option
            )
        }
    }

    /// Handles modifier flags changes (Shift, Control, etc.).
    ///
    /// - Parameter event: The NSEvent for the modifier change.
    func handleFlagsChanged(_ event: NSEvent) {
        keyboardHandler.updateModifiers(
            shift: event.modifierFlags.contains(.shift),
            control: event.modifierFlags.contains(.control),
            option: event.modifierFlags.contains(.option),
            command: event.modifierFlags.contains(.command)
        )
    }

    // =========================================================================
    // MARK: - Emulation Loop
    // =========================================================================

    /// Starts the emulation loop.
    ///
    /// The emulation loop runs as a Task and executes frames at approximately
    /// 60fps. Each frame:
    /// 1. Executes one frame of emulation
    /// 2. Gets the frame buffer
    /// 3. Updates the Metal texture
    /// 4. Updates the FPS counter
    private func startEmulationLoop() {
        emulationTask = Task { [weak self] in
            await self?.emulationLoop()
        }
    }

    /// The main emulation loop.
    ///
    /// This runs at approximately 60fps (the Atari's native frame rate).
    /// Each iteration:
    /// 1. Executes one frame of emulation (CPU, ANTIC, GTIA, POKEY)
    /// 2. Sends the video frame to the Metal renderer
    /// 3. Sends audio samples to the audio engine
    /// 4. Updates the FPS counter
    /// 5. Sleeps to maintain proper timing
    ///
    /// The Atari 800 XL uses NTSC timing, which is approximately 59.94 Hz.
    /// We target 60 fps for simplicity, which is close enough.
    private func emulationLoop() async {
        // Target 60fps = 16.67ms per frame
        let targetFrameTime: UInt64 = 16_666_667  // nanoseconds

        while !Task.isCancelled {
            let frameStart = DispatchTime.now().uptimeNanoseconds

            // Check if we should be running (we're on main actor)
            if isRunning {
                // Execute one frame
                // This runs the 6502 CPU and all hardware for one video frame
                // (~29780 CPU cycles for NTSC)
                let result = await emulator.executeFrame()

                // Get frame buffer and update renderer
                // The frame buffer is 384x240 pixels in BGRA format
                let frameBuffer = await emulator.getFrameBuffer()

                // Get audio samples and feed to audio engine
                // libatari800 generates audio samples during executeFrame()
                // We use getAudioSamples() which returns a Sendable [UInt8] array
                let audioSamples = await emulator.getAudioSamples()
                if !audioSamples.isEmpty {
                    audioEngine.enqueueSamplesFromEmulator(bytes: audioSamples)
                }

                // Update UI (already on main actor)
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

            // Sleep to maintain 60fps
            let frameEnd = DispatchTime.now().uptimeNanoseconds
            let elapsed = frameEnd - frameStart

            if elapsed < targetFrameTime {
                let sleepTime = targetFrameTime - elapsed
                try? await Task.sleep(nanoseconds: sleepTime)
            }
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

    /// Stops the emulation loop.
    ///
    /// This also stops the audio engine to prevent any lingering audio output.
    func stopEmulationLoop() {
        emulationTask?.cancel()
        emulationTask = nil
        audioEngine.stop()
    }

    /// Called to clean up when the view model is deallocated.
    ///
    /// Note: deinit is nonisolated in Swift, so we can only perform
    /// simple cleanup here. We cancel the task directly rather than
    /// calling stopEmulationLoop() which requires actor isolation.
    deinit {
        emulationTask?.cancel()
        // Note: audioEngine.stop() is called in AudioEngine's deinit
    }
}

// =============================================================================
// MARK: - Menu Commands
// =============================================================================

/// Custom menu commands for the Attic application.
///
/// This struct defines additional menu items that appear in the menu bar.
/// SwiftUI's Commands API allows adding to or replacing standard menu items.
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
                Task { await viewModel.reset() }
            }
            .keyboardShortcut("R", modifiers: [.command, .shift])

            Button("Reset (Warm)") {
                Task { await viewModel.emulator.reset(cold: false) }
            }
            .keyboardShortcut("R", modifiers: [.command, .option])
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
    }
}
