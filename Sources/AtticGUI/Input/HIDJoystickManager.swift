// HIDJoystickManager.swift
// AtticGUI
//
// Low-level IOKit HID joystick support for USB devices not recognized by
// Apple's GameController framework. This catches retro joysticks, arcade
// sticks, and other generic USB HID devices that present as joysticks or
// gamepads but lack MFi certification.
//
// Architecture:
// - Uses IOHIDManager to match USB HID devices with usage page 0x01
//   (Generic Desktop) and usage 0x04 (Joystick) or 0x05 (Game Pad).
// - Enumerates each device's HID elements (axes, buttons, hat switches)
//   and registers value-changed callbacks.
// - Converts raw HID axis values to digital Atari joystick directions
//   using a deadzone threshold.
// - Publishes joystick state for the HUD overlay, same pattern as
//   GameControllerHandler.
// - Scheduled on CFRunLoopGetMain() so callbacks fire on the main thread,
//   compatible with @MainActor isolation.
// - Does NOT seize devices (kIOHIDOptionsTypeNone), so GameController
//   framework can still claim devices it recognizes. If a device is
//   handled by both, last-input-wins applies (same as keyboard coexistence).

import Combine
import Foundation
import IOKit
import IOKit.hid
import AtticProtocol

// MARK: - HID Constants

/// Standard HID usage page and usage IDs for device matching.
/// See USB HID Usage Tables specification (hut1_4.pdf).
private enum HIDUsagePage {
    static let genericDesktop: Int = 0x01
    static let button: Int = 0x09
}

/// Generic Desktop usage IDs for device types and axis elements.
private enum HIDGenericDesktopUsage {
    // Device types (for matching)
    static let joystick: Int = 0x04
    static let gamepad: Int = 0x05

    // Axis elements
    static let x: Int = 0x30
    static let y: Int = 0x31
    static let z: Int = 0x32
    static let hatSwitch: Int = 0x39
}

// MARK: - HID Device State

/// Tracks the current input state for one connected HID device.
///
/// Updated by IOHIDManager callbacks as raw HID values arrive.
/// The axis values are normalized to -1.0...1.0 range with deadzone applied.
private struct HIDDeviceState {
    let vendorName: String
    let productName: String

    /// Horizontal axis (X), normalized with deadzone. Negative = left, positive = right.
    var axisX: Double = 0

    /// Vertical axis (Y), normalized with deadzone. Negative = up, positive = down.
    /// Note: HID Y axis convention is typically inverted (positive = down).
    var axisY: Double = 0

    /// Button states keyed by HID button usage ID (1-based).
    var buttons: [Int: Bool] = [:]

    /// Hat switch directions (from hat switch element, if present).
    var hatUp: Bool = false
    var hatDown: Bool = false
    var hatLeft: Bool = false
    var hatRight: Bool = false
}

// MARK: - HIDJoystickManager

/// Manages raw USB HID joystick/gamepad devices via IOKit.
///
/// This complements GameControllerHandler by catching devices that Apple's
/// GameController framework doesn't recognize (e.g. retro joysticks like
/// the CXStick from Retro Games LTD).
///
/// Usage:
/// 1. Create as a property of AtticViewModel alongside GameControllerHandler.
/// 2. Call `start(client:)` after AESP client connects.
/// 3. Call `stop()` during cleanup.
/// 4. Read published properties for HUD overlay display.
@MainActor
final class HIDJoystickManager: ObservableObject {

    // =========================================================================
    // MARK: - Published State (for HUD overlay)
    // =========================================================================

    /// Port 0 direction and trigger state from HID devices.
    @Published var port0Up: Bool = false
    @Published var port0Down: Bool = false
    @Published var port0Left: Bool = false
    @Published var port0Right: Bool = false
    @Published var port0Trigger: Bool = false

    /// Whether any HID joystick is currently connected.
    @Published var hasConnectedDevice: Bool = false

    // =========================================================================
    // MARK: - Private State
    // =========================================================================

    /// The IOHIDManager instance. Created in start(), destroyed in stop().
    private var hidManager: IOHIDManager?

