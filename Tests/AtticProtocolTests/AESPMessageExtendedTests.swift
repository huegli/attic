// =============================================================================
// AESPMessageExtendedTests.swift - Extended Protocol Coverage Tests
// =============================================================================
//
// This file provides additional tests for AESP message types not fully covered
// in the main test file. These tests ensure complete protocol coverage per
// docs/PROTOCOL.md specification.
//
// Coverage includes:
// - PAUSE/RESUME individual tests
// - INFO message
// - REGISTERS_READ/WRITE
// - BREAKPOINT_SET/CLEAR/LIST/HIT
// - PADDLE
// - FRAME_DELTA/CONFIG
// - VIDEO_UNSUBSCRIBE
// - AUDIO_CONFIG/SUBSCRIBE/UNSUBSCRIBE
// - STATUS message
//
// =============================================================================

import XCTest
@testable import AtticProtocol

// =============================================================================
// MARK: - Control Message Extended Tests
// =============================================================================

/// Extended tests for control messages.
final class AESPControlMessageExtendedTests: XCTestCase {

    // =========================================================================
    // MARK: - PAUSE/RESUME Tests
    // =========================================================================

    /// Test encoding PAUSE message.
    func test_encode_pause() {
        let message = AESPMessage.pause()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.pause.rawValue)
        XCTAssertEqual(encoded[3], 0x02)
    }

    /// Test encoding RESUME message.
    func test_encode_resume() {
        let message = AESPMessage.resume()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.resume.rawValue)
        XCTAssertEqual(encoded[3], 0x03)
    }

    /// Test PAUSE round-trip.
    func test_roundtrip_pause() throws {
        let original = AESPMessage.pause()
        let encoded = original.encode()
        let (decoded, consumed) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .pause)
        XCTAssertEqual(decoded.payload.count, 0)
        XCTAssertEqual(consumed, 8)
    }

    /// Test RESUME round-trip.
    func test_roundtrip_resume() throws {
        let original = AESPMessage.resume()
        let encoded = original.encode()
        let (decoded, consumed) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .resume)
        XCTAssertEqual(decoded.payload.count, 0)
        XCTAssertEqual(consumed, 8)
    }

    // =========================================================================
    // MARK: - STATUS Tests
    // =========================================================================

    /// Test encoding STATUS request message.
    func test_encode_statusRequest() {
        let message = AESPMessage.status()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.status.rawValue)
        XCTAssertEqual(encoded[3], 0x05)
    }

    /// Test encoding STATUS response with running state.
    func test_encode_statusResponse_running() {
        let message = AESPMessage.statusResponse(isRunning: true)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[3], AESPMessageType.status.rawValue)
        XCTAssertEqual(encoded[8], 0x01) // Running
    }

    /// Test encoding STATUS response with paused state.
    func test_encode_statusResponse_paused() {
        let message = AESPMessage.statusResponse(isRunning: false)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[8], 0x00) // Paused
    }

    /// Test decoding STATUS response.
    func test_decode_statusResponse() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x05, 0x00, 0x00, 0x00, 0x01, 0x01])
        let (message, _) = try AESPMessage.decode(from: data)

        XCTAssertEqual(message.type, .status)
        guard let isRunning = message.parseStatusPayload() else {
            XCTFail("Failed to parse status payload")
            return
        }
        XCTAssertTrue(isRunning)
    }

    /// Test STATUS round-trip.
    func test_roundtrip_status() throws {
        let original = AESPMessage.statusResponse(isRunning: true)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let isRunning = decoded.parseStatusPayload() else {
            XCTFail("Failed to parse status payload")
            return
        }
        XCTAssertTrue(isRunning)
    }

    // =========================================================================
    // MARK: - INFO Tests
    // =========================================================================

    /// Test encoding INFO request message.
    func test_encode_infoRequest() {
        let message = AESPMessage.info()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.info.rawValue)
        XCTAssertEqual(encoded[3], 0x06)
    }

    /// Test encoding INFO response with JSON payload.
    func test_encode_infoResponse() {
        let jsonPayload = "{\"version\":\"1.0\",\"name\":\"Attic\"}"
        let message = AESPMessage.infoResponse(json: jsonPayload)
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.info.rawValue)
        XCTAssertEqual(encoded.count, 8 + jsonPayload.utf8.count)
    }

    /// Test decoding INFO response.
    func test_decode_infoResponse() throws {
        let jsonPayload = "{\"version\":\"1.0\"}"
        var data = Data([0xAE, 0x50, 0x01, 0x06, 0x00, 0x00, 0x00])
        data.append(UInt8(jsonPayload.utf8.count))
        data.append(contentsOf: jsonPayload.utf8)

        let (message, _) = try AESPMessage.decode(from: data)

        guard let json = message.parseInfoPayload() else {
            XCTFail("Failed to parse info payload")
            return
        }
        XCTAssertEqual(json, jsonPayload)
    }

    /// Test INFO round-trip.
    func test_roundtrip_info() throws {
        let json = "{\"version\":\"1.0\",\"capabilities\":[\"video\",\"audio\"]}"
        let original = AESPMessage.infoResponse(json: json)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let parsedJson = decoded.parseInfoPayload() else {
            XCTFail("Failed to parse info payload")
            return
        }
        XCTAssertEqual(parsedJson, json)
    }

    // =========================================================================
    // MARK: - BOOT_FILE Tests
    // =========================================================================

    /// Test encoding BOOT_FILE request message.
    func test_encode_bootFile() {
        let message = AESPMessage.bootFile(filePath: "/path/to/game.atr")
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.bootFile.rawValue)
        XCTAssertEqual(encoded[3], 0x07)

        // Payload should be UTF-8 encoded file path
        let payloadBytes = encoded[8...]
        let path = String(decoding: payloadBytes, as: UTF8.self)
        XCTAssertEqual(path, "/path/to/game.atr")
    }

    /// Test decoding BOOT_FILE request message.
    func test_decode_bootFile() throws {
        let filePath = "/Users/test/game.xex"
        var data = Data([0xAE, 0x50, 0x01, 0x07, 0x00, 0x00, 0x00])
        data.append(UInt8(filePath.utf8.count))
        data.append(contentsOf: filePath.utf8)

        let (message, _) = try AESPMessage.decode(from: data)

        guard let parsedPath = message.parseBootFileRequest() else {
            XCTFail("Failed to parse boot file request")
            return
        }
        XCTAssertEqual(parsedPath, filePath)
    }

    /// Test encoding BOOT_FILE response with success.
    func test_encode_bootFileResponse_success() {
        let message = AESPMessage.bootFileResponse(success: true, message: "Loaded ATR disk image")
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.bootFile.rawValue)
        XCTAssertEqual(encoded[8], 0x00) // success = 0x00
    }

    /// Test encoding BOOT_FILE response with failure.
    func test_encode_bootFileResponse_failure() {
        let message = AESPMessage.bootFileResponse(success: false, message: "File not found")
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.bootFile.rawValue)
        XCTAssertEqual(encoded[8], 0x01) // failure = 0x01
    }

    /// Test decoding BOOT_FILE response with success.
    func test_decode_bootFileResponse_success() throws {
        let msg = "Loaded ATR disk image"
        var data = Data([0xAE, 0x50, 0x01, 0x07, 0x00, 0x00, 0x00])
        data.append(UInt8(1 + msg.utf8.count))
        data.append(0x00) // success
        data.append(contentsOf: msg.utf8)

        let (message, _) = try AESPMessage.decode(from: data)

        guard let (success, responseMsg) = message.parseBootFileResponse() else {
            XCTFail("Failed to parse boot file response")
            return
        }
        XCTAssertTrue(success)
        XCTAssertEqual(responseMsg, msg)
    }

    /// Test decoding BOOT_FILE response with failure.
    func test_decode_bootFileResponse_failure() throws {
        let msg = "File not found"
        var data = Data([0xAE, 0x50, 0x01, 0x07, 0x00, 0x00, 0x00])
        data.append(UInt8(1 + msg.utf8.count))
        data.append(0x01) // failure
        data.append(contentsOf: msg.utf8)

        let (message, _) = try AESPMessage.decode(from: data)

        guard let (success, responseMsg) = message.parseBootFileResponse() else {
            XCTFail("Failed to parse boot file response")
            return
        }
        XCTAssertFalse(success)
        XCTAssertEqual(responseMsg, msg)
    }

    /// Test BOOT_FILE request round-trip.
    func test_roundtrip_bootFile() throws {
        let filePath = "/Users/test/my game/starraiders.atr"
        let original = AESPMessage.bootFile(filePath: filePath)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let parsedPath = decoded.parseBootFileRequest() else {
            XCTFail("Failed to parse boot file request")
            return
        }
        XCTAssertEqual(parsedPath, filePath)
    }

    /// Test BOOT_FILE response round-trip.
    func test_roundtrip_bootFileResponse() throws {
        let original = AESPMessage.bootFileResponse(success: true, message: "Loaded XEX executable")
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (success, message) = decoded.parseBootFileResponse() else {
            XCTFail("Failed to parse boot file response")
            return
        }
        XCTAssertTrue(success)
        XCTAssertEqual(message, "Loaded XEX executable")
    }

    /// Test BOOT_FILE message properties.
    func test_bootFile_properties() {
        XCTAssertEqual(AESPMessageType.bootFile.rawValue, 0x07)
        XCTAssertEqual(AESPMessageType.bootFile.category, .control)
        XCTAssertTrue(AESPMessageType.bootFile.isRequest)
        XCTAssertFalse(AESPMessageType.bootFile.isResponse)
        XCTAssertEqual(AESPMessageType.bootFile.name, "BOOT_FILE")
    }

    // =========================================================================
    // MARK: - REGISTERS Tests
    // =========================================================================

    /// Test encoding REGISTERS_READ request.
    func test_encode_registersRead() {
        let message = AESPMessage.registersRead()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.registersRead.rawValue)
        XCTAssertEqual(encoded[3], 0x12)
    }

    /// Test encoding REGISTERS_READ response with register values.
    func test_encode_registersResponse() {
        let message = AESPMessage.registersResponse(
            a: 0x42, x: 0x10, y: 0x20, s: 0xFF, p: 0x34, pc: 0xE477
        )
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 16) // 8 header + 8 payload
        XCTAssertEqual(encoded[3], AESPMessageType.registersRead.rawValue)

        // A, X, Y, S, P
        XCTAssertEqual(encoded[8], 0x42)   // A
        XCTAssertEqual(encoded[9], 0x10)   // X
        XCTAssertEqual(encoded[10], 0x20)  // Y
        XCTAssertEqual(encoded[11], 0xFF)  // S
        XCTAssertEqual(encoded[12], 0x34)  // P

        // PC (big-endian)
        XCTAssertEqual(encoded[13], 0xE4)  // PC high
        XCTAssertEqual(encoded[14], 0x77)  // PC low

        // Reserved
        XCTAssertEqual(encoded[15], 0x00)
    }

    /// Test decoding REGISTERS_READ response.
    func test_decode_registersResponse() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x12, 0x00, 0x00, 0x00, 0x08,
                        0x42, 0x10, 0x20, 0xFF, 0x34, 0xE4, 0x77, 0x00])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let regs = message.parseRegistersPayload() else {
            XCTFail("Failed to parse registers payload")
            return
        }

        XCTAssertEqual(regs.a, 0x42)
        XCTAssertEqual(regs.x, 0x10)
        XCTAssertEqual(regs.y, 0x20)
        XCTAssertEqual(regs.s, 0xFF)
        XCTAssertEqual(regs.p, 0x34)
        XCTAssertEqual(regs.pc, 0xE477)
    }

    /// Test encoding REGISTERS_WRITE request.
    func test_encode_registersWrite() {
        let message = AESPMessage.registersWrite(
            a: 0x50, x: 0x00, y: 0x00, s: 0xFD, p: 0x30, pc: 0x0600
        )
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 16)
        XCTAssertEqual(encoded[3], AESPMessageType.registersWrite.rawValue)
        XCTAssertEqual(encoded[3], 0x13)
    }

    /// Test REGISTERS round-trip.
    func test_roundtrip_registers() throws {
        let original = AESPMessage.registersResponse(
            a: 0xAB, x: 0xCD, y: 0xEF, s: 0x12, p: 0x34, pc: 0x5678
        )
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let regs = decoded.parseRegistersPayload() else {
            XCTFail("Failed to parse registers")
            return
        }

        XCTAssertEqual(regs.a, 0xAB)
        XCTAssertEqual(regs.x, 0xCD)
        XCTAssertEqual(regs.y, 0xEF)
        XCTAssertEqual(regs.s, 0x12)
        XCTAssertEqual(regs.p, 0x34)
        XCTAssertEqual(regs.pc, 0x5678)
    }

    // =========================================================================
    // MARK: - BREAKPOINT Tests
    // =========================================================================

    /// Test encoding BREAKPOINT_SET message.
    func test_encode_breakpointSet() {
        let message = AESPMessage.breakpointSet(address: 0x0600)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 10) // 8 header + 2 address
        XCTAssertEqual(encoded[3], AESPMessageType.breakpointSet.rawValue)
        XCTAssertEqual(encoded[3], 0x20)

        // Address (big-endian)
        XCTAssertEqual(encoded[8], 0x06)
        XCTAssertEqual(encoded[9], 0x00)
    }

    /// Test encoding BREAKPOINT_CLEAR message.
    func test_encode_breakpointClear() {
        let message = AESPMessage.breakpointClear(address: 0xE477)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 10)
        XCTAssertEqual(encoded[3], AESPMessageType.breakpointClear.rawValue)
        XCTAssertEqual(encoded[3], 0x21)

        // Address (big-endian)
        XCTAssertEqual(encoded[8], 0xE4)
        XCTAssertEqual(encoded[9], 0x77)
    }

    /// Test encoding BREAKPOINT_LIST request.
    func test_encode_breakpointListRequest() {
        let message = AESPMessage.breakpointList()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.breakpointList.rawValue)
        XCTAssertEqual(encoded[3], 0x22)
    }

    /// Test encoding BREAKPOINT_LIST response with addresses.
    func test_encode_breakpointListResponse() {
        let addresses: [UInt16] = [0x0600, 0x0700, 0xE477]
        let message = AESPMessage.breakpointListResponse(addresses: addresses)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 14) // 8 header + 6 bytes (3 * 2)
        XCTAssertEqual(encoded[3], AESPMessageType.breakpointList.rawValue)

        // First address
        XCTAssertEqual(encoded[8], 0x06)
        XCTAssertEqual(encoded[9], 0x00)

        // Second address
        XCTAssertEqual(encoded[10], 0x07)
        XCTAssertEqual(encoded[11], 0x00)

        // Third address
        XCTAssertEqual(encoded[12], 0xE4)
        XCTAssertEqual(encoded[13], 0x77)
    }

    /// Test decoding BREAKPOINT_LIST response.
    func test_decode_breakpointListResponse() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x22, 0x00, 0x00, 0x00, 0x04,
                        0x06, 0x00, 0x07, 0x00])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let addresses = message.parseBreakpointListPayload() else {
            XCTFail("Failed to parse breakpoint list payload")
            return
        }

        XCTAssertEqual(addresses.count, 2)
        XCTAssertEqual(addresses[0], 0x0600)
        XCTAssertEqual(addresses[1], 0x0700)
    }

    /// Test encoding BREAKPOINT_HIT notification.
    func test_encode_breakpointHit() {
        let message = AESPMessage.breakpointHit(address: 0x0600)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 10)
        XCTAssertEqual(encoded[3], AESPMessageType.breakpointHit.rawValue)
        XCTAssertEqual(encoded[3], 0x23)

        // Address (big-endian)
        XCTAssertEqual(encoded[8], 0x06)
        XCTAssertEqual(encoded[9], 0x00)
    }

    /// Test decoding BREAKPOINT_HIT notification.
    func test_decode_breakpointHit() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x23, 0x00, 0x00, 0x00, 0x02,
                        0xE4, 0x77])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let address = message.parseBreakpointHitPayload() else {
            XCTFail("Failed to parse breakpoint hit payload")
            return
        }

        XCTAssertEqual(address, 0xE477)
    }

    /// Test BREAKPOINT_SET round-trip.
    func test_roundtrip_breakpointSet() throws {
        let original = AESPMessage.breakpointSet(address: 0xABCD)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .breakpointSet)

        // Parse the address from payload
        let address = UInt16(decoded.payload[0]) << 8 | UInt16(decoded.payload[1])
        XCTAssertEqual(address, 0xABCD)
    }
}

