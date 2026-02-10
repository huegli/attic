// =============================================================================
// AESPMessage.swift - AESP Protocol Message Encoding/Decoding
// =============================================================================
//
// This file implements the binary message format for AESP (Attic Emulator
// Server Protocol). All messages share a common 8-byte header followed by
// a variable-length payload.
//
// Header Format:
// ┌────────┬────────┬────────┬────────┬─────────────┐
// │ Magic  │Version │ Type   │ Length │  Payload    │
// │0xAE50  │ 0x01   │(1 byte)│(4 byte)│ (variable)  │
// └────────┴────────┴────────┴────────┴─────────────┘
//    2 bytes  1 byte   1 byte  4 bytes   N bytes
//
// - Magic: 0xAE50 (big-endian) - identifies AESP messages
// - Version: Protocol version (currently 0x01)
// - Type: Message type from AESPMessageType
// - Length: Payload length in bytes (big-endian, 4 bytes)
// - Payload: Type-specific data
//
// All multi-byte integers use big-endian (network) byte order.
//
// =============================================================================

import Foundation

// MARK: - Protocol Constants

/// AESP protocol constants.
public enum AESPConstants {
    /// Magic number identifying AESP messages (0xAE50).
    /// "AE" = Attic Emulator, "50" = Protocol (P=0x50).
    public static let magic: UInt16 = 0xAE50

    /// Current protocol version.
    public static let version: UInt8 = 0x01

    /// Size of the message header in bytes.
    public static let headerSize: Int = 8

    /// Maximum payload size (16 MB - should be more than enough for any message).
    public static let maxPayloadSize: UInt32 = 16 * 1024 * 1024

    /// Default control port.
    public static let defaultControlPort: Int = 47800

    /// Default video port.
    public static let defaultVideoPort: Int = 47801

    /// Default audio port.
    public static let defaultAudioPort: Int = 47802

    /// Default WebSocket port.
    public static let defaultWebSocketPort: Int = 47803

    /// Video frame dimensions.
    public static let frameWidth: Int = 384
    public static let frameHeight: Int = 240
    public static let frameBytesPerPixel: Int = 4  // BGRA
    public static let frameSize: Int = frameWidth * frameHeight * frameBytesPerPixel

    /// Audio sample rate.
    public static let audioSampleRate: Int = 44100
    public static let audioBitsPerSample: Int = 16
    public static let audioChannels: Int = 1  // Mono
}

// MARK: - Protocol Errors

/// Errors that can occur during AESP message encoding/decoding.
public enum AESPError: Error, Sendable, CustomStringConvertible {
    /// Invalid magic number in header.
    case invalidMagic(received: UInt16)

    /// Unsupported protocol version.
    case unsupportedVersion(received: UInt8)

    /// Unknown message type.
    case unknownMessageType(rawValue: UInt8)

    /// Payload too large.
    case payloadTooLarge(size: UInt32)

    /// Insufficient data to decode message.
    case insufficientData(expected: Int, received: Int)

    /// Invalid payload for message type.
    case invalidPayload(messageType: AESPMessageType, reason: String)

    /// Connection error.
    case connectionError(String)

    /// Server error response.
    case serverError(code: UInt8, message: String)

