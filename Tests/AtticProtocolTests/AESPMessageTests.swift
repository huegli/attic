// =============================================================================
// AESPMessageTests.swift - Unit Tests for AESP Message Encoding/Decoding
// =============================================================================
//
// This file contains comprehensive unit tests for the AESP (Attic Emulator
// Server Protocol) message encoding and decoding. Tests cover:
//
// - Header validation (magic, version, type, length)
// - All message types (control, input, video, audio)
// - Payload encoding/decoding for each message type
// - Error handling for malformed messages
// - Round-trip encoding/decoding
//
// Test coverage follows the specification in docs/PROTOCOL.md.
//
// =============================================================================

import XCTest
@testable import AtticProtocol

// =============================================================================
// MARK: - Constants Tests
// =============================================================================

/// Tests for AESP protocol constants.
final class AESPConstantsTests: XCTestCase {

    /// Test magic number is correct.
    func test_magic_isAE50() {
        XCTAssertEqual(AESPConstants.magic, 0xAE50)
    }

    /// Test version is 1.
    func test_version_isOne() {
        XCTAssertEqual(AESPConstants.version, 0x01)
    }

    /// Test header size is 8 bytes.
    func test_headerSize_isEight() {
        XCTAssertEqual(AESPConstants.headerSize, 8)
    }

    /// Test max payload size is 16 MB.
    func test_maxPayloadSize_is16MB() {
        XCTAssertEqual(AESPConstants.maxPayloadSize, 16 * 1024 * 1024)
    }

    /// Test default ports.
    func test_defaultPorts() {
        XCTAssertEqual(AESPConstants.defaultControlPort, 47800)
        XCTAssertEqual(AESPConstants.defaultVideoPort, 47801)
        XCTAssertEqual(AESPConstants.defaultAudioPort, 47802)
        XCTAssertEqual(AESPConstants.defaultWebSocketPort, 47803)
    }

    /// Test frame dimensions.
    func test_frameDimensions() {
        XCTAssertEqual(AESPConstants.frameWidth, 384)
        XCTAssertEqual(AESPConstants.frameHeight, 240)
        XCTAssertEqual(AESPConstants.frameBytesPerPixel, 4)
        XCTAssertEqual(AESPConstants.frameSize, 384 * 240 * 4)
    }

    /// Test audio parameters.
    func test_audioParameters() {
        XCTAssertEqual(AESPConstants.audioSampleRate, 44100)
        XCTAssertEqual(AESPConstants.audioBitsPerSample, 16)
        XCTAssertEqual(AESPConstants.audioChannels, 1)
    }
}

// =============================================================================
// MARK: - Message Type Tests
// =============================================================================

/// Tests for AESPMessageType enum.
final class AESPMessageTypeTests: XCTestCase {

    /// Test control messages are in correct range.
    func test_controlMessages_inCorrectRange() {
        let controlTypes: [AESPMessageType] = [
            .ping, .pong, .pause, .resume, .reset, .status, .info, .ack,
            .error
        ]

        for type in controlTypes {
            XCTAssertEqual(type.category, .control, "\(type) should be control")
            XCTAssertTrue(type.rawValue <= 0x3F, "\(type) raw value should be <= 0x3F")
        }
    }

    /// Test input messages are in correct range.
    func test_inputMessages_inCorrectRange() {
        let inputTypes: [AESPMessageType] = [
            .keyDown, .keyUp, .joystick, .consoleKeys, .paddle
        ]

        for type in inputTypes {
            XCTAssertEqual(type.category, .input, "\(type) should be input")
            XCTAssertTrue(type.rawValue >= 0x40 && type.rawValue <= 0x5F,
                         "\(type) raw value should be in 0x40-0x5F")
        }
    }

    /// Test video messages are in correct range.
    func test_videoMessages_inCorrectRange() {
        let videoTypes: [AESPMessageType] = [
            .frameRaw, .frameDelta, .frameConfig, .videoSubscribe, .videoUnsubscribe
        ]

        for type in videoTypes {
            XCTAssertEqual(type.category, .video, "\(type) should be video")
            XCTAssertTrue(type.rawValue >= 0x60 && type.rawValue <= 0x7F,
                         "\(type) raw value should be in 0x60-0x7F")
        }
    }

