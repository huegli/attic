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
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Called when the app finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Attic GUI launched")

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
class AtticViewModel: ObservableObject {
    /// The emulator engine.
    let emulator: EmulatorEngine

    /// Current emulator running state for UI binding.
    @Published var isRunning: Bool = false

    /// Status message for display.
    @Published var statusMessage: String = "Ready"

    /// FPS counter.
    @Published var fps: Int = 0

    /// Creates a new view model.
    init() {
        self.emulator = EmulatorEngine()
    }

    /// Starts the emulator.
    @MainActor
    func start() async {
        await emulator.resume()
        isRunning = true
        statusMessage = "Running"
    }

    /// Pauses the emulator.
    @MainActor
    func pause() async {
        await emulator.pause()
        isRunning = false
        statusMessage = "Paused"
    }

    /// Performs a cold reset.
    @MainActor
    func reset() async {
        await emulator.reset(cold: true)
        statusMessage = "Reset"
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