    public var description: String {
        switch self {
        case .invalidMagic(let received):
            return "Invalid AESP magic number: 0x\(String(format: "%04X", received)) (expected 0xAE50)"
        case .unsupportedVersion(let received):
            return "Unsupported AESP version: \(received) (expected \(AESPConstants.version))"
        case .unknownMessageType(let rawValue):
            return "Unknown message type: 0x\(String(format: "%02X", rawValue))"
        case .payloadTooLarge(let size):
            return "Payload too large: \(size) bytes (max \(AESPConstants.maxPayloadSize))"
        case .insufficientData(let expected, let received):
            return "Insufficient data: expected \(expected) bytes, received \(received)"
        case .invalidPayload(let messageType, let reason):
            return "Invalid payload for \(messageType.name): \(reason)"
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

// MARK: - AESP Message

/// An AESP protocol message with type and payload.
///
/// Messages can be created from raw bytes or constructed programmatically.
/// Use the `encode()` method to serialize for transmission, and
/// `decode(from:)` to parse received bytes.
///
/// ## Creating Messages
///
/// ```swift
/// // Create a simple message without payload
/// let pingMessage = AESPMessage(type: .ping)
///
/// // Create a message with payload
/// let keyMessage = AESPMessage(type: .keyDown, payload: keyPayload.encode())
///
/// // Encode for transmission
/// let bytes = pingMessage.encode()
/// ```
///
/// ## Decoding Messages
///
/// ```swift
/// let (message, bytesConsumed) = try AESPMessage.decode(from: receivedData)
/// switch message.type {
/// case .pong:
///     print("Received pong!")
/// case .frameRaw:
///     let pixels = message.payload
///     // Process frame...
/// }
/// ```
public struct AESPMessage: Sendable, Equatable {
    /// The message type.
    public let type: AESPMessageType

    /// The message payload (may be empty).
    public let payload: Data

    /// Creates a new AESP message.
    ///
    /// - Parameters:
    ///   - type: The message type.
    ///   - payload: The payload data (default: empty).
    public init(type: AESPMessageType, payload: Data = Data()) {
        self.type = type
        self.payload = payload
    }

    /// Creates a new AESP message with payload from bytes.
    ///
    /// - Parameters:
    ///   - type: The message type.
    ///   - payload: The payload as a byte array.
    public init(type: AESPMessageType, payload: [UInt8]) {
        self.type = type
        self.payload = Data(payload)
    }

    // =========================================================================
    // MARK: - Encoding
    // =========================================================================

    /// Encodes this message to binary data for transmission.
    ///
    /// The encoded format is:
    /// - 2 bytes: Magic (0xAE50, big-endian)
    /// - 1 byte: Version (0x01)
    /// - 1 byte: Message type
    /// - 4 bytes: Payload length (big-endian)
    /// - N bytes: Payload
    ///
    /// - Returns: The encoded message as Data.
    public func encode() -> Data {
        var data = Data(capacity: AESPConstants.headerSize + payload.count)

        // Magic (2 bytes, big-endian)
        data.append(UInt8((AESPConstants.magic >> 8) & 0xFF))
        data.append(UInt8(AESPConstants.magic & 0xFF))

        // Version (1 byte)
        data.append(AESPConstants.version)

        // Type (1 byte)
        data.append(type.rawValue)

        // Length (4 bytes, big-endian)
        let length = UInt32(payload.count)
        data.append(UInt8((length >> 24) & 0xFF))
        data.append(UInt8((length >> 16) & 0xFF))
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))

        // Payload
        data.append(payload)

        return data
    }

    // =========================================================================
    // MARK: - Decoding
    // =========================================================================

    /// Decodes an AESP message from binary data.
    ///
    /// - Parameter data: The data to decode (must contain at least 8 bytes for header).
    /// - Returns: A tuple of (decoded message, number of bytes consumed).
    /// - Throws: `AESPError` if the data is invalid or incomplete.
    public static func decode(from data: Data) throws -> (AESPMessage, Int) {
        // Check minimum header size
        guard data.count >= AESPConstants.headerSize else {
            throw AESPError.insufficientData(
                expected: AESPConstants.headerSize,
                received: data.count
            )
        }

        // Parse header using withUnsafeBytes to handle Data slices correctly
        let (magic, version, typeRaw, length): (UInt16, UInt8, UInt8, UInt32) = data.withUnsafeBytes { bytes in
            let ptr = bytes.bindMemory(to: UInt8.self)
            let m = UInt16(ptr[0]) << 8 | UInt16(ptr[1])
            let v = ptr[2]
            let t = ptr[3]
            let l = UInt32(ptr[4]) << 24 |
                    UInt32(ptr[5]) << 16 |
                    UInt32(ptr[6]) << 8 |
                    UInt32(ptr[7])
            return (m, v, t, l)
        }

        guard magic == AESPConstants.magic else {
            throw AESPError.invalidMagic(received: magic)
        }

        guard version == AESPConstants.version else {
            throw AESPError.unsupportedVersion(received: version)
        }

        guard let type = AESPMessageType(rawValue: typeRaw) else {
            throw AESPError.unknownMessageType(rawValue: typeRaw)
        }

        guard length <= AESPConstants.maxPayloadSize else {
            throw AESPError.payloadTooLarge(size: length)
        }

        let totalSize = AESPConstants.headerSize + Int(length)
        guard data.count >= totalSize else {
            throw AESPError.insufficientData(expected: totalSize, received: data.count)
        }

        // Extract payload using proper indexing for Data slices
        let payload: Data
        if length > 0 {
            let start = data.startIndex + AESPConstants.headerSize
            let end = data.startIndex + totalSize
            payload = data.subdata(in: start..<end)
        } else {
            payload = Data()
        }

        let message = AESPMessage(type: type, payload: payload)
        return (message, totalSize)
    }

    /// Checks if the data contains a complete message.
    ///
    /// - Parameter data: The data to check.
    /// - Returns: The total message size if complete, or nil if incomplete/invalid.
    public static func messageSize(in data: Data) -> Int? {
        guard data.count >= AESPConstants.headerSize else {
            return nil
        }

        // Use withUnsafeBytes for safe access to Data bytes
        // This avoids issues with Data slices that don't start at index 0
        return data.withUnsafeBytes { bytes -> Int? in
            let ptr = bytes.bindMemory(to: UInt8.self)

            // Verify magic
            let magic = UInt16(ptr[0]) << 8 | UInt16(ptr[1])
            guard magic == AESPConstants.magic else {
                return nil
            }

            // Get payload length
            let length = UInt32(ptr[4]) << 24 |
                         UInt32(ptr[5]) << 16 |
                         UInt32(ptr[6]) << 8 |
                         UInt32(ptr[7])

            let totalSize = AESPConstants.headerSize + Int(length)
            return data.count >= totalSize ? totalSize : nil
        }
    }
}

// MARK: - Convenience Constructors

extension AESPMessage {

