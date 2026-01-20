// =============================================================================
// KeyboardInputHandler.swift - Keyboard Input Mapping for Atari Emulator
// =============================================================================
//
// This file provides the keyboard input handling for the Attic emulator.
// It maps macOS keyboard events to Atari 800 XL key codes.
//
// Atari 800 XL Keyboard Layout:
// -----------------------------
// The Atari 800 XL has a different keyboard layout than modern computers:
// - ESC is in the top-left
// - START, SELECT, OPTION are console keys (not on keyboard)
// - BREAK key generates special interrupt
// - ATARI key (inverse video) is where backtick is on Mac keyboards
// - CAPS key toggles capitals (not Caps Lock behavior)
//
// Key Code System:
// ----------------
// libatari800 uses two values for keyboard input:
// - keychar: The ATASCII character code (like ASCII but with Atari extensions)
// - keycode: The internal key matrix code (AKEY_* constants)
//
// For regular typing, we use keychar (the character).
// For special keys (arrows, function keys), we use keycode.
//
// Host Key Mapping:
// -----------------
// | Mac Key       | Atari Key    | Notes                              |
// |---------------|--------------|----------------------------------- |
// | A-Z, a-z      | A-Z          | Letters (ATASCII)                  |
// | 0-9           | 0-9          | Numbers (ATASCII)                  |
// | Return        | RETURN       | Enter key                          |
// | Backspace     | DELETE       | Delete character                   |
// | Tab           | TAB          | Tab key                            |
// | Escape        | ESC          | Escape key                         |
// | F1            | START        | Console START key                  |
// | F2            | SELECT       | Console SELECT key                 |
// | F3            | OPTION       | Console OPTION key                 |
// | Backtick (`)  | ATARI        | Inverse video toggle               |
// | Arrow keys    | Arrow keys   | Cursor movement                    |
// | Shift         | SHIFT        | Modifier                           |
// | Control       | CONTROL      | Modifier                           |
//
// =============================================================================

import Foundation

// Import CAtari800 for AKEY_* constants
// These are defined in libatari800.h
@preconcurrency import CAtari800

// =============================================================================
// MARK: - Atari Key Constants
// =============================================================================

/// Atari key code constants from libatari800.
///
/// These are the internal key codes used by the Atari 800 XL keyboard matrix.
/// They're different from ATASCII character codes.
public enum AtariKeyCode {
    // Special keys
    public static let none: UInt8 = 0xFF
    public static let help: UInt8 = UInt8(AKEY_HELP)
    public static let down: UInt8 = UInt8(AKEY_DOWN)
    public static let left: UInt8 = UInt8(AKEY_LEFT)
    public static let right: UInt8 = UInt8(AKEY_RIGHT)
    public static let up: UInt8 = UInt8(AKEY_UP)
    public static let backspace: UInt8 = UInt8(AKEY_BACKSPACE)
    public static let deleteChar: UInt8 = UInt8(AKEY_DELETE_CHAR)
    public static let deleteLine: UInt8 = UInt8(AKEY_DELETE_LINE)
    public static let insertChar: UInt8 = UInt8(AKEY_INSERT_CHAR)
    public static let insertLine: UInt8 = UInt8(AKEY_INSERT_LINE)
    public static let escape: UInt8 = UInt8(AKEY_ESCAPE)
    public static let atari: UInt8 = UInt8(AKEY_ATARI)
    public static let capsLock: UInt8 = UInt8(AKEY_CAPSLOCK)
    public static let capsToggle: UInt8 = UInt8(AKEY_CAPSTOGGLE)
    public static let tab: UInt8 = UInt8(AKEY_TAB)
    public static let `return`: UInt8 = UInt8(AKEY_RETURN)
    public static let space: UInt8 = UInt8(AKEY_SPACE)

    // Function keys (used for HELP on XL)
    public static let f1: UInt8 = UInt8(AKEY_F1)
    public static let f2: UInt8 = UInt8(AKEY_F2)
    public static let f3: UInt8 = UInt8(AKEY_F3)
    public static let f4: UInt8 = UInt8(AKEY_F4)