// =============================================================================
// MARK: - Input Message Extended Tests
// =============================================================================

/// Extended tests for input messages.
final class AESPInputMessageExtendedTests: XCTestCase {

    // =========================================================================
    // MARK: - PADDLE Tests
    // =========================================================================

    /// Test encoding PADDLE message.
    func test_encode_paddle() {
        let message = AESPMessage.paddle(number: 0, position: 128)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 10) // 8 header + 2 payload
        XCTAssertEqual(encoded[3], AESPMessageType.paddle.rawValue)
        XCTAssertEqual(encoded[3], 0x44)

        // Paddle number
        XCTAssertEqual(encoded[8], 0x00)
        // Position
        XCTAssertEqual(encoded[9], 0x80) // 128
    }

    /// Test encoding PADDLE message for paddle 3 at max position.
    func test_encode_paddle_max() {
        let message = AESPMessage.paddle(number: 3, position: 228)
        let encoded = message.encode()

        XCTAssertEqual(encoded[8], 0x03) // Paddle 3
        XCTAssertEqual(encoded[9], 228)  // Max position
    }

    /// Test decoding PADDLE message.
    func test_decode_paddle() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x44, 0x00, 0x00, 0x00, 0x02,
                        0x01, 0x64]) // Paddle 1, position 100
        let (message, _) = try AESPMessage.decode(from: data)

        guard let (number, position) = message.parsePaddlePayload() else {
            XCTFail("Failed to parse paddle payload")
            return
        }

        XCTAssertEqual(number, 1)
        XCTAssertEqual(position, 100)
    }

    /// Test PADDLE round-trip.
    func test_roundtrip_paddle() throws {
        let original = AESPMessage.paddle(number: 2, position: 200)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let (number, position) = decoded.parsePaddlePayload() else {
            XCTFail("Failed to parse paddle payload")
            return
        }

        XCTAssertEqual(number, 2)
        XCTAssertEqual(position, 200)
    }
}