    // =========================================================================
    // MARK: - Control Messages
    // =========================================================================

    /// Creates a PING message.
    public static func ping() -> AESPMessage {
        return AESPMessage(type: .ping)
    }

    /// Creates a PONG message.
    public static func pong() -> AESPMessage {
        return AESPMessage(type: .pong)
    }

    /// Creates a PAUSE message.
    public static func pause() -> AESPMessage {
        return AESPMessage(type: .pause)
    }

    /// Creates a RESUME message.
    public static func resume() -> AESPMessage {
        return AESPMessage(type: .resume)
    }

    /// Creates a RESET message.
    ///
    /// - Parameter cold: If true, performs a cold reset (power cycle).
    ///                   If false, performs a warm reset.
    public static func reset(cold: Bool) -> AESPMessage {
        return AESPMessage(type: .reset, payload: [cold ? 0x01 : 0x00])
    }

    /// Creates a STATUS request message.
    public static func status() -> AESPMessage {
        return AESPMessage(type: .status)
    }

    /// Creates an INFO request message.
    public static func info() -> AESPMessage {
        return AESPMessage(type: .info)
    }

    /// Creates a STATUS response message (basic, no disk info).
    ///
    /// - Parameter isRunning: Whether the emulator is running.
    public static func statusResponse(isRunning: Bool) -> AESPMessage {
        return AESPMessage(type: .status, payload: [isRunning ? 0x01 : 0x00])
    }

    /// Creates a STATUS response message with mounted drive information.
    ///
    /// The payload format is backwards-compatible with the basic status response:
    /// - Byte 0: isRunning flag (0x00 = paused, 0x01 = running)
    /// - Byte 1: number of mounted drives (N)
    /// - For each mounted drive:
    ///   - 1 byte: drive number (1-8)
    ///   - 1 byte: filename length (L)
    ///   - L bytes: filename as UTF-8 string
    ///
    /// Clients that only read byte 0 (the old format) will still work correctly.
    ///
    /// - Parameters:
    ///   - isRunning: Whether the emulator is running.
    ///   - mountedDrives: Array of (drive number, filename) tuples for mounted drives.
    public static func statusResponse(
        isRunning: Bool,
        mountedDrives: [(drive: Int, filename: String)]
    ) -> AESPMessage {
        var payload = Data()
        // Byte 0: running flag
        payload.append(isRunning ? 0x01 : 0x00)
        // Byte 1: number of mounted drives
        payload.append(UInt8(min(mountedDrives.count, 255)))
        // Drive records
        for (drive, filename) in mountedDrives {
            payload.append(UInt8(drive & 0xFF))
            let filenameBytes = Array(filename.utf8)
            payload.append(UInt8(min(filenameBytes.count, 255)))
            payload.append(contentsOf: filenameBytes.prefix(255))
        }
        return AESPMessage(type: .status, payload: payload)
    }

    /// Creates an INFO response message.
    ///
    /// - Parameter json: The JSON payload with version and capabilities.
    public static func infoResponse(json: String) -> AESPMessage {
        return AESPMessage(type: .info, payload: Data(json.utf8))
    }

    /// Creates a BOOT_FILE request message.
    ///
    /// Requests the server to load a file and reboot the emulator.
    /// Supported file types include disk images (ATR, XFD, ATX, DCM, PRO),
    /// executables (XEX, COM, EXE), BASIC programs (BAS, LST), cartridges
    /// (CART, ROM), and cassettes (CAS).
    ///
    /// - Parameter filePath: Absolute path to the file to boot.
    public static func bootFile(filePath: String) -> AESPMessage {
        return AESPMessage(type: .bootFile, payload: Data(filePath.utf8))
    }

