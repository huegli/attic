// =============================================================================
// ContentView.swift - Main Window Content
// =============================================================================
//
// This file defines the main content view for the Attic GUI application.
// It contains:
// - The emulator display (Metal view)
// - Control panel with START/SELECT/OPTION buttons
// - Status bar showing running state and FPS
//
// Layout:
// ┌─────────────────────────────────────────────────────┐
// │                                                     │
// │              Emulator Display                       │
// │              (Metal View)                           │
// │              384x240 @ 3x                           │
// │                                                     │
// ├─────────────────────────────────────────────────────┤
// │  [START] [SELECT] [OPTION]  │  Status | 60 FPS     │
// └─────────────────────────────────────────────────────┘
//
// =============================================================================

import SwiftUI
import AtticCore
import AppKit

/// The main content view for the Attic window.
///
/// This view contains the emulator display and control panel.
/// It receives the view model from the environment.
struct ContentView: View {
    // =========================================================================
    // MARK: - Environment
    // =========================================================================

    /// The shared view model containing emulator state.
    @EnvironmentObject var viewModel: AtticViewModel

    // =========================================================================
    // MARK: - Body
    // =========================================================================

    var body: some View {
        VStack(spacing: 0) {
            // Emulator display area - Metal view
            EmulatorDisplayView()
                .frame(minWidth: 384, minHeight: 240)
                .aspectRatio(384.0/240.0, contentMode: .fit)

            // Control panel and status bar
            ControlPanelView()
        }
        .background(Color.black)
        .onAppear {
            // Initialize emulator when view appears
            Task {
                await viewModel.initializeEmulator()
            }
        }
    }
}

// =============================================================================
// MARK: - Emulator Display View
// =============================================================================

/// View for the emulator display using Metal rendering.
///
/// This view contains the Metal-based emulator display. When the emulator
/// is not initialized or fails, it shows a placeholder.
///
/// Keyboard Input:
/// We overlay a KeyEventView on top of the Metal view to capture keyboard
/// events. KeyEventView is an NSViewRepresentable that becomes first responder
/// and receives all keyboard events, which are then forwarded to the view model.
struct EmulatorDisplayView: View {
    @EnvironmentObject var viewModel: AtticViewModel

    var body: some View {
        ZStack {
            // Metal view for rendering (always present)
            EmulatorMetalView(viewModel: viewModel)

            // Keyboard event capture overlay
            // This transparent view captures all keyboard events and forwards
            // them to the view model for processing.
            KeyEventView(
                onKeyDown: { event in
                    viewModel.handleKeyDown(event)
                },
                onKeyUp: { event in
                    viewModel.handleKeyUp(event)
                },
                onFlagsChanged: { event in
                    viewModel.handleFlagsChanged(event)
                }
            )

            // Overlay message when not initialized
            if !viewModel.isInitialized {
                InitializationOverlay(viewModel: viewModel)
            }
        }
    }
}

// =============================================================================
// MARK: - Initialization Overlay
// =============================================================================

/// Overlay shown when the emulator is not yet initialized.
///
/// Displays initialization status or error messages.
struct InitializationOverlay: View {
    @ObservedObject var viewModel: AtticViewModel

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)

            VStack(spacing: 20) {
                Text("ATTIC")
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("Atari 800 XL Emulator")
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                if let error = viewModel.initializationError {
                    // Show error
                    VStack(spacing: 8) {
                        Text("Initialization Error")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.red)

                        Text(error)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Text("Place ATARIXL.ROM and ATARIBAS.ROM in Resources/ROM/")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 10)
                    }
                    .padding(.top, 20)
                } else {
                    // Show loading
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding(.top, 30)

                    Text("Initializing...")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
}

// =============================================================================
// MARK: - Control Panel View
// =============================================================================

/// The control panel with console buttons and status display.
///
/// Console Keys:
/// The Atari 800 XL has three console keys: START, SELECT, and OPTION.
/// These are mapped to F1, F2, and F3 on the keyboard. The buttons here
/// provide an alternative way to trigger these keys via mouse click.
struct ControlPanelView: View {
    @EnvironmentObject var viewModel: AtticViewModel