// =============================================================================
// MARK: - Video Message Extended Tests
// =============================================================================

/// Extended tests for video messages.
final class AESPVideoMessageExtendedTests: XCTestCase {

    // =========================================================================
    // MARK: - FRAME_DELTA Tests
    // =========================================================================

    /// Test encoding FRAME_DELTA message.
    func test_encode_frameDelta() {
        // Delta format: [4 bytes count] + [changed pixels: 3 bytes index + 4 bytes BGRA]
        let changedPixels: [(index: Int, bgra: [UInt8])] = [
            (index: 100, bgra: [0xFF, 0x00, 0x00, 0xFF]),
            (index: 200, bgra: [0x00, 0xFF, 0x00, 0xFF])
        ]

        var payload = Data()
        // Count (big-endian)
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x02])

        for pixel in changedPixels {
            // Index (3 bytes, big-endian)
            payload.append(UInt8((pixel.index >> 16) & 0xFF))
            payload.append(UInt8((pixel.index >> 8) & 0xFF))
            payload.append(UInt8(pixel.index & 0xFF))
            // BGRA
            payload.append(contentsOf: pixel.bgra)
        }

        let message = AESPMessage.frameDelta(payload: payload)
        let encoded = message.encode()

        XCTAssertEqual(encoded[3], AESPMessageType.frameDelta.rawValue)
        XCTAssertEqual(encoded[3], 0x61)
    }

    /// Test decoding FRAME_DELTA message.
    func test_decode_frameDelta() throws {
        var data = Data([0xAE, 0x50, 0x01, 0x61, 0x00, 0x00, 0x00, 0x0B])
        // 1 changed pixel
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Count = 1
        data.append(contentsOf: [0x00, 0x00, 0x64])       // Index = 100
        data.append(contentsOf: [0xFF, 0x00, 0x00, 0xFF]) // BGRA

        let (message, _) = try AESPMessage.decode(from: data)

        XCTAssertEqual(message.type, .frameDelta)
        XCTAssertEqual(message.payload.count, 11)
    }

    // =========================================================================
    // MARK: - FRAME_CONFIG Tests
    // =========================================================================

    /// Test encoding FRAME_CONFIG message.
    func test_encode_frameConfig() {
        let message = AESPMessage.frameConfig(width: 384, height: 240, bytesPerPixel: 4, fps: 60)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 14) // 8 header + 6 payload
        XCTAssertEqual(encoded[3], AESPMessageType.frameConfig.rawValue)
        XCTAssertEqual(encoded[3], 0x62)

        // Width (big-endian): 384 = 0x0180
        XCTAssertEqual(encoded[8], 0x01)
        XCTAssertEqual(encoded[9], 0x80)

        // Height (big-endian): 240 = 0x00F0
        XCTAssertEqual(encoded[10], 0x00)
        XCTAssertEqual(encoded[11], 0xF0)

        // Bytes per pixel
        XCTAssertEqual(encoded[12], 0x04)

        // FPS
        XCTAssertEqual(encoded[13], 60)
    }

    /// Test decoding FRAME_CONFIG message.
    func test_decode_frameConfig() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x62, 0x00, 0x00, 0x00, 0x06,
                        0x01, 0x80, 0x00, 0xF0, 0x04, 0x3C])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let config = message.parseFrameConfigPayload() else {
            XCTFail("Failed to parse frame config payload")
            return
        }

        XCTAssertEqual(config.width, 384)
        XCTAssertEqual(config.height, 240)
        XCTAssertEqual(config.bytesPerPixel, 4)
        XCTAssertEqual(config.fps, 60)
    }

    /// Test FRAME_CONFIG round-trip.
    func test_roundtrip_frameConfig() throws {
        let original = AESPMessage.frameConfig(width: 320, height: 200, bytesPerPixel: 4, fps: 50)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let config = decoded.parseFrameConfigPayload() else {
            XCTFail("Failed to parse frame config payload")
            return
        }

        XCTAssertEqual(config.width, 320)
        XCTAssertEqual(config.height, 200)
        XCTAssertEqual(config.bytesPerPixel, 4)
        XCTAssertEqual(config.fps, 50)
    }

    // =========================================================================
    // MARK: - VIDEO_UNSUBSCRIBE Tests
    // =========================================================================

    /// Test encoding VIDEO_UNSUBSCRIBE message.
    func test_encode_videoUnsubscribe() {
        let message = AESPMessage.videoUnsubscribe()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.videoUnsubscribe.rawValue)
        XCTAssertEqual(encoded[3], 0x64)
    }

    /// Test VIDEO_UNSUBSCRIBE round-trip.
    func test_roundtrip_videoUnsubscribe() throws {
        let original = AESPMessage.videoUnsubscribe()
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .videoUnsubscribe)
        XCTAssertEqual(decoded.payload.count, 0)
    }
}

