// =============================================================================
// AESPMessageType.swift - AESP Protocol Message Types
// =============================================================================
//
// This file defines all message types for the Attic Emulator Server Protocol
// (AESP). AESP is a binary protocol for communication between the emulator
// server and GUI/web clients.
//
// Message types are organized into categories by their numeric range:
// - 0x00-0x3F: Control messages (commands, status)
// - 0x40-0x5F: Input messages (keyboard, joystick, console keys)
// - 0x60-0x7F: Video messages (frame data, configuration)
// - 0x80-0x9F: Audio messages (PCM samples, sync)
//
// Each message type has a corresponding raw value that is transmitted
// in the protocol header's Type field.
//
// =============================================================================

import Foundation

// MARK: - Message Type Enum

/// All AESP protocol message types.
///
/// Message types are grouped into categories based on their function.
/// The raw value is the single-byte type identifier used in the protocol header.
///
/// ## Message Categories
///
/// - **Control (0x00-0x3F)**: Server control, status queries
/// - **Input (0x40-0x5F)**: User input events (keyboard, joystick)
/// - **Video (0x60-0x7F)**: Video frame data and configuration
/// - **Audio (0x80-0x9F)**: Audio sample data and synchronization
///
/// ## Usage
///
/// ```swift
/// let type = AESPMessageType.keyDown
/// let rawValue = type.rawValue  // 0x40
/// let category = type.category  // .input
/// ```
public enum AESPMessageType: UInt8, Sendable, CaseIterable {

    // =========================================================================
    // MARK: - Control Messages (0x00-0x3F)
    // =========================================================================

    /// Ping request - client sends to check server is alive.
    /// Server responds with `pong`.
    /// Payload: Empty
    case ping = 0x00

    /// Pong response - server responds to `ping`.
    /// Payload: Empty
    case pong = 0x01

    /// Pause emulation.
    /// Payload: Empty
    /// Response: `status` message with updated state
    case pause = 0x02

    /// Resume emulation.
    /// Payload: Empty
    /// Response: `status` message with updated state
    case resume = 0x03

    /// Reset emulator (cold or warm boot).
    /// Payload: 1 byte - 0x00 for warm reset, 0x01 for cold reset
    /// Response: `status` message with updated state
    case reset = 0x04

    /// Request or receive emulator status.
    /// Request payload: Empty
    /// Response payload: See `AESPStatusPayload`
    case status = 0x05

    /// Query emulator capabilities and version.
    /// Request payload: Empty
    /// Response payload: See `AESPInfoPayload`
    case info = 0x06

    /// Boot emulator with a file (disk image, executable, BASIC program, etc.).
    /// Calls `libatari800_reboot_with_file` which mounts/loads the file and
    /// performs a cold start.
    /// Request payload: UTF-8 file path string
    /// Response payload: 1 byte status (0x00=success, 0x01=failure) + UTF-8 message
    case bootFile = 0x07

    /// Acknowledge receipt of a command (generic OK response).
    /// Payload: 1 byte - the message type being acknowledged
    case ack = 0x0F

    /// Error response from server.
    /// Payload: 1 byte error code + UTF-8 error message
    case error = 0x3F

    // =========================================================================
    // MARK: - Input Messages (0x40-0x5F)
    // =========================================================================

    /// Key press event.
    /// Payload: See `AESPKeyPayload`
    case keyDown = 0x40

    /// Key release event.
    /// Payload: Empty (releases current key)
    case keyUp = 0x41

    /// Joystick state update.
    /// Payload: See `AESPJoystickPayload`
    case joystick = 0x42

    /// Console keys state (START, SELECT, OPTION).
    /// Payload: 1 byte - bit flags (bit 0=START, bit 1=SELECT, bit 2=OPTION)
    case consoleKeys = 0x43

    /// Paddle position update.
    /// Payload: 1 byte paddle number + 1 byte position (0-228)
    case paddle = 0x44

    // =========================================================================
    // MARK: - Video Messages (0x60-0x7F)
    // =========================================================================

    /// Raw video frame data (uncompressed BGRA).
    /// Payload: 336 * 240 * 4 = 322,560 bytes of BGRA pixel data
    /// Sent at 60fps from server to subscribed clients.
    case frameRaw = 0x60

    /// Delta-encoded video frame (only changed pixels).
    /// Payload: See `AESPFrameDeltaPayload`
    /// Used for web clients to reduce bandwidth.
    case frameDelta = 0x61

    /// Video configuration message.
    /// Payload: See `AESPVideoConfigPayload`
    case frameConfig = 0x62