    var body: some View {
        HStack {
            // Console buttons
            // These buttons trigger the same actions as F1/F2/F3 keys.
            // On press, they set the console key; on release, they clear it.
            HStack(spacing: 12) {
                ConsoleButton(
                    label: "START",
                    key: "F1",
                    isPressed: viewModel.keyboardHandler.startPressed,
                    onPress: {
                        viewModel.setConsoleKeys(
                            start: true,
                            select: viewModel.keyboardHandler.selectPressed,
                            option: viewModel.keyboardHandler.optionPressed
                        )
                    },
                    onRelease: {
                        viewModel.setConsoleKeys(
                            start: false,
                            select: viewModel.keyboardHandler.selectPressed,
                            option: viewModel.keyboardHandler.optionPressed
                        )
                    }
                )

                ConsoleButton(
                    label: "SELECT",
                    key: "F2",
                    isPressed: viewModel.keyboardHandler.selectPressed,
                    onPress: {
                        viewModel.setConsoleKeys(
                            start: viewModel.keyboardHandler.startPressed,
                            select: true,
                            option: viewModel.keyboardHandler.optionPressed
                        )
                    },
                    onRelease: {
                        viewModel.setConsoleKeys(
                            start: viewModel.keyboardHandler.startPressed,
                            select: false,
                            option: viewModel.keyboardHandler.optionPressed
                        )
                    }
                )

                ConsoleButton(
                    label: "OPTION",
                    key: "F3",
                    isPressed: viewModel.keyboardHandler.optionPressed,
                    onPress: {
                        viewModel.setConsoleKeys(
                            start: viewModel.keyboardHandler.startPressed,
                            select: viewModel.keyboardHandler.selectPressed,
                            option: true
                        )
                    },
                    onRelease: {
                        viewModel.setConsoleKeys(
                            start: viewModel.keyboardHandler.startPressed,
                            select: viewModel.keyboardHandler.selectPressed,
                            option: false
                        )
                    }
                )

                // HELP key (XL/XE only)
                ConsoleButton(
                    label: "HELP",
                    key: "F4",
                    isPressed: false,  // HELP doesn't have persistent state
                    onPress: {
                        viewModel.pressHelpKey()
                    },
                    onRelease: {
                        viewModel.releaseHelpKey()
                    }
                )

                // Divider between keyboard keys and system reset
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)

                // RESET button (warm reset)
                ActionButton(
                    label: "RESET",
                    key: "F5",
                    action: {
                        Task {
                            await viewModel.reset(cold: false)
                        }
                    }
                )
            }
            .padding(.leading)

            Spacer()

            // Status display
            HStack(spacing: 16) {
                // Mounted disk names (shown only when disks are mounted)
                if !viewModel.mountedDiskNames.isEmpty {
                    Text(viewModel.mountedDiskNames)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // Running state
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.statusMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }

                // FPS counter
                Text("\(viewModel.fps) FPS")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.trailing)
        }
        .frame(height: 44)
        .background(Color(white: 0.15))
    }
}

// =============================================================================
// MARK: - Action Button
// =============================================================================

/// A styled button for single-action controls (like RESET).
///
/// Unlike ConsoleButton which tracks press/release, ActionButton triggers
/// a single action on click.
struct ActionButton: View {
    /// The label text (e.g., "RESET").
    let label: String

    /// The keyboard shortcut hint (e.g., "F5").
    let key: String

    /// The action to perform when clicked.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(key)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(width: 60, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}

// =============================================================================
// MARK: - Console Button
// =============================================================================

/// A styled button for console controls (START, SELECT, OPTION, HELP).
///
/// Console buttons support press and release actions to match the Atari's
/// console key behavior. The button appearance changes when pressed
/// (either via keyboard or mouse).
struct ConsoleButton: View {
    /// The label text (e.g., "START").
    let label: String

    /// The keyboard shortcut hint (e.g., "F1").
    let key: String

    /// Whether the button is currently pressed (bound to keyboard state).
    let isPressed: Bool

    /// Called when the button is pressed.
    let onPress: () -> Void

    /// Called when the button is released.
    let onRelease: () -> Void

    /// Local state for mouse press tracking.
    @State private var isMousePressed = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
            Text(key)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: 60, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 4)
                // Show pressed state from either keyboard or mouse
                .fill((isPressed || isMousePressed) ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .foregroundColor(.white)
        // Handle mouse press/release with gesture
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isMousePressed {
                        isMousePressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    isMousePressed = false
                    onRelease()
                }
        )
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#Preview {
    ContentView()
        .environmentObject(AtticViewModel())
        .frame(width: 1152, height: 720)
}