    /// Test audio messages are in correct range.
    func test_audioMessages_inCorrectRange() {
        let audioTypes: [AESPMessageType] = [
            .audioPCM, .audioConfig, .audioSync, .audioSubscribe, .audioUnsubscribe
        ]

        for type in audioTypes {
            XCTAssertEqual(type.category, .audio, "\(type) should be audio")
            XCTAssertTrue(type.rawValue >= 0x80 && type.rawValue <= 0x9F,
                         "\(type) raw value should be in 0x80-0x9F")
        }
    }

    /// Test request/response classification.
    func test_requestResponseClassification() {
        // Requests (client -> server)
        XCTAssertTrue(AESPMessageType.ping.isRequest)
        XCTAssertTrue(AESPMessageType.pause.isRequest)
        XCTAssertTrue(AESPMessageType.keyDown.isRequest)
        XCTAssertTrue(AESPMessageType.videoSubscribe.isRequest)

        // Responses (server -> client)
        XCTAssertTrue(AESPMessageType.pong.isResponse)
        XCTAssertTrue(AESPMessageType.ack.isResponse)
        XCTAssertTrue(AESPMessageType.frameRaw.isResponse)
        XCTAssertTrue(AESPMessageType.audioPCM.isResponse)
    }

    /// Test all types have names.
    func test_allTypesHaveNames() {
        for type in AESPMessageType.allCases {
            XCTAssertFalse(type.name.isEmpty, "\(type) should have a name")
        }
    }

    /// Test specific raw values per PROTOCOL.md.
    func test_specificRawValues() {
        XCTAssertEqual(AESPMessageType.ping.rawValue, 0x00)
        XCTAssertEqual(AESPMessageType.pong.rawValue, 0x01)
        XCTAssertEqual(AESPMessageType.pause.rawValue, 0x02)
        XCTAssertEqual(AESPMessageType.resume.rawValue, 0x03)
        XCTAssertEqual(AESPMessageType.reset.rawValue, 0x04)
        XCTAssertEqual(AESPMessageType.status.rawValue, 0x05)
        XCTAssertEqual(AESPMessageType.ack.rawValue, 0x0F)
        XCTAssertEqual(AESPMessageType.keyDown.rawValue, 0x40)
        XCTAssertEqual(AESPMessageType.keyUp.rawValue, 0x41)
        XCTAssertEqual(AESPMessageType.joystick.rawValue, 0x42)
        XCTAssertEqual(AESPMessageType.consoleKeys.rawValue, 0x43)
        XCTAssertEqual(AESPMessageType.frameRaw.rawValue, 0x60)
        XCTAssertEqual(AESPMessageType.videoSubscribe.rawValue, 0x63)
        XCTAssertEqual(AESPMessageType.audioPCM.rawValue, 0x80)
        XCTAssertEqual(AESPMessageType.audioSubscribe.rawValue, 0x83)
        XCTAssertEqual(AESPMessageType.error.rawValue, 0x3F)
        XCTAssertEqual(AESPMessageType.bootFile.rawValue, 0x07)
    }
}

// =============================================================================
// MARK: - Message Encoding Tests
// =============================================================================

/// Tests for AESP message encoding.
final class AESPMessageEncodingTests: XCTestCase {

    /// Test header encoding format.
    func test_encode_headerFormat() {
        let message = AESPMessage(type: .ping)
        let encoded = message.encode()

        // Header should be 8 bytes
        XCTAssertEqual(encoded.count, 8)

        // Magic (big-endian): 0xAE, 0x50
        XCTAssertEqual(encoded[0], 0xAE)
        XCTAssertEqual(encoded[1], 0x50)

        // Version: 0x01
        XCTAssertEqual(encoded[2], 0x01)

        // Type: 0x00 (PING)
        XCTAssertEqual(encoded[3], 0x00)

        // Length (big-endian, 4 bytes): 0x00, 0x00, 0x00, 0x00
        XCTAssertEqual(encoded[4], 0x00)
        XCTAssertEqual(encoded[5], 0x00)
        XCTAssertEqual(encoded[6], 0x00)
        XCTAssertEqual(encoded[7], 0x00)
    }