    /// Connected HID devices keyed by their IOHIDDevice (as pointer value).
    /// We use the pointer value as key since IOHIDDevice isn't Hashable.
    private var devices: [Int: HIDDeviceState] = [:]

    /// Maps IOHIDDevice pointer values to their actual refs for cleanup.
    private var deviceRefs: [Int: IOHIDDevice] = [:]

    /// Reference to the AESP client for sending joystick messages.
    private weak var client: AESPClient?

    /// Analog stick deadzone threshold (0.0–1.0).
    /// Raw HID values within this range of center are treated as neutral.
    private let deadzone: Double = 0.25

    /// Opaque pointer to self for C callback context.
    /// Stored to ensure consistent pointer value across callbacks.
    private var unmanagedSelf: Unmanaged<HIDJoystickManager>?

    // =========================================================================
    // MARK: - Lifecycle
    // =========================================================================

    /// Starts HID device discovery and monitoring.
    ///
    /// Creates an IOHIDManager, sets up matching criteria for joystick and
    /// gamepad devices, registers connect/disconnect callbacks, and schedules
    /// on the main run loop.
    ///
    /// - Parameter client: The connected AESP client for sending input.
    func start(client: AESPClient) {
        self.client = client

        // Create the HID manager.
        // kIOHIDOptionsTypeNone means we don't seize devices — this allows
        // GameController framework to also claim devices it recognizes.
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("[HIDJoystick] Failed to create IOHIDManager")
            return
        }

        // Match USB HID devices that report as joystick or gamepad.
        // This catches devices GameController doesn't recognize.
        let joystickMatch: NSDictionary = [
            kIOHIDDeviceUsagePageKey: HIDUsagePage.genericDesktop,
            kIOHIDDeviceUsageKey: HIDGenericDesktopUsage.joystick
        ]
        let gamepadMatch: NSDictionary = [
            kIOHIDDeviceUsagePageKey: HIDUsagePage.genericDesktop,
            kIOHIDDeviceUsageKey: HIDGenericDesktopUsage.gamepad
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, [joystickMatch, gamepadMatch] as CFArray)

        // Store an unmanaged reference to self for use as C callback context.
        // passUnretained avoids a retain cycle — the manager's lifetime is
        // controlled by start()/stop(), not by the callbacks.
        unmanagedSelf = Unmanaged.passUnretained(self)
        let context = unmanagedSelf!.toOpaque()

