// =============================================================================
// EmulatorMetalView.swift - SwiftUI Wrapper for Metal Rendering
// =============================================================================
//
// This file provides a SwiftUI-compatible view for the Metal-based emulator
// display. SwiftUI doesn't have native support for MTKView, so we use
// NSViewRepresentable to bridge the gap.
//
// NSViewRepresentable Protocol:
// -----------------------------
// This protocol allows you to wrap an AppKit NSView for use in SwiftUI.
// It requires implementing:
// - makeNSView(): Creates the initial NSView instance
// - updateNSView(): Updates the view when SwiftUI state changes
//
// Coordinator Pattern:
// -------------------
// The Coordinator class acts as a delegate and stores references that need
// to persist across view updates. Here it holds the MetalRenderer.
//
// Usage:
//
//     EmulatorMetalView(viewModel: viewModel)
//         .aspectRatio(384.0/240.0, contentMode: .fit)
//
// =============================================================================

import SwiftUI
import MetalKit
import AtticCore

// =============================================================================
// MARK: - EmulatorMetalView
// =============================================================================

/// A SwiftUI view that displays the emulator output using Metal.
///
/// This view wraps an MTKView and a MetalRenderer to display the Atari
/// screen. The view model provides frame data that is uploaded to the
/// GPU texture each frame.
struct EmulatorMetalView: NSViewRepresentable {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The view model containing the emulator.
    @ObservedObject var viewModel: AtticViewModel

    // =========================================================================
    // MARK: - Coordinator
    // =========================================================================

    /// Coordinator class that manages the Metal renderer.
    ///
    /// The coordinator persists across view updates and holds the renderer
    /// and any delegate references.
    class Coordinator: NSObject {
        /// The parent view (for accessing view model).
        var parent: EmulatorMetalView

        /// The Metal renderer instance.
        var renderer: MetalRenderer?

        /// The MTKView instance.
        var metalView: MTKView?

        init(_ parent: EmulatorMetalView) {
            self.parent = parent
        }
    }

    /// Creates the coordinator.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // =========================================================================
    // MARK: - NSViewRepresentable
    // =========================================================================

    /// Creates the MTKView and sets up the renderer.
    ///
    /// This is called once when the view is first created.
    func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView()

        // Store reference in coordinator
        context.coordinator.metalView = metalView

        // Create the renderer
        do {
            let renderer = try MetalRenderer(metalView: metalView)
            context.coordinator.renderer = renderer

            // Connect renderer to view model for frame updates
            DispatchQueue.main.async {
                self.viewModel.renderer = renderer
            }
        } catch {
            print("Failed to create MetalRenderer: \(error)")
            // View will show black if renderer fails
        }

        // Make the view focusable for keyboard input
        metalView.becomeFirstResponder()

        return metalView
    }

    /// Updates the view when SwiftUI state changes.
    ///
    /// This is called whenever the SwiftUI view hierarchy is updated.
    /// We don't need to do much here since the renderer updates itself.
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Ensure renderer is connected to view model
        if viewModel.renderer == nil, let renderer = context.coordinator.renderer {
            viewModel.renderer = renderer
        }
    }
}