    /// Test encoding with payload.
    func test_encode_withPayload() {
        let payload: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        let message = AESPMessage(type: .reset, payload: payload)
        let encoded = message.encode()

        // Total size: 8 header + 4 payload
        XCTAssertEqual(encoded.count, 12)

        // Length should be 4
        XCTAssertEqual(encoded[4], 0x00)
        XCTAssertEqual(encoded[5], 0x00)
        XCTAssertEqual(encoded[6], 0x00)
        XCTAssertEqual(encoded[7], 0x04)

        // Payload follows header
        XCTAssertEqual(encoded[8], 0x01)
        XCTAssertEqual(encoded[9], 0x02)
        XCTAssertEqual(encoded[10], 0x03)
        XCTAssertEqual(encoded[11], 0x04)
    }

    /// Test encoding PING message.
    func test_encode_ping() {
        let message = AESPMessage.ping()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.ping.rawValue)
    }

    /// Test encoding PONG message.
    func test_encode_pong() {
        let message = AESPMessage.pong()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.pong.rawValue)
    }

    /// Test encoding RESET message with cold flag.
    func test_encode_reset_cold() {
        let message = AESPMessage.reset(cold: true)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[3], AESPMessageType.reset.rawValue)
        XCTAssertEqual(encoded[8], 0x01) // cold = true
    }

    /// Test encoding RESET message with warm flag.
    func test_encode_reset_warm() {
        let message = AESPMessage.reset(cold: false)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[8], 0x00) // cold = false (warm reset)
    }

    /// Test encoding ACK message.
    func test_encode_ack() {
        let message = AESPMessage.ack(for: .pause)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[3], AESPMessageType.ack.rawValue)
        XCTAssertEqual(encoded[8], AESPMessageType.pause.rawValue)
    }

    /// Test encoding KEY_DOWN message.
    func test_encode_keyDown() {
        // 'A' key with shift
        let message = AESPMessage.keyDown(keyChar: 0x41, keyCode: 0x3F, shift: true, control: false)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 11) // 8 header + 3 payload
        XCTAssertEqual(encoded[3], AESPMessageType.keyDown.rawValue)

        // Key char
        XCTAssertEqual(encoded[8], 0x41)
        // Key code
        XCTAssertEqual(encoded[9], 0x3F)
        // Flags: shift=true (bit 0), control=false (bit 1)
        XCTAssertEqual(encoded[10], 0x01)
    }

    /// Test encoding KEY_DOWN with control modifier.
    func test_encode_keyDown_withControl() {
        let message = AESPMessage.keyDown(keyChar: 0x01, keyCode: 0x3F, shift: false, control: true)
        let encoded = message.encode()

        // Flags: shift=false, control=true = 0x02
        XCTAssertEqual(encoded[10], 0x02)
    }

    /// Test encoding KEY_DOWN with both modifiers.
    func test_encode_keyDown_withBothModifiers() {
        let message = AESPMessage.keyDown(keyChar: 0x01, keyCode: 0x3F, shift: true, control: true)
        let encoded = message.encode()

        // Flags: shift=true, control=true = 0x03
        XCTAssertEqual(encoded[10], 0x03)
    }

    /// Test encoding KEY_UP message.
    func test_encode_keyUp() {
        let message = AESPMessage.keyUp()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.keyUp.rawValue)
    }

    /// Test encoding JOYSTICK message.
    func test_encode_joystick() {
        // Port 0, up+trigger
        let message = AESPMessage.joystick(port: 0, directions: 0x01, trigger: true)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 10) // 8 header + 2 payload
        XCTAssertEqual(encoded[3], AESPMessageType.joystick.rawValue)

        // Port
        XCTAssertEqual(encoded[8], 0x00)
        // Directions + trigger: up (0x01) | trigger (0x10) = 0x11
        XCTAssertEqual(encoded[9], 0x11)
    }

    /// Test encoding CONSOLE_KEYS message.
    func test_encode_consoleKeys() {
        let message = AESPMessage.consoleKeys(start: true, select: false, option: true)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[3], AESPMessageType.consoleKeys.rawValue)

        // Flags: start=0x01, option=0x04 = 0x05
        XCTAssertEqual(encoded[8], 0x05)
    }

    /// Test encoding VIDEO_SUBSCRIBE message.
    func test_encode_videoSubscribe() {
        let message = AESPMessage.videoSubscribe(deltaEncoding: false)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[3], AESPMessageType.videoSubscribe.rawValue)
        XCTAssertEqual(encoded[8], 0x00) // Raw format
    }

    /// Test encoding VIDEO_SUBSCRIBE with delta encoding.
    func test_encode_videoSubscribe_delta() {
        let message = AESPMessage.videoSubscribe(deltaEncoding: true)
        let encoded = message.encode()

        XCTAssertEqual(encoded[8], 0x01) // Delta format
    }

    /// Test encoding AUDIO_SYNC message.
    func test_encode_audioSync() {
        let frameNumber: UInt64 = 0x0102030405060708
        let message = AESPMessage.audioSync(frameNumber: frameNumber)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 16) // 8 header + 8 frame number
        XCTAssertEqual(encoded[3], AESPMessageType.audioSync.rawValue)

        // Frame number (big-endian)
        XCTAssertEqual(encoded[8], 0x01)
        XCTAssertEqual(encoded[9], 0x02)
        XCTAssertEqual(encoded[10], 0x03)
        XCTAssertEqual(encoded[11], 0x04)
        XCTAssertEqual(encoded[12], 0x05)
        XCTAssertEqual(encoded[13], 0x06)
        XCTAssertEqual(encoded[14], 0x07)
        XCTAssertEqual(encoded[15], 0x08)
    }

    /// Test encoding ERROR message.
    func test_encode_error() {
        let message = AESPMessage.error(code: 0x01, message: "Test error")
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.error.rawValue)
        XCTAssertEqual(encoded[8], 0x01) // Error code

        // Error message follows
        let messageBytes = Array(encoded[9...])
        XCTAssertEqual(String(bytes: messageBytes, encoding: .utf8), "Test error")
    }

    /// Test encoding FRAME_RAW message.
    func test_encode_frameRaw() {
        // Create a small test frame
        let pixels: [UInt8] = Array(repeating: 0xAB, count: 100)
        let message = AESPMessage.frameRaw(pixels: pixels)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 108) // 8 header + 100 pixels
        XCTAssertEqual(encoded[3], AESPMessageType.frameRaw.rawValue)

        // Length should be 100
        let length = UInt32(encoded[4]) << 24 | UInt32(encoded[5]) << 16 |
                     UInt32(encoded[6]) << 8 | UInt32(encoded[7])
        XCTAssertEqual(length, 100)
    }
}

