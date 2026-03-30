// GameControllerHandler.swift
// AtticGUI
//
// Bridges Apple's GameController framework to the Atari 800 XL emulator.
// Monitors physical game controller connections (USB/Bluetooth) and maps
// D-pad, analog stick, and button inputs to Atari joystick directions,
// trigger, and console keys (START/SELECT/OPTION).
//
// Architecture:
// - Runs on @MainActor to match AtticViewModel and avoid data races.
// - Publishes joystick state for the HUD overlay (JoystickOverlayView).
// - Sends input to the server via AESPClient.sendJoystick().
// - Supports up to 2 controllers (Atari ports 0 and 1).
// - Coexists with keyboard joystick emulation (F9 toggle) — both paths
//   feed the same sendJoystick() method; last input wins.

import GameController
import AtticProtocol

// MARK: - Controller Slot

/// Represents one of the two Atari joystick ports and the physical controller
/// currently assigned to it (if any).
struct ControllerSlot {
    /// The physical controller assigned to this slot, or nil if empty.
    var controller: GCController?

    /// The Atari joystick port number (0 or 1).
    let port: UInt8
}

// MARK: - Console Key State

/// Tracks the current state of the three Atari console keys so we can detect
/// changes and avoid flooding the server with redundant messages.
private struct ConsoleKeyState: Equatable {
    var start: Bool = false
    var select: Bool = false
    var option: Bool = false
}

// MARK: - GameControllerHandler

/// Manages physical game controller discovery, connection, and input mapping.
///
/// Usage:
/// 1. Create an instance as a property of AtticViewModel.
/// 2. Call `start(client:)` after the AESP client connects.
/// 3. Call `stop()` during cleanup before disconnecting the client.
/// 4. Read the published joystick state properties for the HUD overlay.
///
/// The handler automatically detects controller connect/disconnect events
/// via NotificationCenter and sets up value-changed handlers on each
/// controller's extended gamepad profile.
@MainActor
final class GameControllerHandler: ObservableObject {

    // =========================================================================
    // MARK: - Published Joystick State (for HUD overlay)
    // =========================================================================

    /// Port 0 direction and trigger state, updated on every input change.
    /// The JoystickOverlayView reads these to show visual feedback.
    @Published var port0Up: Bool = false
    @Published var port0Down: Bool = false
    @Published var port0Left: Bool = false
    @Published var port0Right: Bool = false
    @Published var port0Trigger: Bool = false

    /// Port 1 direction and trigger state.
    @Published var port1Up: Bool = false
    @Published var port1Down: Bool = false
    @Published var port1Left: Bool = false
    @Published var port1Right: Bool = false
    @Published var port1Trigger: Bool = false

    /// Whether any controller is currently connected.
    /// Used by the HUD overlay to decide visibility.
    @Published var hasConnectedController: Bool = false

    // =========================================================================
    // MARK: - Private State
    // =========================================================================

    /// Two controller slots, one per Atari joystick port.
    /// First controller connected gets port 0, second gets port 1.
    private var slots: [ControllerSlot] = [
        ControllerSlot(controller: nil, port: 0),
        ControllerSlot(controller: nil, port: 1)
    ]

    /// Reference to the AESP client for sending joystick/console key messages.
    /// Weak to avoid retain cycles — the client is owned by AtticViewModel.
    private weak var client: AESPClient?

    /// Tracks the last console key state sent to the server.
    /// We only send console key messages when the state actually changes,
    /// avoiding unnecessary network traffic.
    private var lastConsoleKeyState = ConsoleKeyState()

    /// Notification observers for controller connect/disconnect.
    /// Stored so we can remove them in `stop()`.
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    /// Analog stick deadzone threshold (0.0–1.0).
    /// Values below this magnitude are treated as centered (no direction).
    /// 0.25 is a common industry standard that prevents phantom input from
    /// stick drift while remaining responsive to intentional movement.
    private let deadzone: Float = 0.25

    // =========================================================================
    // MARK: - Lifecycle
    // =========================================================================

    /// Starts controller discovery and registers for connection notifications.
    ///
    /// Call this after the AESP client has successfully connected to the server.
    /// Already-connected controllers (e.g. wired USB) are detected immediately
    /// via `GCController.controllers()`.
    ///
    /// - Parameter client: The connected AESP client for sending input messages.
    func start(client: AESPClient) {
        self.client = client

        // Register for controller connect/disconnect notifications.
        // These fire on the main thread, matching our @MainActor isolation.
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the controller on the main queue before crossing isolation.
            // nonisolated(unsafe) silences the Sendable warning — safe because
            // we read .object on the main queue and pass it to @MainActor code
            // that also runs on the main queue (queue: .main above).
            nonisolated(unsafe) let controller = notification.object as? GCController
            MainActor.assumeIsolated {
                guard let self, let controller else { return }
                self.controllerDidConnect(controller)
            }
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            nonisolated(unsafe) let controller = notification.object as? GCController
            MainActor.assumeIsolated {
                guard let self, let controller else { return }
                self.controllerDidDisconnect(controller)
            }
        }