    /// Creates a BOOT_FILE response message.
    ///
    /// - Parameters:
    ///   - success: Whether the boot was successful.
    ///   - message: Description of outcome (e.g. file type on success,
    ///     error message on failure).
    public static func bootFileResponse(success: Bool, message: String) -> AESPMessage {
        var payload = Data(capacity: 1 + message.utf8.count)
        payload.append(success ? 0x00 : 0x01)
        payload.append(contentsOf: message.utf8)
        return AESPMessage(type: .bootFile, payload: payload)
    }

    /// Creates an ACK message.
    ///
    /// - Parameter acknowledgedType: The message type being acknowledged.
    public static func ack(for acknowledgedType: AESPMessageType) -> AESPMessage {
        return AESPMessage(type: .ack, payload: [acknowledgedType.rawValue])
    }

    /// Creates a MEMORY_READ request message.
    ///
    /// - Parameters:
    ///   - address: The memory address to read from.
    ///   - count: The number of bytes to read.
    public static func memoryRead(address: UInt16, count: UInt16) -> AESPMessage {
        var payload = Data(capacity: 4)
        payload.append(UInt8((address >> 8) & 0xFF))
        payload.append(UInt8(address & 0xFF))
        payload.append(UInt8((count >> 8) & 0xFF))
        payload.append(UInt8(count & 0xFF))
        return AESPMessage(type: .memoryRead, payload: payload)
    }

    /// Creates a MEMORY_WRITE message.
    ///
    /// - Parameters:
    ///   - address: The memory address to write to.
    ///   - bytes: The data to write.
    public static func memoryWrite(address: UInt16, bytes: Data) -> AESPMessage {
        var payload = Data(capacity: 2 + bytes.count)
        payload.append(UInt8((address >> 8) & 0xFF))
        payload.append(UInt8(address & 0xFF))
        payload.append(bytes)
        return AESPMessage(type: .memoryWrite, payload: payload)
    }

    /// Creates an ERROR message.
    ///
    /// - Parameters:
    ///   - code: Error code.
    ///   - message: Human-readable error message.
    public static func error(code: UInt8, message: String) -> AESPMessage {
        var payload = Data(capacity: 1 + message.utf8.count)
        payload.append(code)
        payload.append(contentsOf: message.utf8)
        return AESPMessage(type: .error, payload: payload)
    }

    /// Creates a REGISTERS_READ request message.
    public static func registersRead() -> AESPMessage {
        return AESPMessage(type: .registersRead)
    }

    /// Creates a REGISTERS_READ response message.
    ///
    /// - Parameters:
    ///   - a: Accumulator register.
    ///   - x: X index register.
    ///   - y: Y index register.
    ///   - s: Stack pointer.
    ///   - p: Processor status.
    ///   - pc: Program counter.
    public static func registersResponse(
        a: UInt8, x: UInt8, y: UInt8, s: UInt8, p: UInt8, pc: UInt16
    ) -> AESPMessage {
        var payload = Data(capacity: 8)
        payload.append(a)
        payload.append(x)
        payload.append(y)
        payload.append(s)
        payload.append(p)
        payload.append(UInt8((pc >> 8) & 0xFF))
        payload.append(UInt8(pc & 0xFF))
        payload.append(0x00) // Reserved
        return AESPMessage(type: .registersRead, payload: payload)
    }

    /// Creates a REGISTERS_WRITE request message.
    ///
    /// - Parameters:
    ///   - a: Accumulator register.
    ///   - x: X index register.
    ///   - y: Y index register.
    ///   - s: Stack pointer.
    ///   - p: Processor status.
    ///   - pc: Program counter.
    public static func registersWrite(
        a: UInt8, x: UInt8, y: UInt8, s: UInt8, p: UInt8, pc: UInt16
    ) -> AESPMessage {
        var payload = Data(capacity: 8)
        payload.append(a)
        payload.append(x)
        payload.append(y)
        payload.append(s)
        payload.append(p)
        payload.append(UInt8((pc >> 8) & 0xFF))
        payload.append(UInt8(pc & 0xFF))
        payload.append(0x00) // Reserved
        return AESPMessage(type: .registersWrite, payload: payload)
    }

    /// Creates a BREAKPOINT_SET message.
    ///
    /// - Parameter address: The address to set a breakpoint at.
    public static func breakpointSet(address: UInt16) -> AESPMessage {
        var payload = Data(capacity: 2)
        payload.append(UInt8((address >> 8) & 0xFF))
        payload.append(UInt8(address & 0xFF))
        return AESPMessage(type: .breakpointSet, payload: payload)
    }

    /// Creates a BREAKPOINT_CLEAR message.
    ///
    /// - Parameter address: The address to clear a breakpoint at.
    public static func breakpointClear(address: UInt16) -> AESPMessage {
        var payload = Data(capacity: 2)
        payload.append(UInt8((address >> 8) & 0xFF))
        payload.append(UInt8(address & 0xFF))
        return AESPMessage(type: .breakpointClear, payload: payload)
    }