// =============================================================================
// MARK: - Message Decoding Tests
// =============================================================================

/// Tests for AESP message decoding.
final class AESPMessageDecodingTests: XCTestCase {

    /// Test decoding valid PING message.
    func test_decode_ping() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        let (message, consumed) = try AESPMessage.decode(from: data)

        XCTAssertEqual(message.type, .ping)
        XCTAssertEqual(message.payload.count, 0)
        XCTAssertEqual(consumed, 8)
    }

    /// Test decoding message with payload.
    func test_decode_messageWithPayload() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x04, 0x00, 0x00, 0x00, 0x01, 0xFF])
        let (message, consumed) = try AESPMessage.decode(from: data)

        XCTAssertEqual(message.type, .reset)
        XCTAssertEqual(message.payload.count, 1)
        XCTAssertEqual(message.payload[0], 0xFF)
        XCTAssertEqual(consumed, 9)
    }

    /// Test decoding fails with insufficient data.
    func test_decode_insufficientData_header() {
        let data = Data([0xAE, 0x50, 0x01, 0x00]) // Only 4 bytes

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.insufficientData(let expected, let received) = error else {
                XCTFail("Expected insufficientData error")
                return
            }
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(received, 4)
        }
    }

    /// Test decoding fails with insufficient payload data.
    func test_decode_insufficientData_payload() {
        // Header says 10 bytes payload, but only 5 provided
        let data = Data([0xAE, 0x50, 0x01, 0x04, 0x00, 0x00, 0x00, 0x0A,
                        0x01, 0x02, 0x03, 0x04, 0x05])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.insufficientData(let expected, let received) = error else {
                XCTFail("Expected insufficientData error")
                return
            }
            XCTAssertEqual(expected, 18) // 8 header + 10 payload
            XCTAssertEqual(received, 13)
        }
    }

    /// Test decoding fails with invalid magic.
    func test_decode_invalidMagic() {
        let data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.invalidMagic(let received) = error else {
                XCTFail("Expected invalidMagic error")
                return
            }
            XCTAssertEqual(received, 0x0000)
        }
    }

    /// Test decoding fails with wrong magic high byte.
    func test_decode_invalidMagic_highByte() {
        let data = Data([0xFF, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.invalidMagic(let received) = error else {
                XCTFail("Expected invalidMagic error")
                return
            }
            XCTAssertEqual(received, 0xFF50)
        }
    }

    /// Test decoding fails with wrong magic low byte.
    func test_decode_invalidMagic_lowByte() {
        let data = Data([0xAE, 0xFF, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.invalidMagic(let received) = error else {
                XCTFail("Expected invalidMagic error")
                return
            }
            XCTAssertEqual(received, 0xAEFF)
        }
    }

    /// Test decoding fails with unsupported version 0.
    func test_decode_unsupportedVersion_zero() {
        let data = Data([0xAE, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.unsupportedVersion(let received) = error else {
                XCTFail("Expected unsupportedVersion error")
                return
            }
            XCTAssertEqual(received, 0x00)
        }
    }

    /// Test decoding fails with unsupported version 2.
    func test_decode_unsupportedVersion_two() {
        let data = Data([0xAE, 0x50, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.unsupportedVersion(let received) = error else {
                XCTFail("Expected unsupportedVersion error")
                return
            }
            XCTAssertEqual(received, 0x02)
        }
    }

    /// Test decoding fails with unknown message type.
    func test_decode_unknownMessageType() {
        let data = Data([0xAE, 0x50, 0x01, 0xFE, 0x00, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.unknownMessageType(let rawValue) = error else {
                XCTFail("Expected unknownMessageType error")
                return
            }
            XCTAssertEqual(rawValue, 0xFE)
        }
    }

    /// Test decoding fails with payload too large.
    func test_decode_payloadTooLarge() {
        // Set length to > 16 MB
        let data = Data([0xAE, 0x50, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00])

        XCTAssertThrowsError(try AESPMessage.decode(from: data)) { error in
            guard case AESPError.payloadTooLarge(let size) = error else {
                XCTFail("Expected payloadTooLarge error")
                return
            }
            XCTAssertEqual(size, 0x02000000)
        }
    }

    /// Test decoding KEY_DOWN message.
    func test_decode_keyDown() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x40, 0x00, 0x00, 0x00, 0x03,
                        0x41, 0x3F, 0x03]) // 'A', keycode, shift+ctrl
        let (message, _) = try AESPMessage.decode(from: data)

        guard let (keyChar, keyCode, shift, control) = message.parseKeyPayload() else {
            XCTFail("Failed to parse key payload")
            return
        }

        XCTAssertEqual(keyChar, 0x41)
        XCTAssertEqual(keyCode, 0x3F)
        XCTAssertTrue(shift)
        XCTAssertTrue(control)
    }

    /// Test decoding JOYSTICK message.
    func test_decode_joystick() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x42, 0x00, 0x00, 0x00, 0x02,
                        0x00, 0x15]) // Port 0, up+left+trigger
        let (message, _) = try AESPMessage.decode(from: data)

        guard let (port, up, down, left, right, trigger) = message.parseJoystickPayload() else {
            XCTFail("Failed to parse joystick payload")
            return
        }

        XCTAssertEqual(port, 0)
        XCTAssertTrue(up)
        XCTAssertFalse(down)
        XCTAssertTrue(left)
        XCTAssertFalse(right)
        XCTAssertTrue(trigger)
    }

    /// Test decoding CONSOLE_KEYS message.
    func test_decode_consoleKeys() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x43, 0x00, 0x00, 0x00, 0x01,
                        0x05]) // START + OPTION
        let (message, _) = try AESPMessage.decode(from: data)

        guard let (start, select, option) = message.parseConsoleKeysPayload() else {
            XCTFail("Failed to parse console keys payload")
            return
        }

        XCTAssertTrue(start)
        XCTAssertFalse(select)
        XCTAssertTrue(option)
    }

    /// Test decoding ERROR message.
    func test_decode_error() throws {
        let errorMsg = "Test error"
        var data = Data([0xAE, 0x50, 0x01, 0x3F, 0x00, 0x00, 0x00])
        data.append(UInt8(1 + errorMsg.utf8.count))
        data.append(0x01) // Error code
        data.append(contentsOf: errorMsg.utf8)

        let (message, _) = try AESPMessage.decode(from: data)

        guard let (code, msg) = message.parseErrorPayload() else {
            XCTFail("Failed to parse error payload")
            return
        }

        XCTAssertEqual(code, 0x01)
        XCTAssertEqual(msg, "Test error")
    }

    /// Test decoding AUDIO_SYNC message.
    func test_decode_audioSync() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x82, 0x00, 0x00, 0x00, 0x08,
                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let frameNumber = message.parseAudioSyncPayload() else {
            XCTFail("Failed to parse audio sync payload")
            return
        }

        XCTAssertEqual(frameNumber, 256) // 0x0100
    }

    /// Test messageSize returns nil for incomplete data.
    func test_messageSize_incompleteHeader() {
        let data = Data([0xAE, 0x50, 0x01])
        XCTAssertNil(AESPMessage.messageSize(in: data))
    }

    /// Test messageSize returns nil for invalid magic.
    func test_messageSize_invalidMagic() {
        let data = Data([0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertNil(AESPMessage.messageSize(in: data))
    }

    /// Test messageSize returns nil for incomplete payload.
    func test_messageSize_incompletePayload() {
        // Header says 10 bytes payload, but only 5 bytes total after header
        let data = Data([0xAE, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x0A,
                        0x01, 0x02, 0x03, 0x04, 0x05])
        XCTAssertNil(AESPMessage.messageSize(in: data))
    }

    /// Test messageSize returns correct size.
    func test_messageSize_complete() {
        let data = Data([0xAE, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00, 0x04,
                        0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual(AESPMessage.messageSize(in: data), 12)
    }
}

// =============================================================================
// MARK: - Round-trip Tests
// =============================================================================

/// Tests for encode-decode round-trips.
final class AESPMessageRoundtripTests: XCTestCase {

    /// Test PING round-trip.
    func test_roundtrip_ping() throws {
        let original = AESPMessage.ping()
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.payload, original.payload)
    }

    /// Test PONG round-trip.
    func test_roundtrip_pong() throws {
        let original = AESPMessage.pong()
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, original.type)
    }

    /// Test RESET round-trip.
    func test_roundtrip_reset() throws {
        let original = AESPMessage.reset(cold: true)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.payload, original.payload)
    }

    /// Test ACK round-trip.
    func test_roundtrip_ack() throws {
        let original = AESPMessage.ack(for: .pause)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .ack)
        XCTAssertEqual(decoded.payload[0], AESPMessageType.pause.rawValue)
    }

    /// Test KEY_DOWN round-trip.
    func test_roundtrip_keyDown() throws {
        let original = AESPMessage.keyDown(keyChar: 0x52, keyCode: 0x28, shift: true, control: false)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (keyChar, keyCode, shift, control) = decoded.parseKeyPayload() else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(keyChar, 0x52)
        XCTAssertEqual(keyCode, 0x28)
        XCTAssertTrue(shift)
        XCTAssertFalse(control)
    }

    /// Test JOYSTICK round-trip.
    func test_roundtrip_joystick() throws {
        let original = AESPMessage.joystick(port: 1, directions: 0x0A, trigger: true)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (port, up, down, left, right, trigger) = decoded.parseJoystickPayload() else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(port, 1)
        XCTAssertFalse(up)
        XCTAssertTrue(down)
        XCTAssertFalse(left)
        XCTAssertTrue(right)
        XCTAssertTrue(trigger)
    }

    /// Test CONSOLE_KEYS round-trip.
    func test_roundtrip_consoleKeys() throws {
        let original = AESPMessage.consoleKeys(start: false, select: true, option: false)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (start, select, option) = decoded.parseConsoleKeysPayload() else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertFalse(start)
        XCTAssertTrue(select)
        XCTAssertFalse(option)
    }

    /// Test VIDEO_SUBSCRIBE round-trip.
    func test_roundtrip_videoSubscribe() throws {
        let original = AESPMessage.videoSubscribe(deltaEncoding: true)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .videoSubscribe)
        XCTAssertEqual(decoded.payload[0], 0x01)
    }

    /// Test AUDIO_SYNC round-trip.
    func test_roundtrip_audioSync() throws {
        let original = AESPMessage.audioSync(frameNumber: 123456789)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let frameNumber = decoded.parseAudioSyncPayload() else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(frameNumber, 123456789)
    }

    /// Test ERROR round-trip.
    func test_roundtrip_error() throws {
        let original = AESPMessage.error(code: 0x05, message: "Not implemented")
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (code, message) = decoded.parseErrorPayload() else {
            XCTFail("Failed to parse")
            return
        }

        XCTAssertEqual(code, 0x05)
        XCTAssertEqual(message, "Not implemented")
    }

    /// Test FRAME_RAW round-trip with actual frame size.
    func test_roundtrip_frameRaw() throws {
        // Create a test frame (smaller than actual for speed)
        let pixels: [UInt8] = (0..<1000).map { UInt8($0 & 0xFF) }
        let original = AESPMessage.frameRaw(pixels: pixels)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .frameRaw)
        XCTAssertEqual(Array(decoded.payload), pixels)
    }

    /// Test AUDIO_PCM round-trip.
    func test_roundtrip_audioPCM() throws {
        let samples = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        let original = AESPMessage.audioPCM(samples: samples)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .audioPCM)
        XCTAssertEqual(decoded.payload, samples)
    }

    /// Test all message types round-trip.
    func test_roundtrip_allTypes() throws {
        for type in AESPMessageType.allCases {
            let original = AESPMessage(type: type)
            let encoded = original.encode()
            let (decoded, _) = try AESPMessage.decode(from: encoded)

            XCTAssertEqual(decoded.type, type, "Round-trip failed for \(type)")
        }
    }
}