    // Punctuation
    public static let comma: UInt8 = UInt8(AKEY_COMMA)
    public static let period: UInt8 = UInt8(AKEY_FULLSTOP)
    public static let semicolon: UInt8 = UInt8(AKEY_SEMICOLON)
    public static let colon: UInt8 = UInt8(AKEY_COLON)
    public static let slash: UInt8 = UInt8(AKEY_SLASH)
    public static let minus: UInt8 = UInt8(AKEY_MINUS)
    public static let equal: UInt8 = UInt8(AKEY_EQUAL)
    public static let plus: UInt8 = UInt8(AKEY_PLUS)
    public static let asterisk: UInt8 = UInt8(AKEY_ASTERISK)
    public static let less: UInt8 = UInt8(AKEY_LESS)
    public static let greater: UInt8 = UInt8(AKEY_GREATER)
}

// =============================================================================
// MARK: - KeyboardInputHandler
// =============================================================================

/// Handles keyboard input mapping from host (Mac) to Atari.
///
/// This class maintains the current keyboard state and converts Mac key events
/// to Atari key codes. It tracks modifier keys and console keys (START, SELECT, OPTION).
///
/// Usage:
///
///     let handler = KeyboardInputHandler()
///
///     // On key down:
///     if let (keyChar, keyCode, shift, control) = handler.keyDown(keyCode: 0, characters: "a") {
///         await emulator.pressKey(keyChar: keyChar, keyCode: keyCode, shift: shift, control: control)
///     }
///
///     // On key up:
///     handler.keyUp(keyCode: 0)
///     await emulator.releaseKey()
///
/// Thread Safety:
/// This class is designed to be used from the main thread (UI thread).
/// All its methods should be called from the main thread.
///
@MainActor
public final class KeyboardInputHandler: ObservableObject {
    // =========================================================================
    // MARK: - Published State
    // =========================================================================

    /// Whether the Shift key is currently pressed.
    @Published public private(set) var shiftPressed: Bool = false

    /// Whether the Control key is currently pressed.
    @Published public private(set) var controlPressed: Bool = false

    /// Whether the Option/Alt key is currently pressed (maps to Atari OPTION in some modes).
    @Published public private(set) var optionPressed: Bool = false

    /// Whether the Command key is currently pressed.
    @Published public private(set) var commandPressed: Bool = false

    /// Whether START console key is active (F1).
    @Published public private(set) var startPressed: Bool = false

    /// Whether SELECT console key is active (F2).
    @Published public private(set) var selectPressed: Bool = false

    /// Whether OPTION console key is active (F3).
    @Published public private(set) var optionKeyPressed: Bool = false

    // =========================================================================
    // MARK: - Private State
    // =========================================================================

    /// Set of currently pressed key codes (Mac virtual key codes).
    private var pressedKeys: Set<UInt16> = []

    /// The current Atari key character being sent.
    private var currentKeyChar: UInt8 = 0

    /// The current Atari key code being sent.
    private var currentKeyCode: UInt8 = 0xFF

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    public init() {}

    // =========================================================================
    // MARK: - Modifier Handling
    // =========================================================================

    /// Updates modifier key states based on event flags.
    ///
    /// Call this on every key event to keep modifier state in sync.
    ///
    /// - Parameter modifierFlags: The NSEvent.ModifierFlags from the key event.
    public func updateModifiers(shift: Bool, control: Bool, option: Bool, command: Bool) {
        shiftPressed = shift
        controlPressed = control
        optionPressed = option
        commandPressed = command
    }

    // =========================================================================
    // MARK: - Key Down Handling
    // =========================================================================