    /// Creates a BREAKPOINT_LIST request message.
    public static func breakpointList() -> AESPMessage {
        return AESPMessage(type: .breakpointList)
    }

    /// Creates a BREAKPOINT_LIST response message.
    ///
    /// - Parameter addresses: The list of breakpoint addresses.
    public static func breakpointListResponse(addresses: [UInt16]) -> AESPMessage {
        var payload = Data(capacity: addresses.count * 2)
        for address in addresses {
            payload.append(UInt8((address >> 8) & 0xFF))
            payload.append(UInt8(address & 0xFF))
        }
        return AESPMessage(type: .breakpointList, payload: payload)
    }

    /// Creates a BREAKPOINT_HIT notification message.
    ///
    /// - Parameter address: The address where the breakpoint was hit.
    public static func breakpointHit(address: UInt16) -> AESPMessage {
        var payload = Data(capacity: 2)
        payload.append(UInt8((address >> 8) & 0xFF))
        payload.append(UInt8(address & 0xFF))
        return AESPMessage(type: .breakpointHit, payload: payload)
    }

    // =========================================================================
    // MARK: - Input Messages
    // =========================================================================

    /// Creates a KEY_DOWN message.
    ///
    /// - Parameters:
    ///   - keyChar: The ATASCII character code (0 for special keys).
    ///   - keyCode: The Atari key code (AKEY_* constant).
    ///   - shift: Whether Shift is held.
    ///   - control: Whether Control is held.
    public static func keyDown(
        keyChar: UInt8,
        keyCode: UInt8,
        shift: Bool,
        control: Bool
    ) -> AESPMessage {
        var flags: UInt8 = 0
        if shift { flags |= 0x01 }
        if control { flags |= 0x02 }
        return AESPMessage(type: .keyDown, payload: [keyChar, keyCode, flags])
    }

    /// Creates a KEY_UP message.
    public static func keyUp() -> AESPMessage {
        return AESPMessage(type: .keyUp)
    }

    /// Creates a JOYSTICK message.
    ///
    /// - Parameters:
    ///   - port: Joystick port (0 or 1).
    ///   - directions: Direction bits (bit 0=up, 1=down, 2=left, 3=right).
    ///   - trigger: Whether the trigger/button is pressed.
    public static func joystick(port: UInt8, directions: UInt8, trigger: Bool) -> AESPMessage {
        var flags = directions & 0x0F
        if trigger { flags |= 0x10 }
        return AESPMessage(type: .joystick, payload: [port, flags])
    }

    /// Creates a CONSOLE_KEYS message.
    ///
    /// - Parameters:
    ///   - start: Whether START is pressed.
    ///   - select: Whether SELECT is pressed.
    ///   - option: Whether OPTION is pressed.
    public static func consoleKeys(start: Bool, select: Bool, option: Bool) -> AESPMessage {
        var flags: UInt8 = 0
        if start { flags |= 0x01 }
        if select { flags |= 0x02 }
        if option { flags |= 0x04 }
        return AESPMessage(type: .consoleKeys, payload: [flags])
    }

    /// Creates a PADDLE message.
    ///
    /// - Parameters:
    ///   - number: The paddle number (0-3).
    ///   - position: The paddle position (0-228).
    public static func paddle(number: UInt8, position: UInt8) -> AESPMessage {
        return AESPMessage(type: .paddle, payload: [number, position])
    }

    // =========================================================================
    // MARK: - Video Messages
    // =========================================================================

    /// Creates a FRAME_RAW message with video frame data.
    ///
    /// - Parameter pixels: BGRA pixel data (384 * 240 * 4 = 368,640 bytes).
    public static func frameRaw(pixels: Data) -> AESPMessage {
        return AESPMessage(type: .frameRaw, payload: pixels)
    }

    /// Creates a FRAME_RAW message with video frame data from a byte array.
    ///
    /// - Parameter pixels: BGRA pixel data (384 * 240 * 4 = 368,640 bytes).
    public static func frameRaw(pixels: [UInt8]) -> AESPMessage {
        return AESPMessage(type: .frameRaw, payload: pixels)
    }

    /// Creates a FRAME_DELTA message with delta-encoded video data.
    ///
    /// - Parameter payload: Delta-encoded pixel data.
    public static func frameDelta(payload: Data) -> AESPMessage {
        return AESPMessage(type: .frameDelta, payload: payload)
    }