// =============================================================================
// MARK: - Error Description Tests
// =============================================================================

/// Tests for AESP error descriptions.
final class AESPErrorTests: XCTestCase {

    /// Test invalidMagic error description.
    func test_errorDescription_invalidMagic() {
        let error = AESPError.invalidMagic(received: 0x1234)
        XCTAssertTrue(error.description.contains("0x1234"))
        XCTAssertTrue(error.description.contains("0xAE50"))
    }

    /// Test unsupportedVersion error description.
    func test_errorDescription_unsupportedVersion() {
        let error = AESPError.unsupportedVersion(received: 0x02)
        XCTAssertTrue(error.description.contains("2"))
    }

    /// Test unknownMessageType error description.
    func test_errorDescription_unknownMessageType() {
        let error = AESPError.unknownMessageType(rawValue: 0xFE)
        XCTAssertTrue(error.description.contains("0xFE"))
    }

    /// Test payloadTooLarge error description.
    func test_errorDescription_payloadTooLarge() {
        let error = AESPError.payloadTooLarge(size: 20_000_000)
        XCTAssertTrue(error.description.contains("20000000"))
    }

    /// Test insufficientData error description.
    func test_errorDescription_insufficientData() {
        let error = AESPError.insufficientData(expected: 100, received: 50)
        XCTAssertTrue(error.description.contains("100"))
        XCTAssertTrue(error.description.contains("50"))
    }