// =============================================================================
// MARK: - Audio Message Extended Tests
// =============================================================================

/// Extended tests for audio messages.
final class AESPAudioMessageExtendedTests: XCTestCase {

    // =========================================================================
    // MARK: - AUDIO_CONFIG Tests
    // =========================================================================

    /// Test encoding AUDIO_CONFIG message.
    func test_encode_audioConfig() {
        let message = AESPMessage.audioConfig(sampleRate: 44100, bitsPerSample: 16, channels: 1)
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 14) // 8 header + 6 payload
        XCTAssertEqual(encoded[3], AESPMessageType.audioConfig.rawValue)
        XCTAssertEqual(encoded[3], 0x81)

        // Sample rate (big-endian): 44100 = 0x0000AC44
        XCTAssertEqual(encoded[8], 0x00)
        XCTAssertEqual(encoded[9], 0x00)
        XCTAssertEqual(encoded[10], 0xAC)
        XCTAssertEqual(encoded[11], 0x44)

        // Bits per sample
        XCTAssertEqual(encoded[12], 16)

        // Channels
        XCTAssertEqual(encoded[13], 1)
    }

    /// Test decoding AUDIO_CONFIG message.
    func test_decode_audioConfig() throws {
        let data = Data([0xAE, 0x50, 0x01, 0x81, 0x00, 0x00, 0x00, 0x06,
                        0x00, 0x00, 0xAC, 0x44, 0x10, 0x01])
        let (message, _) = try AESPMessage.decode(from: data)

        guard let config = message.parseAudioConfigPayload() else {
            XCTFail("Failed to parse audio config payload")
            return
        }

        XCTAssertEqual(config.sampleRate, 44100)
        XCTAssertEqual(config.bitsPerSample, 16)
        XCTAssertEqual(config.channels, 1)
    }

    /// Test AUDIO_CONFIG round-trip.
    func test_roundtrip_audioConfig() throws {
        let original = AESPMessage.audioConfig(sampleRate: 48000, bitsPerSample: 24, channels: 2)
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        guard let config = decoded.parseAudioConfigPayload() else {
            XCTFail("Failed to parse audio config payload")
            return
        }

        XCTAssertEqual(config.sampleRate, 48000)
        XCTAssertEqual(config.bitsPerSample, 24)
        XCTAssertEqual(config.channels, 2)
    }

    // =========================================================================
    // MARK: - AUDIO_SUBSCRIBE/UNSUBSCRIBE Tests
    // =========================================================================

    /// Test encoding AUDIO_SUBSCRIBE message.
    func test_encode_audioSubscribe() {
        let message = AESPMessage.audioSubscribe()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.audioSubscribe.rawValue)
        XCTAssertEqual(encoded[3], 0x83)
    }

    /// Test encoding AUDIO_UNSUBSCRIBE message.
    func test_encode_audioUnsubscribe() {
        let message = AESPMessage.audioUnsubscribe()
        let encoded = message.encode()

        XCTAssertEqual(encoded.count, 8)
        XCTAssertEqual(encoded[3], AESPMessageType.audioUnsubscribe.rawValue)
        XCTAssertEqual(encoded[3], 0x84)
    }

    /// Test AUDIO_SUBSCRIBE round-trip.
    func test_roundtrip_audioSubscribe() throws {
        let original = AESPMessage.audioSubscribe()
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .audioSubscribe)
        XCTAssertEqual(decoded.payload.count, 0)
    }

    /// Test AUDIO_UNSUBSCRIBE round-trip.
    func test_roundtrip_audioUnsubscribe() throws {
        let original = AESPMessage.audioUnsubscribe()
        let encoded = original.encode()
        let (decoded, _) = try AESPMessage.decode(from: encoded)

        XCTAssertEqual(decoded.type, .audioUnsubscribe)
        XCTAssertEqual(decoded.payload.count, 0)
    }
}