    /// Creates a FRAME_CONFIG message.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - bytesPerPixel: Bytes per pixel.
    ///   - fps: Target frame rate.
    public static func frameConfig(
        width: UInt16,
        height: UInt16,
        bytesPerPixel: UInt8,
        fps: UInt8
    ) -> AESPMessage {
        var payload = Data(capacity: 6)
        payload.append(UInt8((width >> 8) & 0xFF))
        payload.append(UInt8(width & 0xFF))
        payload.append(UInt8((height >> 8) & 0xFF))
        payload.append(UInt8(height & 0xFF))
        payload.append(bytesPerPixel)
        payload.append(fps)
        return AESPMessage(type: .frameConfig, payload: payload)
    }

    /// Creates a VIDEO_SUBSCRIBE message.
    ///
    /// - Parameter deltaEncoding: If true, request delta-encoded frames.
    public static func videoSubscribe(deltaEncoding: Bool = false) -> AESPMessage {
        return AESPMessage(type: .videoSubscribe, payload: [deltaEncoding ? 0x01 : 0x00])
    }

    /// Creates a VIDEO_UNSUBSCRIBE message.
    public static func videoUnsubscribe() -> AESPMessage {
        return AESPMessage(type: .videoUnsubscribe)
    }

    // =========================================================================
    // MARK: - Audio Messages
    // =========================================================================

    /// Creates an AUDIO_PCM message with audio samples.
    ///
    /// - Parameter samples: 16-bit signed PCM samples.
    public static func audioPCM(samples: Data) -> AESPMessage {
        return AESPMessage(type: .audioPCM, payload: samples)
    }

    /// Creates an AUDIO_CONFIG message.
    ///
    /// - Parameters:
    ///   - sampleRate: Audio sample rate (e.g., 44100).
    ///   - bitsPerSample: Bits per sample (e.g., 16).
    ///   - channels: Number of channels (e.g., 1 for mono).
    public static func audioConfig(
        sampleRate: UInt32,
        bitsPerSample: UInt8,
        channels: UInt8
    ) -> AESPMessage {
        var payload = Data(capacity: 6)
        payload.append(UInt8((sampleRate >> 24) & 0xFF))
        payload.append(UInt8((sampleRate >> 16) & 0xFF))
        payload.append(UInt8((sampleRate >> 8) & 0xFF))
        payload.append(UInt8(sampleRate & 0xFF))
        payload.append(bitsPerSample)
        payload.append(channels)
        return AESPMessage(type: .audioConfig, payload: payload)
    }

    /// Creates an AUDIO_SYNC message.
    ///
    /// - Parameter frameNumber: The current frame number for synchronization.
    public static func audioSync(frameNumber: UInt64) -> AESPMessage {
        var payload = Data(capacity: 8)
        payload.append(UInt8((frameNumber >> 56) & 0xFF))
        payload.append(UInt8((frameNumber >> 48) & 0xFF))
        payload.append(UInt8((frameNumber >> 40) & 0xFF))
        payload.append(UInt8((frameNumber >> 32) & 0xFF))
        payload.append(UInt8((frameNumber >> 24) & 0xFF))
        payload.append(UInt8((frameNumber >> 16) & 0xFF))
        payload.append(UInt8((frameNumber >> 8) & 0xFF))
        payload.append(UInt8(frameNumber & 0xFF))
        return AESPMessage(type: .audioSync, payload: payload)
    }

    /// Creates an AUDIO_SUBSCRIBE message.
    public static func audioSubscribe() -> AESPMessage {
        return AESPMessage(type: .audioSubscribe)
    }

    /// Creates an AUDIO_UNSUBSCRIBE message.
    public static func audioUnsubscribe() -> AESPMessage {
        return AESPMessage(type: .audioUnsubscribe)
    }
}

// MARK: - Payload Parsing Helpers

extension AESPMessage {

    /// Parses the payload as a key event.
    ///
    /// - Returns: Tuple of (keyChar, keyCode, shift, control), or nil if invalid.
    public func parseKeyPayload() -> (keyChar: UInt8, keyCode: UInt8, shift: Bool, control: Bool)? {
        guard type == .keyDown, payload.count >= 3 else { return nil }
        let flags = payload[2]
        return (
            keyChar: payload[0],
            keyCode: payload[1],
            shift: (flags & 0x01) != 0,
            control: (flags & 0x02) != 0
        )
    }

    /// Parses the payload as a joystick event.
    ///
    /// - Returns: Tuple of (port, up, down, left, right, trigger), or nil if invalid.
    public func parseJoystickPayload() -> (
        port: UInt8,
        up: Bool,
        down: Bool,
        left: Bool,
        right: Bool,
        trigger: Bool
    )? {
        guard type == .joystick, payload.count >= 2 else { return nil }
        let flags = payload[1]
        return (
            port: payload[0],
            up: (flags & 0x01) != 0,
            down: (flags & 0x02) != 0,
            left: (flags & 0x04) != 0,
            right: (flags & 0x08) != 0,
            trigger: (flags & 0x10) != 0
        )
    }