    /// Test connectionError error description.
    func test_errorDescription_connectionError() {
        let error = AESPError.connectionError("Connection refused")
        XCTAssertTrue(error.description.contains("Connection refused"))
    }

    /// Test serverError error description.
    func test_errorDescription_serverError() {
        let error = AESPError.serverError(code: 5, message: "Not implemented")
        XCTAssertTrue(error.description.contains("5"))
        XCTAssertTrue(error.description.contains("Not implemented"))
    }
}

// =============================================================================
// MARK: - Message Equatable Tests
// =============================================================================

/// Tests for AESPMessage Equatable conformance.
final class AESPMessageEquatableTests: XCTestCase {

    /// Test equal messages.
    func test_equal_sameTypeAndPayload() {
        let msg1 = AESPMessage.reset(cold: true)
        let msg2 = AESPMessage.reset(cold: true)

        XCTAssertEqual(msg1, msg2)
    }

    /// Test unequal messages - different type.
    func test_notEqual_differentType() {
        let msg1 = AESPMessage.ping()
        let msg2 = AESPMessage.pong()

        XCTAssertNotEqual(msg1, msg2)
    }

    /// Test unequal messages - different payload.
    func test_notEqual_differentPayload() {
        let msg1 = AESPMessage.reset(cold: true)
        let msg2 = AESPMessage.reset(cold: false)

        XCTAssertNotEqual(msg1, msg2)
    }
}