        // Register device matched callback (fires when a matching device connects).
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchedCallback, context)

        // Register device removal callback (fires when a device disconnects).
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovedCallback, context)

        // Schedule on the main run loop. Callbacks will fire on the main thread,
        // which is compatible with @MainActor isolation.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Open the manager to begin receiving events.
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if status != kIOReturnSuccess {
            print("[HIDJoystick] Failed to open IOHIDManager: \(status)")
            return
        }

        print("[HIDJoystick] IOKit HID joystick discovery started")
    }

    /// Stops HID monitoring and releases all resources.
    ///
    /// Sends neutral joystick state before teardown to prevent stuck directions.
    func stop() {
        guard let manager = hidManager else { return }

        // Send neutral state before shutting down
        resetState()

        // Close all tracked devices
        for (_, deviceRef) in deviceRefs {
            IOHIDDeviceClose(deviceRef, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        devices.removeAll()
        deviceRefs.removeAll()

        // Unschedule and close the manager
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
        unmanagedSelf = nil
        client = nil
        hasConnectedDevice = false

        print("[HIDJoystick] IOKit HID joystick discovery stopped")
    }

    /// Resets all published state and sends neutral joystick to the server.
    func resetState() {
        port0Up = false; port0Down = false; port0Left = false; port0Right = false; port0Trigger = false
        Task {
            await client?.sendJoystick(port: 0, up: false, down: false, left: false, right: false, trigger: false)
        }
    }

    // =========================================================================
    // MARK: - Device Connection Handling
    // =========================================================================

    /// Called when a matching HID device connects.
    ///
    /// Opens the device, reads its metadata, enumerates input elements
    /// (axes, buttons, hat switches), and registers a value callback.
    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        let key = deviceKey(device)

        // Skip if already tracking this device
        guard devices[key] == nil else { return }

        // Open the device for reading (non-seizing)
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            print("[HIDJoystick] Failed to open device: \(status)")
            return
        }

        // Read device metadata
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "Unknown"
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        // Log the device's elements for debugging
        logDeviceElements(device)

        // Store device state
        devices[key] = HIDDeviceState(vendorName: vendor, productName: product)
        deviceRefs[key] = device
        hasConnectedDevice = true

        // Register a single input value callback for all elements on this device.
        // This fires whenever any axis, button, or hat switch value changes.
        let context = unmanagedSelf!.toOpaque()
        IOHIDDeviceRegisterInputValueCallback(device, hidInputValueCallback, context)

        print("[HIDJoystick] Device connected: \(vendor) \(product)")
    }

    /// Called when a tracked HID device disconnects.
    ///
    /// Clears device state and sends neutral joystick to prevent stuck input.
    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        let key = deviceKey(device)
        guard let state = devices[key] else { return }

        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        devices.removeValue(forKey: key)
        deviceRefs.removeValue(forKey: key)

        hasConnectedDevice = !devices.isEmpty
        resetState()

        print("[HIDJoystick] Device disconnected: \(state.vendorName) \(state.productName)")
    }

    // =========================================================================
    // MARK: - Input Value Handling
    // =========================================================================

    /// Processes a raw HID input value change.
    ///
    /// Called from the IOHIDManager run loop callback. Routes the value
    /// to the appropriate handler based on HID usage page and usage ID.
    fileprivate func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let key = deviceKey(device)

        guard var state = devices[key] else { return }

        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intValue = IOHIDValueGetIntegerValue(value)
        let logicalMin = IOHIDElementGetLogicalMin(element)
        let logicalMax = IOHIDElementGetLogicalMax(element)

        switch usagePage {
        case HIDUsagePage.genericDesktop:
            switch usage {
            case HIDGenericDesktopUsage.x:
                // Horizontal axis: left = negative, right = positive
                state.axisX = normalizeAxis(intValue, min: logicalMin, max: logicalMax)

            case HIDGenericDesktopUsage.y:
                // Vertical axis: up = negative, down = positive (HID convention)
                state.axisY = normalizeAxis(intValue, min: logicalMin, max: logicalMax)

            case HIDGenericDesktopUsage.hatSwitch:
                // Hat switch (D-pad): 8 directions + center
                decodeHatSwitch(intValue, min: logicalMin, max: logicalMax, state: &state)

            default:
                break
            }

        case HIDUsagePage.button:
            // Button usage IDs are 1-based (Button 1, Button 2, etc.)
            state.buttons[usage] = intValue != 0

        default:
            break
        }

        devices[key] = state

        // Convert device state to Atari joystick directions + trigger
        // Axes and hat switch are OR'd for directions (either input source works).
        let up = state.axisY < -deadzone || state.hatUp
        let down = state.axisY > deadzone || state.hatDown
        let left = state.axisX < -deadzone || state.hatLeft
        let right = state.axisX > deadzone || state.hatRight
        let trigger = state.buttons.values.contains(true)

        // Update published state for HUD
        port0Up = up; port0Down = down; port0Left = left; port0Right = right; port0Trigger = trigger

        // Send to server
        Task {
            await client?.sendJoystick(port: 0, up: up, down: down, left: left, right: right, trigger: trigger)
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    /// Normalizes a raw HID axis integer value to -1.0...1.0 range.
    ///
    /// HID axes report integer values between logicalMin and logicalMax.
    /// For a typical 8-bit axis: min=0, max=255, center=128.
    /// This maps the full range to -1.0...1.0 with center at 0.0.
    private func normalizeAxis(_ value: CFIndex, min: CFIndex, max: CFIndex) -> Double {
        let range = Double(max - min)
        guard range > 0 else { return 0 }
        return (Double(value - min) / range) * 2.0 - 1.0
    }

    /// Decodes a hat switch (D-pad) value into four directional booleans.
    ///
    /// Standard HID hat switch values (when min=0, max=7):
    /// 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8+=centered
    /// Some devices use min=1, max=8 with 0=centered.
    private func decodeHatSwitch(_ value: CFIndex, min: CFIndex, max: CFIndex, state: inout HIDDeviceState) {
        // Normalize: if value is outside min...max, it's centered (neutral)
        guard value >= min && value <= max else {
            state.hatUp = false; state.hatDown = false; state.hatLeft = false; state.hatRight = false
            return
        }

        // Map to 0-based position (0=N, 1=NE, ... 7=NW)
        let position = Int(value - min)
        state.hatUp    = position == 0 || position == 1 || position == 7
        state.hatRight = position == 1 || position == 2 || position == 3
        state.hatDown  = position == 3 || position == 4 || position == 5
        state.hatLeft  = position == 5 || position == 6 || position == 7
    }

    /// Returns a stable key for an IOHIDDevice, using its pointer value.
    ///
    /// IOHIDDevice is a CFTypeRef (opaque pointer), not Hashable in Swift.
    /// The pointer value is stable for the lifetime of the device connection.
    private func deviceKey(_ device: IOHIDDevice) -> Int {
        return Int(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    /// Logs all input elements of a device for debugging.
    ///
    /// This helps diagnose mapping issues with unfamiliar controllers
    /// by showing what axes, buttons, and hat switches the device reports.
    private func logDeviceElements(_ device: IOHIDDevice) {
        guard let cfElements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone))
                as? [IOHIDElement] else {
            print("[HIDJoystick] No elements found on device")
            return
        }

        for element in cfElements {
            let type = IOHIDElementGetType(element)
            guard type == kIOHIDElementTypeInput_Axis
               || type == kIOHIDElementTypeInput_Button
               || type == kIOHIDElementTypeInput_Misc else { continue }

            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let min = IOHIDElementGetLogicalMin(element)
            let max = IOHIDElementGetLogicalMax(element)

            let typeName: String
            switch type {
            case kIOHIDElementTypeInput_Axis: typeName = "Axis"
            case kIOHIDElementTypeInput_Button: typeName = "Button"
            case kIOHIDElementTypeInput_Misc: typeName = "Misc"
            default: typeName = "Other"
            }

            print("[HIDJoystick]   Element: \(typeName) page=0x\(String(page, radix: 16)) usage=0x\(String(usage, radix: 16)) range=[\(min), \(max)]")
        }
    }
}

