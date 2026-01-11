// =============================================================================
// ContentView.swift - Main Window Content
// =============================================================================
//
// This file defines the main content view for the Attic GUI application.
// It contains:
// - The emulator display (placeholder for Metal view)
// - Control panel with START/SELECT/OPTION buttons
// - Status bar showing running state and FPS
//
// Layout:
// ┌─────────────────────────────────────────────────┐
// │                                                 │
// │              Emulator Display                   │
// │              (Metal View)                       │
// │              384x240 @ 3x                       │
// │                                                 │
// ├─────────────────────────────────────────────────┤
// │  [START] [SELECT] [OPTION]  │  Status | 60 FPS │
// └─────────────────────────────────────────────────┘
//
// The Metal rendering will be implemented in Phase 3.
// For now, this shows a placeholder view.
//
// =============================================================================

import SwiftUI
import AtticCore

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
            // Emulator display area
            EmulatorDisplayView()
                .frame(minWidth: 384, minHeight: 240)
                .aspectRatio(384.0/240.0, contentMode: .fit)

            // Control panel and status bar
            ControlPanelView()
        }
        .background(Color.black)
    }
}

// =============================================================================
// MARK: - Emulator Display View
// =============================================================================

/// Placeholder view for the emulator display.
///
/// This will be replaced with a Metal view in Phase 3.
/// For now, it shows a static placeholder.
struct EmulatorDisplayView: View {
    @EnvironmentObject var viewModel: AtticViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background (Atari blue)
                Color(red: 0.0, green: 0.3, blue: 0.6)

                // Placeholder content
                VStack(spacing: 20) {
                    Text("ATTIC")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    Text("Atari 800 XL Emulator")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))

                    Text("Display will appear here")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 20)

                    // Simulated READY prompt
                    VStack(alignment: .leading, spacing: 2) {
                        Text("READY")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                        Text("█")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.white)
                            .opacity(0.8)
                    }
                    .padding(.top, 40)
                }
            }
        }
        // Handle keyboard input
        .focusable()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
            return .handled
        }
    }

    /// Handles keyboard input.
    private func handleKeyPress(_ keyPress: KeyPress) {
        // TODO: Send key to emulator in Phase 5
        print("Key pressed: \(keyPress.characters)")
    }
}

// =============================================================================
// MARK: - Control Panel View
// =============================================================================

/// The control panel with console buttons and status display.
struct ControlPanelView: View {
    @EnvironmentObject var viewModel: AtticViewModel

    var body: some View {
        HStack {
            // Console buttons
            HStack(spacing: 12) {
                ConsoleButton(label: "START", key: "F1") {
                    // TODO: Send START key
                    print("START pressed")
                }

                ConsoleButton(label: "SELECT", key: "F2") {
                    // TODO: Send SELECT key
                    print("SELECT pressed")
                }

                ConsoleButton(label: "OPTION", key: "F3") {
                    // TODO: Send OPTION key
                    print("OPTION pressed")
                }
            }
            .padding(.leading)

            Spacer()

            // Status display
            HStack(spacing: 16) {
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
// MARK: - Console Button
// =============================================================================

/// A styled button for console controls (START, SELECT, OPTION).
struct ConsoleButton: View {
    let label: String
    let key: String
    let action: () -> Void

    @State private var isPressed = false

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
                    .fill(isPressed ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
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