// =============================================================================
// MARK: - Protocol Conformance Tests
// =============================================================================

/// Tests ensuring all message types are properly implemented.
final class AESPProtocolConformanceTests: XCTestCase {

    /// Test that all message types have valid raw values.
    func test_allMessageTypes_haveValidRawValues() {
        for type in AESPMessageType.allCases {
            // Should not crash
            _ = type.rawValue
            _ = type.name
            _ = type.category
            _ = type.isRequest
            _ = type.isResponse
        }
    }

    /// Test all control message raw values match PROTOCOL.md.
    func test_controlMessageRawValues() {
        XCTAssertEqual(AESPMessageType.ping.rawValue, 0x00)
        XCTAssertEqual(AESPMessageType.pong.rawValue, 0x01)
        XCTAssertEqual(AESPMessageType.pause.rawValue, 0x02)
        XCTAssertEqual(AESPMessageType.resume.rawValue, 0x03)
        XCTAssertEqual(AESPMessageType.reset.rawValue, 0x04)
        XCTAssertEqual(AESPMessageType.status.rawValue, 0x05)
        XCTAssertEqual(AESPMessageType.info.rawValue, 0x06)
        XCTAssertEqual(AESPMessageType.bootFile.rawValue, 0x07)
        XCTAssertEqual(AESPMessageType.ack.rawValue, 0x0F)
        XCTAssertEqual(AESPMessageType.memoryRead.rawValue, 0x10)
        XCTAssertEqual(AESPMessageType.memoryWrite.rawValue, 0x11)
        XCTAssertEqual(AESPMessageType.registersRead.rawValue, 0x12)
        XCTAssertEqual(AESPMessageType.registersWrite.rawValue, 0x13)
        XCTAssertEqual(AESPMessageType.breakpointSet.rawValue, 0x20)
        XCTAssertEqual(AESPMessageType.breakpointClear.rawValue, 0x21)
        XCTAssertEqual(AESPMessageType.breakpointList.rawValue, 0x22)
        XCTAssertEqual(AESPMessageType.breakpointHit.rawValue, 0x23)
        XCTAssertEqual(AESPMessageType.error.rawValue, 0x3F)
    }