// MARK: - C Callback Functions

/// IOHIDManager callback when a matching device is connected.
///
/// These are free functions because IOHIDManager uses C function pointers.
/// The context parameter carries an unmanaged reference to HIDJoystickManager.
private func hidDeviceMatchedCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    let manager = Unmanaged<HIDJoystickManager>.fromOpaque(context).takeUnretainedValue()
    // nonisolated(unsafe) silences the Sendable warning for IOHIDDevice —
    // safe because IOHIDManager callbacks fire on CFRunLoopGetMain() and we
    // immediately enter MainActor.assumeIsolated on the same thread.
    nonisolated(unsafe) let dev = device
    MainActor.assumeIsolated {
        manager.deviceMatched(dev)
    }
}

/// IOHIDManager callback when a tracked device is disconnected.
private func hidDeviceRemovedCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ device: IOHIDDevice
) {
    guard let context else { return }
    let manager = Unmanaged<HIDJoystickManager>.fromOpaque(context).takeUnretainedValue()
    nonisolated(unsafe) let dev = device
    MainActor.assumeIsolated {
        manager.deviceRemoved(dev)
    }
}

/// IOHIDDevice callback when any input element value changes.
///
/// Fires for every axis movement, button press/release, and hat switch change.
private func hidInputValueCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    guard let context else { return }
    let manager = Unmanaged<HIDJoystickManager>.fromOpaque(context).takeUnretainedValue()
    nonisolated(unsafe) let val = value
    MainActor.assumeIsolated {
        manager.handleInputValue(val)
    }
}