    /// Parses the payload as console keys state.
    ///
    /// - Returns: Tuple of (start, select, option), or nil if invalid.
    public func parseConsoleKeysPayload() -> (start: Bool, select: Bool, option: Bool)? {
        guard type == .consoleKeys, payload.count >= 1 else { return nil }
        let flags = payload[0]
        return (
            start: (flags & 0x01) != 0,
            select: (flags & 0x02) != 0,
            option: (flags & 0x04) != 0
        )
    }

    /// Parses the payload as a memory read request.
    ///
    /// - Returns: Tuple of (address, count), or nil if invalid.
    public func parseMemoryReadRequest() -> (address: UInt16, count: UInt16)? {
        guard type == .memoryRead, payload.count >= 4 else { return nil }
        let address = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let count = UInt16(payload[2]) << 8 | UInt16(payload[3])
        return (address: address, count: count)
    }

    /// Parses the payload as a memory write request.
    ///
    /// - Returns: Tuple of (address, data), or nil if invalid.
    public func parseMemoryWriteRequest() -> (address: UInt16, data: Data)? {
        guard type == .memoryWrite, payload.count >= 2 else { return nil }
        let address = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let data = payload.count > 2 ? payload.subdata(in: 2..<payload.count) : Data()
        return (address: address, data: data)
    }

    /// Parses the payload as a boot file request.
    ///
    /// - Returns: The file path string, or nil if invalid.
    public func parseBootFileRequest() -> String? {
        guard type == .bootFile, !payload.isEmpty else { return nil }
        return String(decoding: payload, as: UTF8.self)
    }

    /// Parses the payload as a boot file response.
    ///
    /// - Returns: Tuple of (success, message), or nil if invalid.
    public func parseBootFileResponse() -> (success: Bool, message: String)? {
        guard type == .bootFile, payload.count >= 1 else { return nil }
        let success = payload[0] == 0x00
        let message: String
        if payload.count > 1 {
            message = String(decoding: payload[1...], as: UTF8.self)
        } else {
            message = ""
        }
        return (success: success, message: message)
    }

    /// Parses the payload as an error response.
    ///
    /// - Returns: Tuple of (code, message), or nil if invalid.
    public func parseErrorPayload() -> (code: UInt8, message: String)? {
        guard type == .error, payload.count >= 1 else { return nil }
        let code = payload[0]
        let message: String
        if payload.count > 1 {
            message = String(decoding: payload[1...], as: UTF8.self)
        } else {
            message = ""
        }
        return (code: code, message: message)
    }

    /// Parses the payload as an audio sync frame number.
    ///
    /// - Returns: The frame number, or nil if invalid.
    public func parseAudioSyncPayload() -> UInt64? {
        guard type == .audioSync, payload.count >= 8 else { return nil }
        // Break up expression to help compiler type-check
        let b0 = UInt64(payload[0]) << 56
        let b1 = UInt64(payload[1]) << 48
        let b2 = UInt64(payload[2]) << 40
        let b3 = UInt64(payload[3]) << 32
        let b4 = UInt64(payload[4]) << 24
        let b5 = UInt64(payload[5]) << 16
        let b6 = UInt64(payload[6]) << 8
        let b7 = UInt64(payload[7])
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
    }

    /// Parses the payload as a status response (basic, running flag only).
    ///
    /// - Returns: Whether the emulator is running, or nil if invalid.
    public func parseStatusPayload() -> Bool? {
        guard type == .status, payload.count >= 1 else { return nil }
        return payload[0] != 0
    }

    /// Enhanced status payload containing running state and mounted drive info.
    public struct StatusPayload: Sendable {
        /// Whether the emulator is currently running.
        public let isRunning: Bool
        /// Array of mounted drives with their drive number and filename.
        public let mountedDrives: [(drive: Int, filename: String)]
    }