    /// Request video stream subscription.
    /// Payload: 1 byte - format preference (0x00=raw, 0x01=delta)
    case videoSubscribe = 0x63

    /// Cancel video stream subscription.
    /// Payload: Empty
    case videoUnsubscribe = 0x64

    // =========================================================================
    // MARK: - Audio Messages (0x80-0x9F)
    // =========================================================================

    /// Raw audio PCM samples.
    /// Payload: 16-bit signed PCM samples, mono, native endian
    /// Typically ~735 samples per frame at 44100 Hz / 60 fps
    case audioPCM = 0x80

    /// Audio configuration message.
    /// Payload: See `AESPAudioConfigPayload`
    case audioConfig = 0x81

    /// Audio synchronization timestamp.
    /// Payload: 8 bytes - frame number (UInt64, big-endian)
    /// Used for A/V sync on clients.
    case audioSync = 0x82

    /// Request audio stream subscription.
    /// Payload: Empty
    case audioSubscribe = 0x83

    /// Cancel audio stream subscription.
    /// Payload: Empty
    case audioUnsubscribe = 0x84
}

// MARK: - Message Category

/// Categories of AESP messages, based on their numeric range.
public enum AESPMessageCategory: Sendable {
    /// Control messages (0x00-0x3F): commands, status
    case control

    /// Input messages (0x40-0x5F): keyboard, joystick, console keys
    case input

    /// Video messages (0x60-0x7F): frame data, configuration
    case video

    /// Audio messages (0x80-0x9F): PCM samples, sync
    case audio

    /// Unknown category (for future extension)
    case unknown
}

// MARK: - AESPMessageType Extensions

extension AESPMessageType {

    /// The category this message type belongs to.
    ///
    /// Categories are determined by the numeric range of the message type:
    /// - 0x00-0x3F → `.control`
    /// - 0x40-0x5F → `.input`
    /// - 0x60-0x7F → `.video`
    /// - 0x80-0x9F → `.audio`
    public var category: AESPMessageCategory {
        switch rawValue {
        case 0x00...0x3F:
            return .control
        case 0x40...0x5F:
            return .input
        case 0x60...0x7F:
            return .video
        case 0x80...0x9F:
            return .audio
        default:
            return .unknown
        }
    }

    /// Whether this message type is a request (client → server).
    ///
    /// Requests typically expect a response from the server.
    public var isRequest: Bool {
        switch self {
        case .ping, .pause, .resume, .reset, .status, .info, .bootFile,
             .keyDown, .keyUp, .joystick, .consoleKeys, .paddle,
             .videoSubscribe, .videoUnsubscribe,
             .audioSubscribe, .audioUnsubscribe:
            return true
        default:
            return false
        }
    }

    /// Whether this message type is a response or notification (server → client).
    ///
    /// These messages are sent from the server, either as responses to
    /// requests or as asynchronous notifications.
    public var isResponse: Bool {
        switch self {
        case .pong, .ack, .error,
             .frameRaw, .frameDelta, .frameConfig,
             .audioPCM, .audioConfig, .audioSync:
            return true
        default:
            return false
        }
    }

    /// A human-readable name for this message type.
    public var name: String {
        switch self {
        case .ping: return "PING"
        case .pong: return "PONG"
        case .pause: return "PAUSE"
        case .resume: return "RESUME"
        case .reset: return "RESET"
        case .status: return "STATUS"
        case .info: return "INFO"
        case .bootFile: return "BOOT_FILE"
        case .ack: return "ACK"
        case .error: return "ERROR"
        case .keyDown: return "KEY_DOWN"
        case .keyUp: return "KEY_UP"
        case .joystick: return "JOYSTICK"
        case .consoleKeys: return "CONSOLE_KEYS"
        case .paddle: return "PADDLE"
        case .frameRaw: return "FRAME_RAW"
        case .frameDelta: return "FRAME_DELTA"
        case .frameConfig: return "FRAME_CONFIG"
        case .videoSubscribe: return "VIDEO_SUBSCRIBE"
        case .videoUnsubscribe: return "VIDEO_UNSUBSCRIBE"
        case .audioPCM: return "AUDIO_PCM"
        case .audioConfig: return "AUDIO_CONFIG"
        case .audioSync: return "AUDIO_SYNC"
        case .audioSubscribe: return "AUDIO_SUBSCRIBE"
        case .audioUnsubscribe: return "AUDIO_UNSUBSCRIBE"
        }
    }
}

// MARK: - CustomStringConvertible

extension AESPMessageType: CustomStringConvertible {
    public var description: String {
        return "\(name) (0x\(String(format: "%02X", rawValue)))"
    }
}