// =============================================================================
// MARK: - Multiple Messages in Buffer Tests
// =============================================================================

/// Tests for parsing multiple messages from a buffer.
final class AESPMessageBufferTests: XCTestCase {

    /// Test decoding multiple messages from buffer.
    func test_decodeMultipleMessages() throws {
        let msg1 = AESPMessage.ping()
        let msg2 = AESPMessage.pong()
        let msg3 = AESPMessage.reset(cold: true)

        var buffer = Data()
        buffer.append(msg1.encode())
        buffer.append(msg2.encode())
        buffer.append(msg3.encode())

        var decoded: [AESPMessage] = []
        var offset = 0

        while let size = AESPMessage.messageSize(in: buffer.subdata(in: offset..<buffer.count)) {
            let (message, _) = try AESPMessage.decode(from: buffer.subdata(in: offset..<buffer.count))
            decoded.append(message)
            offset += size
        }

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].type, .ping)
        XCTAssertEqual(decoded[1].type, .pong)
        XCTAssertEqual(decoded[2].type, .reset)
    }

    /// Test buffer with trailing partial message.
    func test_bufferWithPartialMessage() {
        let complete = AESPMessage.ping().encode()
        let partial = Data([0xAE, 0x50, 0x01]) // Incomplete header

        var buffer = Data()
        buffer.append(complete)
        buffer.append(partial)

        // First message should be found
        XCTAssertEqual(AESPMessage.messageSize(in: buffer), 8)

        // After removing first message, no complete message
        let remaining = buffer.subdata(in: 8..<buffer.count)
        XCTAssertNil(AESPMessage.messageSize(in: remaining))
    }
}

// =============================================================================
// MARK: - CustomStringConvertible Tests
// =============================================================================

/// Tests for message description formatting.
final class AESPMessageDescriptionTests: XCTestCase {

    /// Test message description format.
    func test_description_format() {
        let message = AESPMessage.reset(cold: true)
        let description = message.description

        XCTAssertTrue(description.contains("RESET"))
        XCTAssertTrue(description.contains("1 bytes"))
    }

    /// Test message type description.
    func test_typeDescription() {
        let type = AESPMessageType.keyDown
        let description = type.description

        XCTAssertTrue(description.contains("KEY_DOWN"))
        XCTAssertTrue(description.contains("0x40"))
    }
}