    /// Processes a key down event.
    ///
    /// Converts the Mac key event to Atari key codes. Returns nil if the key
    /// should be ignored (e.g., Command key combinations for menu shortcuts).
    ///
    /// - Parameters:
    ///   - keyCode: The Mac virtual key code.
    ///   - characters: The characters produced by the key (for regular keys).
    ///   - shift: Whether Shift is pressed.
    ///   - control: Whether Control is pressed.
    /// - Returns: Tuple of (keyChar, keyCode, shift, control) for Atari, or nil to ignore.
    public func keyDown(
        keyCode: UInt16,
        characters: String?,
        shift: Bool,
        control: Bool
    ) -> (keyChar: UInt8, keyCode: UInt8, shift: Bool, control: Bool)? {
        // Track pressed key
        pressedKeys.insert(keyCode)

        // Handle special keys first (by Mac virtual key code)
        if let result = handleSpecialKey(keyCode: keyCode, shift: shift, control: control) {
            currentKeyChar = result.keyChar
            currentKeyCode = result.keyCode

            // Log special key down event
            let keyName = macKeyCodeName(keyCode)
            print("[KeyDown] Mac: 0x\(String(format: "%02X", keyCode)) (\(keyName)) | " +
                  "Atari: keyChar=0x\(String(format: "%02X", result.keyChar)), " +
                  "keyCode=0x\(String(format: "%02X", result.keyCode)) | " +
                  "shift=\(result.shift), control=\(result.control)")

            return result
        }

        // Handle regular character keys
        if let chars = characters, let firstChar = chars.first {
            let result = handleCharacterKey(character: firstChar, shift: shift, control: control)
            currentKeyChar = result.keyChar
            currentKeyCode = result.keyCode

            // Log character key down event
            let keyName = macKeyCodeName(keyCode)
            print("[KeyDown] Mac: 0x\(String(format: "%02X", keyCode)) (\(keyName)) char='\(firstChar)' | " +
                  "Atari: keyChar=0x\(String(format: "%02X", result.keyChar)) ('\(Character(UnicodeScalar(result.keyChar)))'), " +
                  "keyCode=0x\(String(format: "%02X", result.keyCode)) | " +
                  "shift=\(result.shift), control=\(result.control)")

            return result
        }

        // Log ignored key
        let keyName = macKeyCodeName(keyCode)
        print("[KeyDown] Mac: 0x\(String(format: "%02X", keyCode)) (\(keyName)) | IGNORED (no mapping)")

        return nil
    }

    /// Processes a key up event.
    ///
    /// - Parameter keyCode: The Mac virtual key code that was released.
    /// - Returns: true if this was a tracked key that should trigger releaseKey().
    public func keyUp(keyCode: UInt16) -> Bool {
        let wasPressed = pressedKeys.contains(keyCode)
        pressedKeys.remove(keyCode)

        // Log key up event
        let keyName = macKeyCodeName(keyCode)
        print("[KeyUp]   Mac: 0x\(String(format: "%02X", keyCode)) (\(keyName)) | " +
              "wasPressed=\(wasPressed), remainingKeys=\(pressedKeys.count)")

        // Check if console keys are released
        switch keyCode {
        case MacKeyCode.f1:
            startPressed = false
        case MacKeyCode.f2:
            selectPressed = false
        case MacKeyCode.f3:
            optionKeyPressed = false
        default:
            break
        }

        // Clear current key if this was the active key
        if wasPressed && pressedKeys.isEmpty {
            currentKeyChar = 0
            currentKeyCode = 0xFF
        }

        return wasPressed
    }

    /// Returns the current console key states.
    ///
    /// - Returns: Tuple of (start, select, option) states.
    public func getConsoleKeys() -> (start: Bool, select: Bool, option: Bool) {
        (startPressed, selectPressed, optionKeyPressed)
    }

    // =========================================================================
    // MARK: - Special Key Handling
    // =========================================================================

    /// Handles special keys (function keys, arrows, etc.).
    private func handleSpecialKey(
        keyCode: UInt16,
        shift: Bool,
        control: Bool
    ) -> (keyChar: UInt8, keyCode: UInt8, shift: Bool, control: Bool)? {
        switch keyCode {
        // Console keys - these set flags instead of sending keys
        case MacKeyCode.f1:
            startPressed = true
            return nil  // Don't send as regular key

        case MacKeyCode.f2:
            selectPressed = true
            return nil

        case MacKeyCode.f3:
            optionKeyPressed = true
            return nil

        // Escape
        // Note: keyChar must be 0 for special keys so libatari800 uses keyCode
        case MacKeyCode.escape:
            return (0, AtariKeyCode.escape, shift, control)

        // Return/Enter
        // Note: keyChar must be 0 for special keys so libatari800 uses keyCode
        case MacKeyCode.return, MacKeyCode.keypadEnter:
            return (0, AtariKeyCode.return, shift, control)

        // Tab
        // Note: keyChar must be 0 for special keys so libatari800 uses keyCode
        case MacKeyCode.tab:
            return (0, AtariKeyCode.tab, shift, control)

        // Backspace/Delete
        // Note: keyChar must be 0 for special keys so libatari800 uses keyCode
        case MacKeyCode.delete:
            return (0, AtariKeyCode.backspace, shift, control)

        // Arrow keys
        case MacKeyCode.upArrow:
            return (0, AtariKeyCode.up, shift, control)

        case MacKeyCode.downArrow:
            return (0, AtariKeyCode.down, shift, control)

        case MacKeyCode.leftArrow:
            return (0, AtariKeyCode.left, shift, control)

        case MacKeyCode.rightArrow:
            return (0, AtariKeyCode.right, shift, control)

        // Backtick - maps to ATARI key (inverse video)
        case MacKeyCode.grave:
            return (0, AtariKeyCode.atari, shift, control)

        // Caps Lock - toggle caps
        case MacKeyCode.capsLock:
            return (0, AtariKeyCode.capsToggle, false, false)

        // Space
        case MacKeyCode.space:
            return (0x20, AtariKeyCode.space, shift, control)

        default:
            return nil
        }
    }