        // Start wireless controller discovery (Bluetooth).
        // This enables the system to find new wireless controllers.
        GCController.startWirelessControllerDiscovery(completionHandler: nil)

        // Check for controllers that were already connected before we started
        // listening (e.g. wired USB controllers plugged in at launch).
        for controller in GCController.controllers() {
            controllerDidConnect(controller)
        }

        print("[AtticGUI] Game controller discovery started")
    }

    /// Stops controller discovery, removes observers, and resets all state.
    ///
    /// Call this during cleanup before disconnecting the AESP client.
    /// Sends neutral joystick state for all ports to prevent stuck directions.
    func stop() {
        GCController.stopWirelessControllerDiscovery()

        // Remove notification observers
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
            connectObserver = nil
        }
        if let observer = disconnectObserver {
            NotificationCenter.default.removeObserver(observer)
            disconnectObserver = nil
        }

        // Clear all slots and send neutral state
        for i in slots.indices {
            if let controller = slots[i].controller {
                controller.extendedGamepad?.valueChangedHandler = nil
                controller.microGamepad?.valueChangedHandler = nil
            }
            slots[i].controller = nil
        }

        resetAllPorts()
        hasConnectedController = false
        client = nil

        print("[AtticGUI] Game controller discovery stopped")
    }

    /// Sends neutral (centered, no trigger) state for both joystick ports.
    ///
    /// Call this after an emulator reset to clear any stuck directions.
    func resetAllPorts() {
        // Reset published state
        port0Up = false; port0Down = false; port0Left = false; port0Right = false; port0Trigger = false
        port1Up = false; port1Down = false; port1Left = false; port1Right = false; port1Trigger = false

        // Send neutral to server
        Task {
            await client?.sendJoystick(port: 0, up: false, down: false, left: false, right: false, trigger: false)
            await client?.sendJoystick(port: 1, up: false, down: false, left: false, right: false, trigger: false)
        }

        // Reset console key tracking
        let neutral = ConsoleKeyState()
        if lastConsoleKeyState != neutral {
            lastConsoleKeyState = neutral
            Task {
                await client?.sendConsoleKeys(start: false, select: false, option: false)
            }
        }
    }

    // =========================================================================
    // MARK: - Connection Handling
    // =========================================================================

    /// Assigns a newly connected controller to the first available slot.
    ///
    /// If both slots are full (two controllers already connected), the new
    /// controller is ignored. The Atari 800 XL only has two joystick ports.
    private func controllerDidConnect(_ controller: GCController) {
        // Find first empty slot
        guard let slotIndex = slots.firstIndex(where: { $0.controller == nil }) else {
            print("[AtticGUI] Game controller connected but both ports are full, ignoring")
            return
        }

        slots[slotIndex].controller = controller
        let port = slots[slotIndex].port

        // Set the player index LED on controllers that support it
        // (e.g. Xbox/PS controllers light up the corresponding player LED)
        controller.playerIndex = slotIndex == 0 ? .index1 : .index2

        // Set up input handlers based on the controller's profile.
        // GCExtendedGamepad is the full-featured profile (D-pad, sticks, buttons).
        // GCMicroGamepad is for simpler controllers like the Siri Remote.
        if let gamepad = controller.extendedGamepad {
            setupExtendedGamepad(gamepad, port: port)
        } else if let microGamepad = controller.microGamepad {
            setupMicroGamepad(microGamepad, port: port)
        }

        hasConnectedController = true
        print("[AtticGUI] Game controller '\(controller.vendorName ?? "Unknown")' connected on port \(port)")
    }

    /// Removes a disconnected controller from its slot and resets that port.
    ///
    /// Sends neutral joystick state to prevent stuck directions, and updates
    /// the published state so the HUD overlay reflects the disconnection.
    private func controllerDidDisconnect(_ controller: GCController) {
        guard let slotIndex = slots.firstIndex(where: { $0.controller === controller }) else {
            return
        }

        let port = slots[slotIndex].port
        slots[slotIndex].controller = nil

        // Clear the value-changed handlers to avoid dangling references
        controller.extendedGamepad?.valueChangedHandler = nil
        controller.microGamepad?.valueChangedHandler = nil

        // Reset this port's state
        resetPort(port)

        // Update connection status
        hasConnectedController = slots.contains(where: { $0.controller != nil })

        print("[AtticGUI] Game controller disconnected from port \(port)")
    }

    // =========================================================================
    // MARK: - Input Mapping
    // =========================================================================

    /// Sets up input handlers for a controller with the extended gamepad profile.
    ///
    /// The extended profile includes: D-pad, two thumbsticks, ABXY buttons,
    /// shoulder buttons, triggers, and menu/options buttons.
    ///
    /// Mapping:
    /// - D-pad + left thumbstick → joystick directions (OR'd together)
    /// - A/B buttons + right trigger → fire button (OR'd together)
    /// - Menu button → Atari START
    /// - Options button → Atari SELECT
    /// - Left shoulder → Atari OPTION
    private func setupExtendedGamepad(_ gamepad: GCExtendedGamepad, port: UInt8) {
        // The valueChangedHandler fires whenever any element of the gamepad changes.
        // We read the entire gamepad state each time, which naturally coalesces
        // simultaneous input changes (e.g. diagonal + fire) into a single update.
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            // Dispatch back to MainActor since the handler may fire on any thread.
            Task { @MainActor in
                self?.handleExtendedGamepadInput(gamepad, port: port)
            }
        }
    }

    /// Sets up input handlers for a controller with the micro gamepad profile.
    ///
    /// The micro profile (e.g. Siri Remote) has a limited D-pad and one button.
    /// Only basic direction and trigger mapping is possible.
    private func setupMicroGamepad(_ microGamepad: GCMicroGamepad, port: UInt8) {
        microGamepad.valueChangedHandler = { [weak self] gamepad, _ in
            Task { @MainActor in
                self?.handleMicroGamepadInput(gamepad, port: port)
            }
        }
    }

    /// Processes input from an extended gamepad and sends it to the server.
    ///
    /// Combines D-pad and left thumbstick (with deadzone) for directions,
    /// and multiple buttons for the trigger. Also handles console key mapping.
    private func handleExtendedGamepadInput(_ gamepad: GCExtendedGamepad, port: UInt8) {
        // Directions: OR of D-pad digital buttons and left thumbstick analog
        let up = gamepad.dpad.up.isPressed
            || gamepad.leftThumbstick.yAxis.value > deadzone
        let down = gamepad.dpad.down.isPressed
            || gamepad.leftThumbstick.yAxis.value < -deadzone
        let left = gamepad.dpad.left.isPressed
            || gamepad.leftThumbstick.xAxis.value < -deadzone
        let right = gamepad.dpad.right.isPressed
            || gamepad.leftThumbstick.xAxis.value > deadzone

        // Fire: multiple buttons for player comfort (Atari only has one button)
        let trigger = gamepad.buttonA.isPressed
            || gamepad.buttonB.isPressed
            || gamepad.rightTrigger.isPressed

        // Update published state for HUD overlay
        updatePublishedState(port: port, up: up, down: down, left: left, right: right, trigger: trigger)

        // Send to server
        Task {
            await client?.sendJoystick(port: port, up: up, down: down, left: left, right: right, trigger: trigger)
        }

        // Console keys (shared across all controllers, not port-specific).
        // The Atari's console keys are system-wide, so any controller can press them.
        let start = gamepad.buttonMenu.isPressed
        let select = gamepad.buttonOptions?.isPressed ?? false
        let option = gamepad.leftShoulder.isPressed

        let newConsoleState = ConsoleKeyState(start: start, select: select, option: option)
        if newConsoleState != lastConsoleKeyState {
            lastConsoleKeyState = newConsoleState
            Task {
                await client?.sendConsoleKeys(start: start, select: select, option: option)
            }
        }
    }

    /// Processes input from a micro gamepad (e.g. Siri Remote).
    ///
    /// Limited to D-pad directions and one button (buttonA = trigger).
    private func handleMicroGamepadInput(_ gamepad: GCMicroGamepad, port: UInt8) {
        let up = gamepad.dpad.up.isPressed
        let down = gamepad.dpad.down.isPressed
        let left = gamepad.dpad.left.isPressed
        let right = gamepad.dpad.right.isPressed
        let trigger = gamepad.buttonA.isPressed

        updatePublishedState(port: port, up: up, down: down, left: left, right: right, trigger: trigger)

        Task {
            await client?.sendJoystick(port: port, up: up, down: down, left: left, right: right, trigger: trigger)
        }
    }

    // =========================================================================
    // MARK: - State Management
    // =========================================================================

    /// Updates the published joystick state properties for the given port.
    ///
    /// These properties drive the JoystickOverlayView HUD. Separating this
    /// from the send logic keeps the code testable and avoids duplication
    /// between extended and micro gamepad handlers.
    private func updatePublishedState(
        port: UInt8, up: Bool, down: Bool, left: Bool, right: Bool, trigger: Bool
    ) {
        if port == 0 {
            port0Up = up; port0Down = down; port0Left = left; port0Right = right; port0Trigger = trigger
        } else {
            port1Up = up; port1Down = down; port1Left = left; port1Right = right; port1Trigger = trigger
        }
    }

    /// Resets a single port's published state and sends neutral to the server.
    private func resetPort(_ port: UInt8) {
        updatePublishedState(port: port, up: false, down: false, left: false, right: false, trigger: false)
        Task {
            await client?.sendJoystick(port: port, up: false, down: false, left: false, right: false, trigger: false)
        }
    }
}