    /// Test all input message raw values match PROTOCOL.md.
    func test_inputMessageRawValues() {
        XCTAssertEqual(AESPMessageType.keyDown.rawValue, 0x40)
        XCTAssertEqual(AESPMessageType.keyUp.rawValue, 0x41)
        XCTAssertEqual(AESPMessageType.joystick.rawValue, 0x42)
        XCTAssertEqual(AESPMessageType.consoleKeys.rawValue, 0x43)
        XCTAssertEqual(AESPMessageType.paddle.rawValue, 0x44)
    }

    /// Test all video message raw values match PROTOCOL.md.
    func test_videoMessageRawValues() {
        XCTAssertEqual(AESPMessageType.frameRaw.rawValue, 0x60)
        XCTAssertEqual(AESPMessageType.frameDelta.rawValue, 0x61)
        XCTAssertEqual(AESPMessageType.frameConfig.rawValue, 0x62)
        XCTAssertEqual(AESPMessageType.videoSubscribe.rawValue, 0x63)
        XCTAssertEqual(AESPMessageType.videoUnsubscribe.rawValue, 0x64)
    }

    /// Test all audio message raw values match PROTOCOL.md.
    func test_audioMessageRawValues() {
        XCTAssertEqual(AESPMessageType.audioPCM.rawValue, 0x80)
        XCTAssertEqual(AESPMessageType.audioConfig.rawValue, 0x81)
        XCTAssertEqual(AESPMessageType.audioSync.rawValue, 0x82)
        XCTAssertEqual(AESPMessageType.audioSubscribe.rawValue, 0x83)
        XCTAssertEqual(AESPMessageType.audioUnsubscribe.rawValue, 0x84)
    }

    /// Test all message types can be encoded and decoded.
    func test_allTypes_canEncodeAndDecode() throws {
        for type in AESPMessageType.allCases {
            let message = AESPMessage(type: type)
            let encoded = message.encode()

            // Verify header format
            XCTAssertEqual(encoded[0], 0xAE, "Wrong magic high for \(type)")
            XCTAssertEqual(encoded[1], 0x50, "Wrong magic low for \(type)")
            XCTAssertEqual(encoded[2], 0x01, "Wrong version for \(type)")
            XCTAssertEqual(encoded[3], type.rawValue, "Wrong type for \(type)")

            // Decode should succeed
            let (decoded, _) = try AESPMessage.decode(from: encoded)
            XCTAssertEqual(decoded.type, type, "Round-trip failed for \(type)")
        }
    }
}