    // =========================================================================
    // MARK: - Character Key Handling
    // =========================================================================

    /// Handles regular character keys.
    private func handleCharacterKey(
        character: Character,
        shift: Bool,
        control: Bool
    ) -> (keyChar: UInt8, keyCode: UInt8, shift: Bool, control: Bool) {
        let ascii = character.asciiValue ?? 0

        // For most keys, we pass the ATASCII character code directly
        // libatari800 handles the keychar -> keycode mapping internally

        // Control key combinations produce special ATASCII codes
        if control {
            // Control+A through Control+Z produce codes 1-26
            if ascii >= 0x41 && ascii <= 0x5A {  // A-Z
                let ctrlCode = ascii - 0x40
                return (ctrlCode, 0xFF, false, true)
            }
            if ascii >= 0x61 && ascii <= 0x7A {  // a-z
                let ctrlCode = ascii - 0x60
                return (ctrlCode, 0xFF, false, true)
            }
        }

        // Regular character - convert to uppercase ATASCII if letter
        var atasciiChar = ascii
        if atasciiChar >= 0x61 && atasciiChar <= 0x7A {  // a-z
            // Atari uses uppercase internally, shift inverts
            atasciiChar = atasciiChar - 0x20  // Convert to uppercase
        }

        return (atasciiChar, 0xFF, shift, control)
    }

    // =========================================================================
    // MARK: - Logging Helpers
    // =========================================================================

    /// Returns a human-readable name for a Mac virtual key code.
    ///
    /// Used for debug logging to make key events easier to understand.
    private func macKeyCodeName(_ keyCode: UInt16) -> String {
        switch keyCode {
        // Letters
        case MacKeyCode.a: return "A"
        case MacKeyCode.b: return "B"
        case MacKeyCode.c: return "C"
        case MacKeyCode.d: return "D"
        case MacKeyCode.e: return "E"
        case MacKeyCode.f: return "F"
        case MacKeyCode.g: return "G"
        case MacKeyCode.h: return "H"
        case MacKeyCode.i: return "I"
        case MacKeyCode.j: return "J"
        case MacKeyCode.k: return "K"
        case MacKeyCode.l: return "L"
        case MacKeyCode.m: return "M"
        case MacKeyCode.n: return "N"
        case MacKeyCode.o: return "O"
        case MacKeyCode.p: return "P"
        case MacKeyCode.q: return "Q"
        case MacKeyCode.r: return "R"
        case MacKeyCode.s: return "S"
        case MacKeyCode.t: return "T"
        case MacKeyCode.u: return "U"
        case MacKeyCode.v: return "V"
        case MacKeyCode.w: return "W"
        case MacKeyCode.x: return "X"
        case MacKeyCode.y: return "Y"
        case MacKeyCode.z: return "Z"

        // Numbers
        case MacKeyCode.key0: return "0"
        case MacKeyCode.key1: return "1"
        case MacKeyCode.key2: return "2"
        case MacKeyCode.key3: return "3"
        case MacKeyCode.key4: return "4"
        case MacKeyCode.key5: return "5"
        case MacKeyCode.key6: return "6"
        case MacKeyCode.key7: return "7"
        case MacKeyCode.key8: return "8"
        case MacKeyCode.key9: return "9"

        // Special keys
        case MacKeyCode.return: return "Return"
        case MacKeyCode.tab: return "Tab"
        case MacKeyCode.space: return "Space"
        case MacKeyCode.delete: return "Backspace"
        case MacKeyCode.escape: return "Escape"
        case MacKeyCode.capsLock: return "CapsLock"
        case MacKeyCode.grave: return "Grave"

        // Arrow keys
        case MacKeyCode.leftArrow: return "Left"
        case MacKeyCode.rightArrow: return "Right"
        case MacKeyCode.downArrow: return "Down"
        case MacKeyCode.upArrow: return "Up"

        // Function keys
        case MacKeyCode.f1: return "F1"
        case MacKeyCode.f2: return "F2"
        case MacKeyCode.f3: return "F3"
        case MacKeyCode.f4: return "F4"
        case MacKeyCode.f5: return "F5"
        case MacKeyCode.f6: return "F6"
        case MacKeyCode.f7: return "F7"
        case MacKeyCode.f8: return "F8"
        case MacKeyCode.f9: return "F9"
        case MacKeyCode.f10: return "F10"
        case MacKeyCode.f11: return "F11"
        case MacKeyCode.f12: return "F12"

        // Modifiers
        case MacKeyCode.shift: return "Shift"
        case MacKeyCode.rightShift: return "RightShift"
        case MacKeyCode.control: return "Control"
        case MacKeyCode.rightControl: return "RightControl"
        case MacKeyCode.option: return "Option"
        case MacKeyCode.rightOption: return "RightOption"
        case MacKeyCode.command: return "Command"
        case MacKeyCode.rightCommand: return "RightCommand"

        // Keypad
        case MacKeyCode.keypadEnter: return "KeypadEnter"

        default: return "Unknown"
        }
    }