    /// Parses the payload as an enhanced status response with disk information.
    ///
    /// This parser is backwards-compatible: if the payload only has the single
    /// running-flag byte (old format), it returns an empty mountedDrives array.
    /// If the payload includes drive records (new format), those are parsed too.
    ///
    /// - Returns: A `StatusPayload` with running state and mounted drives,
    ///   or nil if the payload is invalid.
    public func parseStatusWithDisks() -> StatusPayload? {
        guard type == .status, payload.count >= 1 else { return nil }
        let isRunning = payload[0] != 0

        // Old format: single byte payload, no disk info
        guard payload.count >= 2 else {
            return StatusPayload(isRunning: isRunning, mountedDrives: [])
        }

        let driveCount = Int(payload[1])
        var drives: [(drive: Int, filename: String)] = []
        var offset = 2

        for _ in 0..<driveCount {
            // Need at least 2 bytes (drive number + filename length)
            guard offset + 2 <= payload.count else { break }
            let driveNumber = Int(payload[offset])
            let filenameLength = Int(payload[offset + 1])
            offset += 2

            // Read filename bytes
            guard offset + filenameLength <= payload.count else { break }
            let filenameData = payload[offset..<(offset + filenameLength)]
            let filename = String(decoding: filenameData, as: UTF8.self)
            offset += filenameLength

            drives.append((drive: driveNumber, filename: filename))
        }

        return StatusPayload(isRunning: isRunning, mountedDrives: drives)
    }

    /// Parses the payload as an info response.
    ///
    /// - Returns: The JSON string, or nil if invalid.
    public func parseInfoPayload() -> String? {
        guard type == .info, !payload.isEmpty else { return nil }
        return String(decoding: payload, as: UTF8.self)
    }

    /// CPU register values.
    public struct CPURegisters {
        public let a: UInt8
        public let x: UInt8
        public let y: UInt8
        public let s: UInt8
        public let p: UInt8
        public let pc: UInt16
    }

    /// Parses the payload as a registers response.
    ///
    /// - Returns: The CPU register values, or nil if invalid.
    public func parseRegistersPayload() -> CPURegisters? {
        guard type == .registersRead || type == .registersWrite,
              payload.count >= 7 else { return nil }
        let pc = UInt16(payload[5]) << 8 | UInt16(payload[6])
        return CPURegisters(
            a: payload[0],
            x: payload[1],
            y: payload[2],
            s: payload[3],
            p: payload[4],
            pc: pc
        )
    }

    /// Parses the payload as a breakpoint list response.
    ///
    /// - Returns: Array of breakpoint addresses, or nil if invalid.
    public func parseBreakpointListPayload() -> [UInt16]? {
        guard type == .breakpointList else { return nil }
        guard payload.count % 2 == 0 else { return nil }

        var addresses: [UInt16] = []
        for i in stride(from: 0, to: payload.count, by: 2) {
            let address = UInt16(payload[i]) << 8 | UInt16(payload[i + 1])
            addresses.append(address)
        }
        return addresses
    }

    /// Parses the payload as a breakpoint hit notification.
    ///
    /// - Returns: The address where breakpoint was hit, or nil if invalid.
    public func parseBreakpointHitPayload() -> UInt16? {
        guard type == .breakpointHit, payload.count >= 2 else { return nil }
        return UInt16(payload[0]) << 8 | UInt16(payload[1])
    }

    /// Parses the payload as a paddle event.
    ///
    /// - Returns: Tuple of (paddle number, position), or nil if invalid.
    public func parsePaddlePayload() -> (number: UInt8, position: UInt8)? {
        guard type == .paddle, payload.count >= 2 else { return nil }
        return (number: payload[0], position: payload[1])
    }

    /// Frame configuration values.
    public struct FrameConfig {
        public let width: UInt16
        public let height: UInt16
        public let bytesPerPixel: UInt8
        public let fps: UInt8
    }

    /// Parses the payload as a frame config response.
    ///
    /// - Returns: The frame configuration, or nil if invalid.
    public func parseFrameConfigPayload() -> FrameConfig? {
        guard type == .frameConfig, payload.count >= 6 else { return nil }
        let width = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let height = UInt16(payload[2]) << 8 | UInt16(payload[3])
        return FrameConfig(
            width: width,
            height: height,
            bytesPerPixel: payload[4],
            fps: payload[5]
        )
    }

    /// Audio configuration values.
    public struct AudioConfig {
        public let sampleRate: UInt32
        public let bitsPerSample: UInt8
        public let channels: UInt8
    }

    /// Parses the payload as an audio config response.
    ///
    /// - Returns: The audio configuration, or nil if invalid.
    public func parseAudioConfigPayload() -> AudioConfig? {
        guard type == .audioConfig, payload.count >= 6 else { return nil }
        let sampleRate = UInt32(payload[0]) << 24 |
                         UInt32(payload[1]) << 16 |
                         UInt32(payload[2]) << 8 |
                         UInt32(payload[3])
        return AudioConfig(
            sampleRate: sampleRate,
            bitsPerSample: payload[4],
            channels: payload[5]
        )
    }
}

// MARK: - CustomStringConvertible

extension AESPMessage: CustomStringConvertible {
    public var description: String {
        return "AESPMessage(\(type.name), \(payload.count) bytes)"
    }
}
