// =============================================================================
// KeyEventView.swift - NSView for Keyboard Event Capture
// =============================================================================
//
// This file provides a SwiftUI-compatible view that captures keyboard events.
// SwiftUI's built-in keyboard handling (.onKeyPress) only handles key down
// events and doesn't provide raw key codes. For an emulator, we need:
// - Key down events with key codes
// - Key up events (to know when keys are released)
// - Modifier flag changes
// - Ability to handle held keys
//
// Solution: Local Event Monitor
// -----------------------------
// We use NSEvent.addLocalMonitorForEvents to capture keyboard events at the
// application level. This is more reliable than trying to make an NSView
// become first responder, which can fail in SwiftUI layouts.
//
// The local monitor captures all keyboard events sent to our application,
// allowing the emulator to receive input regardless of which view has focus.
//
// Architecture:
// 1. KeyEventView (SwiftUI) - The representable wrapper
// 2. KeyCaptureNSView (AppKit) - Sets up event monitors and handles focus
// 3. Callbacks - Closures that propagate events to SwiftUI
//
// =============================================================================

import SwiftUI
import AppKit

// =============================================================================
// MARK: - KeyEventView (SwiftUI Wrapper)
// =============================================================================

/// A SwiftUI view that captures keyboard events using AppKit.
///
/// This view wraps an NSView that handles keyboard events and passes them
/// to the provided callbacks. Use this when you need full keyboard control
/// including key up events and raw key codes.
///
/// Usage:
///
///     KeyEventView(
///         onKeyDown: { event in
///             print("Key down: \(event.keyCode)")
///         },
///         onKeyUp: { event in
///             print("Key up: \(event.keyCode)")
///         },
///         onFlagsChanged: { event in
///             print("Modifiers: \(event.modifierFlags)")
///         }
///     )
///
struct KeyEventView: NSViewRepresentable {
    /// Called when a key is pressed.
    var onKeyDown: ((NSEvent) -> Void)?

    /// Called when a key is released.
    var onKeyUp: ((NSEvent) -> Void)?

    /// Called when modifier flags change (Shift, Control, etc.).
    var onFlagsChanged: ((NSEvent) -> Void)?

    /// Creates the NSView.
    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onKeyUp = onKeyUp
        view.onFlagsChanged = onFlagsChanged
        return view
    }

    /// Updates the NSView when SwiftUI state changes.
    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onKeyUp = onKeyUp
        nsView.onFlagsChanged = onFlagsChanged
    }

    /// Makes the view focusable and become first responder.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {}
}

// =============================================================================
// MARK: - KeyCaptureNSView (AppKit Implementation)
// =============================================================================

/// An NSView that captures keyboard events and forwards them via callbacks.
///
/// This view uses local event monitors to capture keyboard events at the
/// application level. This is more reliable than relying on first responder
/// status, which can be tricky in SwiftUI layouts.
///
/// Event monitors:
/// - keyDown: Captures key press events
/// - keyUp: Captures key release events
/// - flagsChanged: Captures modifier key changes (Shift, Control, etc.)
///
class KeyCaptureNSView: NSView {
    // Callbacks for keyboard events
    var onKeyDown: ((NSEvent) -> Void)?
    var onKeyUp: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    // Event monitors - stored so we can remove them later
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var flagsChangedMonitor: Any?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupEventMonitors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEventMonitors()
    }

    deinit {
        // Use assumeIsolated since NSView deinit runs on main thread
        // but Swift 6 requires explicit isolation context
        MainActor.assumeIsolated {
            self.removeEventMonitors()
        }
    }

    // =========================================================================
    // MARK: - Event Monitors
    // =========================================================================

    /// Sets up local event monitors for keyboard events.
    ///
    /// Local event monitors capture events sent to the application.
    /// Unlike global monitors (which require accessibility permissions),
    /// local monitors only see events when our app is active.
    ///
    /// We return the event from the handler to allow it to propagate
    /// to other handlers (like menu shortcuts). For regular keys, we
    /// return nil to consume the event and prevent the system beep.
    private func setupEventMonitors() {
        // Monitor key down events
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Don't capture Command key combinations (menu shortcuts)
            if event.modifierFlags.contains(.command) {
                return event
            }

            self?.onKeyDown?(event)
            // Return nil to consume the event (prevents system beep)
            return nil
        }

        // Monitor key up events
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            // Don't capture Command key combinations
            if event.modifierFlags.contains(.command) {
                return event
            }

            self?.onKeyUp?(event)
            // Return nil to consume the event
            return nil
        }

        // Monitor modifier flag changes
        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.onFlagsChanged?(event)
            // Return the event to allow modifier changes to propagate
            return event
        }
    }

    /// Removes all event monitors.
    ///
    /// This must be called when the view is deallocated to prevent
    /// memory leaks and crashes from dangling event handlers.
    private func removeEventMonitors() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
            keyUpMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
    }

    // =========================================================================
    // MARK: - First Responder (Fallback)
    // =========================================================================

    /// Returns true to indicate this view can become first responder.
    ///
    /// While we primarily use event monitors, we still accept first responder
    /// as a fallback mechanism.
    override var acceptsFirstResponder: Bool {
        true
    }

    /// Called when the view becomes first responder.
    override func becomeFirstResponder() -> Bool {
        true
    }

    /// Called when the view resigns first responder.
    override func resignFirstResponder() -> Bool {
        true
    }

    // =========================================================================
    // MARK: - Focus Handling
    // =========================================================================

    /// Called when the view is added to a window.
    ///
    /// We make the window key and request focus to help ensure we're active.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window {
            // Make the window key (active) so it receives keyboard events
            window.makeKey()
            // Request first responder status
            window.makeFirstResponder(self)
        }
    }

    /// Request focus when clicked.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
}

// =============================================================================
// MARK: - NSEvent Extensions
// =============================================================================

extension NSEvent {
    /// Returns the characters without applying modifiers.
    ///
    /// This is useful for getting the base key character regardless of
    /// whether Shift or other modifiers are pressed.
    var charactersIgnoringAllModifiers: String? {
        charactersIgnoringModifiers
    }
}