    // =========================================================================
    // MARK: - Reset
    // =========================================================================

    /// Resets all key states.
    ///
    /// Call this when the window loses focus to prevent stuck keys.
    public func reset() {
        pressedKeys.removeAll()
        shiftPressed = false
        controlPressed = false
        optionPressed = false
        commandPressed = false
        startPressed = false
        selectPressed = false
        optionKeyPressed = false
        currentKeyChar = 0
        currentKeyCode = 0xFF
    }
}

// =============================================================================
// MARK: - Mac Virtual Key Codes
// =============================================================================

/// Mac virtual key codes for special keys.
///
/// These are the raw key codes from NSEvent.keyCode, which represent
/// the physical key position rather than the character produced.
public enum MacKeyCode {
    // Letters (ANSI keyboard layout)
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let x: UInt16 = 0x07
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let b: UInt16 = 0x0B
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let y: UInt16 = 0x10
    public static let t: UInt16 = 0x11
    public static let o: UInt16 = 0x1F
    public static let u: UInt16 = 0x20
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E

    // Numbers
    public static let key1: UInt16 = 0x12
    public static let key2: UInt16 = 0x13
    public static let key3: UInt16 = 0x14
    public static let key4: UInt16 = 0x15
    public static let key5: UInt16 = 0x17
    public static let key6: UInt16 = 0x16
    public static let key7: UInt16 = 0x1A
    public static let key8: UInt16 = 0x1C
    public static let key9: UInt16 = 0x19
    public static let key0: UInt16 = 0x1D

    // Special keys
    public static let `return`: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35
    public static let capsLock: UInt16 = 0x39
    public static let grave: UInt16 = 0x32  // Backtick

    // Arrow keys
    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E

    // Function keys
    public static let f1: UInt16 = 0x7A
    public static let f2: UInt16 = 0x78
    public static let f3: UInt16 = 0x63
    public static let f4: UInt16 = 0x76
    public static let f5: UInt16 = 0x60
    public static let f6: UInt16 = 0x61
    public static let f7: UInt16 = 0x62
    public static let f8: UInt16 = 0x64
    public static let f9: UInt16 = 0x65
    public static let f10: UInt16 = 0x6D
    public static let f11: UInt16 = 0x67
    public static let f12: UInt16 = 0x6F

    // Modifiers
    public static let shift: UInt16 = 0x38
    public static let rightShift: UInt16 = 0x3C
    public static let control: UInt16 = 0x3B
    public static let rightControl: UInt16 = 0x3E
    public static let option: UInt16 = 0x3A
    public static let rightOption: UInt16 = 0x3D
    public static let command: UInt16 = 0x37
    public static let rightCommand: UInt16 = 0x36

    // Keypad
    public static let keypadEnter: UInt16 = 0x4C
}
